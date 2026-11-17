import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/scan_page.dart';
import '../../services/image_processing_service.dart';
import '../../services/ocr_service.dart';
import 'crop_screen.dart';
import 'scan_review_screen.dart';

/// Boucle de scan : photographier une page, ajuster la zone, recommencer.
///
/// La fluidité de cette boucle est ce qui rend le scan d'un chapitre entier
/// supportable — chaque validation du recadrage ramène directement ici, prêt
/// pour la page suivante.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({Key? key}) : super(key: key);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _cameraError;

  final List<ScanPage> _pages = [];
  bool _busy = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Sans ça, revenir d'arrière-plan laisse un aperçu noir — le grand
  /// classique du plugin `camera`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = AppLocalizations.of(context)!.camera_noCameraAvailable);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      final future = controller.initialize();
      setState(() {
        _controller = controller;
        _initFuture = future;
        _cameraError = null;
      });
      await future;
      await controller.setFlashMode(FlashMode.off);
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt';
      final l10n = AppLocalizations.of(context)!;
      setState(() => _cameraError = denied
          ? l10n.camera_accessDenied
          : l10n.camera_unavailableWithReason(e.description ?? e.code));
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = AppLocalizations.of(context)!.camera_unavailableWithReason('$e'));
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      // Certains appareils n'ont pas de torche : on ignore silencieusement.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;

    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      await _ingest([shot.path]);
    } catch (e) {
      if (!mounted) return;
      _toast(AppLocalizations.of(context)!.camera_captureFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
      await _ingest(picked.map((x) => x.path).toList());
    } catch (e) {
      if (!mounted) return;
      _toast(AppLocalizations.of(context)!.camera_importFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Normalise les images puis envoie la première au recadrage. Les suivantes
  /// (import multiple) sont ajoutées telles quelles : l'utilisateur les
  /// recadre depuis l'écran de révision s'il le souhaite.
  Future<void> _ingest(List<String> paths) async {
    final created = <ScanPage>[];
    for (final path in paths) {
      final prepared = await ImageProcessingService.prepareSource(path);
      created.add(ScanPage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sourcePath: prepared,
      ));
    }
    if (!mounted || created.isEmpty) return;

    setState(() => _pages.addAll(created));

    for (final page in created) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => CropScreen(page: page)),
      );
      if (!mounted) return;
      if (ok != true) {
        // Recadrage annulé : la page ne sert à rien sans texte.
        setState(() => _pages.remove(page));
      } else {
        setState(() {});
      }
    }
  }

  Future<void> _finish() async {
    if (_pages.isEmpty) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ScanReviewScreen(pages: _pages)),
    );
    if (!mounted) return;
    if (created == true) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {});
  }

  Future<void> _confirmQuit() async {
    if (_pages.isEmpty) {
      await OcrService.instance.dispose();
      await ImageProcessingService.clearSession();
      if (mounted) Navigator.pop(context);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.camera_abandonTitle),
        content: Text(l10n.camera_abandonBody(_pages.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.camera_continueScanning),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.camera_abandon,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (quit == true && mounted) {
      await OcrService.instance.dispose();
      await ImageProcessingService.clearSession();
      if (mounted) Navigator.pop(context);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_pages.isEmpty
              ? l10n.camera_scanBook
              : l10n.camera_pagesScanned(_pages.length)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmQuit,
          ),
          actions: [
            IconButton(
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              tooltip: l10n.camera_torch,
              onPressed: _toggleTorch,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreview(),
                  if (_busy)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Colors.white),
                            const SizedBox(height: 16),
                            Text(
                              l10n.camera_processingPhoto,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_pages.isNotEmpty) _buildThumbnails(),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final l10n = AppLocalizations.of(context)!;
    final error = _cameraError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: Text(l10n.camera_importFromGallery),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || _initFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _FramingGuidePainter()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThumbnails() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final page = _pages[i];
          final path = page.rectifiedPath ?? page.sourcePath;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(path),
                  key: ValueKey(path),
                  width: 46,
                  height: 62,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  color: page.hasText ? Colors.black87 : Colors.red,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Colors.black,
      // `SafeArea` seul, sans padding manuel en bas : sur les appareils en
      // edge-to-edge forcé (Samsung/Android 16), la barre de navigation
      // système passait par-dessus ces boutons sans elle.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.photo_library),
                tooltip: l10n.camera_gallery,
                onPressed: _busy ? null : _pickFromGallery,
              ),
              GestureDetector(
                onTap: _busy ? null : _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _busy ? Colors.grey : Colors.white,
                    border: Border.all(color: Colors.white24, width: 4),
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              TextButton(
                onPressed: _pages.isEmpty || _busy ? null : _finish,
                child: Text(l10n.camera_finish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cadre-guide discret : aide à poser la page bien dans le champ.
class _FramingGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.06,
      size.width * 0.88,
      size.height * 0.88,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white38;

    const corner = 28.0;
    for (final c in [
      [rect.topLeft, const Offset(corner, 0), const Offset(0, corner)],
      [rect.topRight, const Offset(-corner, 0), const Offset(0, corner)],
      [rect.bottomLeft, const Offset(corner, 0), const Offset(0, -corner)],
      [rect.bottomRight, const Offset(-corner, 0), const Offset(0, -corner)],
    ]) {
      canvas.drawLine(c[0], c[0] + c[1], paint);
      canvas.drawLine(c[0], c[0] + c[2], paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
