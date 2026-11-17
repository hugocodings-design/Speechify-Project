import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/scan_page.dart';
import '../../services/image_processing_service.dart';
import '../../services/ocr_service.dart';

/// Ajustement manuel de la zone de texte à capter.
///
/// Les 4 coins sont libres (quadrilatère quelconque) et l'image est ensuite
/// redressée : une page photographiée en biais redevient rectangulaire, ce qui
/// change beaucoup la qualité de l'OCR.
class CropScreen extends StatefulWidget {
  const CropScreen({Key? key, required this.page}) : super(key: key);

  /// Modifiée en place : à la validation, `rectifiedPath` et `recognizedText`
  /// sont renseignés.
  final ScanPage page;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  static const double _handleTouchRadius = 44;
  static const double _handleVisualRadius = 13;

  Size? _imageSize;
  int? _draggingCorner;
  Offset? _fingerScreenPos;
  bool _busy = false;
  String _busyLabel = '';

  late List<Offset> _quad = List.of(widget.page.quad);

  @override
  void initState() {
    super.initState();
    _loadAndAutoDetect();
  }

  Future<void> _loadAndAutoDetect() async {
    final size = await ImageProcessingService.imageSize(widget.page.sourcePath);
    if (!mounted) return;
    // Rend l'écran interactif tout de suite : l'utilisateur voit le cadre par
    // défaut et peut déjà le déplacer pendant que la détection tourne.
    setState(() => _imageSize = size);

    // Ne pas écraser un cadrage que l'utilisateur a déjà posé.
    if (!_isDefaultQuad(widget.page.quad)) return;
    unawaited(_autoDetect(silent: true, blocking: false));
  }

  bool _isDefaultQuad(List<Offset> q) {
    final d = ScanPage.defaultQuad();
    for (var i = 0; i < 4; i++) {
      if ((q[i] - d[i]).distance > 0.001) return false;
    }
    return true;
  }

  /// [blocking] affiche le voile de progression plein écran ; laissé à
  /// `false` pour la détection automatique au chargement, qui ne doit pas
  /// empêcher l'utilisateur de commencer à ajuster les coins à la main
  /// pendant qu'elle tourne en arrière-plan.
  Future<void> _autoDetect({bool silent = false, bool blocking = true}) async {
    final size = _imageSize;
    if (size == null) return;
    if (blocking) {
      setState(() {
        _busy = true;
        _busyLabel = AppLocalizations.of(context)!.crop_detectingTextArea;
      });
    }
    try {
      final bounds = await OcrService.instance
          .detectTextBounds(widget.page.sourcePath, size);
      if (!mounted) return;
      // Ne pas écraser un cadrage que l'utilisateur a posé pendant la
      // détection en arrière-plan.
      if (!blocking && !_isDefaultQuad(_quad)) return;
      if (bounds != null && bounds.width > 0.05 && bounds.height > 0.05) {
        setState(() => _quad = ScanPage.quadFromRect(bounds));
      } else if (!silent) {
        _toast(AppLocalizations.of(context)!.crop_noTextBlockDetected);
      }
    } catch (e) {
      if (!silent && mounted) _toast(AppLocalizations.of(context)!.crop_detectionFailed('$e'));
    } finally {
      if (blocking && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    setState(() {
      _busy = true;
      _busyLabel = AppLocalizations.of(context)!.crop_rotating;
    });
    try {
      final rotated =
          await ImageProcessingService.rotate90(widget.page.sourcePath);
      final size = await ImageProcessingService.imageSize(rotated);
      if (!mounted) return;
      setState(() {
        widget.page.sourcePath = rotated;
        _imageSize = size;
        // Le fichier sur le disque porte désormais la rotation, donc le
        // quadrilatère repart de zéro dans le nouveau référentiel.
        _quad = ScanPage.defaultQuad();
      });
      await _autoDetect(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_isConvex(_quad)) {
      _toast(l10n.crop_cornersOverlap);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = l10n.crop_rectifyingAndReading;
    });

    widget.page.quad = List.of(_quad);
    widget.page.status = ScanStatus.processing;

    try {
      final rectified = await ImageProcessingService.rectifyAndEnhance(
        widget.page.sourcePath,
        widget.page.flatQuad,
      );
      final text = await OcrService.instance.recognizeText(rectified);

      widget.page
        ..rectifiedPath = rectified
        ..recognizedText = text
        ..error = text.trim().isEmpty ? l10n.crop_noTextRecognized : null
        ..status = text.trim().isEmpty ? ScanStatus.failed : ScanStatus.done;

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      widget.page
        ..status = ScanStatus.failed
        ..error = '$e';
      if (mounted) {
        setState(() => _busy = false);
        _toast(l10n.crop_processingFailed('$e'));
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Rejette un quadrilatère « papillon » (côtés croisés), pour lequel le
  /// redressement produirait une bouillie.
  static bool _isConvex(List<Offset> q) {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = q[i];
      final b = q[(i + 1) % 4];
      final c = q[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.crop_adjustTextArea),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_cw),
            tooltip: l10n.crop_rotate,
            onPressed: _busy ? null : _rotate,
          ),
        ],
      ),
      body: imageSize == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildCanvas(imageSize)),
                _buildActions(),
              ],
            ),
    );
  }

  Widget _buildCanvas(Size imageSize) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Le rectangle réellement occupé par l'image en BoxFit.contain : c'est
        // le référentiel de conversion écran <-> coordonnées normalisées.
        final fitted = applyBoxFit(
          BoxFit.contain,
          imageSize,
          constraints.biggest,
        ).destination;
        final rect = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);

        Offset toScreen(Offset n) =>
            Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);
        Offset toNormalized(Offset s) => Offset(
              ((s.dx - rect.left) / rect.width).clamp(0.0, 1.0),
              ((s.dy - rect.top) / rect.height).clamp(0.0, 1.0),
            );

        final corners = _quad.map(toScreen).toList();

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.file(
                File(widget.page.sourcePath),
                key: ValueKey(widget.page.sourcePath),
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                var nearest = -1;
                var best = _handleTouchRadius;
                for (var i = 0; i < 4; i++) {
                  final dist = (corners[i] - d.localPosition).distance;
                  if (dist < best) {
                    best = dist;
                    nearest = i;
                  }
                }
                if (nearest >= 0) {
                  setState(() {
                    _draggingCorner = nearest;
                    _fingerScreenPos = d.localPosition;
                  });
                }
              },
              onPanUpdate: (d) {
                final i = _draggingCorner;
                if (i == null) return;
                setState(() {
                  _quad[i] = toNormalized(d.localPosition);
                  _fingerScreenPos = d.localPosition;
                });
              },
              onPanEnd: (_) => setState(() {
                _draggingCorner = null;
                _fingerScreenPos = null;
              }),
              child: CustomPaint(
                painter: _QuadPainter(corners: corners, imageRect: rect),
              ),
            ),
            if (_draggingCorner != null && _fingerScreenPos != null)
              _buildMagnifier(rect, corners[_draggingCorner!]),
            if (_busy)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _busyLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Loupe : indispensable pour poser un coin précisément, puisque le doigt
  /// masque exactement l'endroit qu'on vise.
  ///
  /// `RawMagnifier` agrandit ce qui est réellement peint dessous — donc
  /// l'image *et* le tracé du quadrilatère, ce qui aide à viser.
  Widget _buildMagnifier(Rect imageRect, Offset focus) {
    const side = 120.0;
    const margin = 16.0;
    final onLeft = focus.dx > imageRect.center.dx;
    final center = Offset(
      onLeft ? margin + side / 2 : imageRect.width + imageRect.left - margin - side / 2,
      margin + side / 2,
    );

    return Positioned(
      top: margin,
      left: onLeft ? margin : null,
      right: onLeft ? null : margin,
      child: RawMagnifier(
        size: const Size(side, side),
        magnificationScale: 2.5,
        focalPointOffset: focus - center,
        decoration: const MagnifierDecoration(
          shape: CircleBorder(
            side: BorderSide(color: Colors.cyanAccent, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Colors.black,
      // Idem que l'écran caméra : la barre de navigation système passait
      // par-dessus « Valider » sans `SafeArea` sur les appareils en
      // edge-to-edge forcé.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
          TextButton.icon(
            onPressed: _busy ? null : () => _autoDetect(),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(l10n.crop_auto),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _quad = ScanPage.defaultQuad()),
            icon: const Icon(Icons.crop_free),
            label: Text(l10n.crop_all),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: const Icon(Icons.check),
            label: Text(l10n.crop_confirm),
          ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.corners, required this.imageRect});

  final List<Offset> corners;
  final Rect imageRect;

  @override
  void paint(Canvas canvas, Size size) {
    final quadPath = Path()..addPolygon(corners, true);

    // Voile sombre partout sauf dans la sélection.
    final veil = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      quadPath,
    );
    canvas.drawPath(veil, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      quadPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.cyanAccent,
    );

    // Lignes de tiers, pour aider à aligner sur le bloc de texte.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.cyanAccent.withValues(alpha: 0.35);
    for (var i = 1; i < 3; i++) {
      final t = i / 3;
      canvas.drawLine(
        Offset.lerp(corners[0], corners[1], t)!,
        Offset.lerp(corners[3], corners[2], t)!,
        guide,
      );
      canvas.drawLine(
        Offset.lerp(corners[0], corners[3], t)!,
        Offset.lerp(corners[1], corners[2], t)!,
        guide,
      );
    }

    for (final c in corners) {
      canvas.drawCircle(
        c,
        _CropScreenState._handleVisualRadius,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        c,
        _CropScreenState._handleVisualRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.cyanAccent,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.corners != corners || old.imageRect != imageRect;
}
