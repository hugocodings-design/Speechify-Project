import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/ebook.dart';
import '../services/file_service.dart';
import 'home_screen.dart';
import 'recent_screen.dart';
import 'profile_screen.dart';
import 'scan/camera_capture_screen.dart';
import 'annotations_screen.dart';
import '../widgets/mini_player.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isLoading = false;
  final _fileService = FileService();

  @override
  void initState() {
    super.initState();
    // Demander la permission notifications une fois l'Activity prête (Android 13+)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Permission.notification.request();
      } catch (_) {
        // Permission déjà accordée manuellement ou Activity pas encore prête
      }
    });
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
  }

  // ─── Ajout de document (logique partagée avec l'ancien FAB de HomeScreen) ──

  Future<void> _pickAndUploadFile() async {
    try {
      setState(() => _isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub'],
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          final fileFormat = _fileService.detectFileFormat(filePath);
          final chapters = await _fileService.extractText(filePath);

          // Calculer le nombre total de phrases pour la barre de progression
          int totalSentences = 0;
          for (final ch in chapters) {
            totalSentences += ch.textContent
                .split(RegExp(r'(?<=[.!?…])\s+'))
                .where((s) => s.trim().isNotEmpty)
                .length;
          }

          // Extraire la couverture en parallèle (silencieusement en cas d'échec)
          final coverPath = await _fileService.extractCoverImage(filePath, fileFormat);

          final ebook = Ebook(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: result.files.first.name,
            chapters: chapters,
            uploadedAt: DateTime.now(),
            fileFormat: fileFormat,
            totalSentences: totalSentences,
            coverImagePath: coverPath,
          );

          await Hive.box<Ebook>('ebooks').put(ebook.id, ebook);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.mainScreen_bookAdded(ebook.title)),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.mainScreen_error('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddOptions() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(l10n.mainScreen_importFile),
              subtitle: Text(l10n.mainScreen_pdfOrEpub),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner),
              title: Text(l10n.mainScreen_scanWithCamera),
              subtitle: Text(l10n.mainScreen_scanSubtitle),
              onTap: () {
                Navigator.pop(ctx);
                _startScan();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startScan() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.mainScreen_bookCreatedFromScan),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                RecentScreen(),     // 0 — Accueil
                HomeScreen(),       // 1 — Bibliothèque
                AnnotationsScreen(),   // 2 — Annotations
                ProfileScreen(),    // 3 — Profil
              ],
            ),
          ),
          // Juste au-dessus de la barre de navigation, sur tous les onglets —
          // se cache d'elle-même tant qu'aucun livre n'est en cours.
          const MiniPlayer(),
        ],
      ),

      // Barre de navigation en bas — le "+" est un bouton parmi les autres,
      // au même niveau, pas surélevé ni séparé du reste de la barre.
      bottomNavigationBar: BottomAppBar(
        // Hauteur explicite : la hauteur par défaut (56px) était trop
        // juste pour icône + texte de chaque bouton, causant un léger
        // débordement (~2-3px) visible en bas de l'écran.
        height: 70,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          // Expanded sur chaque bouton : force les 5 à se partager la
          // largeur à parts égales. Sans ça, avec 5 items (au lieu de 4
          // avant l'ajout du bouton "Ajouter"), leur largeur naturelle
          // (icône + texte + padding) dépasse la largeur de l'écran et
          // le dernier ("Profil") déborde sur la droite.
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.home_rounded,
                label: l10n.nav_home,
                index: 0,
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.library_books_rounded,
                label: l10n.nav_library,
                index: 1,
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
            Expanded(
              child: _AddNavItem(
                isLoading: _isLoading,
                onTap: _showAddOptions,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.border_color_rounded,
                label: l10n.nav_annotations,
                index: 2,
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.person_rounded,
                label: l10n.nav_profile,
                index: 3,
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widget bouton de navigation ──────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = currentIndex == index;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey[600];

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bouton "+" — même style que les autres, pas surélevé ─────────────────────

class _AddNavItem extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _AddNavItem({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Colors.grey[600];

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
                  )
                : Icon(Icons.add_circle_outline_rounded, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context)!.nav_add,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
