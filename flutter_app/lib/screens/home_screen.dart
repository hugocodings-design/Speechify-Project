import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ebook.dart';
import '../models/folder.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Box<Ebook>? _ebookBox;
  Box<Folder>? _folderBox;
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};
  String? _currentFolderId; // null = racine (tous les livres sans dossier)

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  void _initializeHive() {
    // Les boxes sont déjà ouvertes dans main.dart — on les récupère directement
    setState(() {
      _ebookBox = Hive.box<Ebook>('ebooks');
      _folderBox = Hive.box<Folder>('folders');
    });
  }

  // ─── Getters filtrés ────────────────────────────────────────────────────────

  List<Folder> get _folders => _folderBox?.values.toList() ?? [];

  List<Ebook> get _visibleEbooks {
    if (_ebookBox == null) return [];
    return _ebookBox!.values
        .where((e) => e.folderId == _currentFolderId)
        .toList();
  }

  // ─── Upload ─────────────────────────────────────────────────────────────────

  // ─── Sélection ──────────────────────────────────────────────────────────────

  void _enterSelectionMode(String ebookId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds = {ebookId};
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds = {};
    });
  }

  void _toggleSelection(String ebookId) {
    setState(() {
      if (_selectedIds.contains(ebookId)) {
        _selectedIds.remove(ebookId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(ebookId);
      }
    });
  }

  // ─── Actions sur un livre ────────────────────────────────────────────────────

  Future<void> _renameEbook(Ebook ebook) async {
    final controller = TextEditingController(text: ebook.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le livre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titre'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != ebook.title) {
      ebook.title = newTitle;
      await _ebookBox!.put(ebook.id, ebook);
      setState(() {});
    }
  }

  Future<void> _deleteEbook(Ebook ebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le livre'),
        content: Text('Supprimer "${ebook.title}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _ebookBox!.delete(ebook.id);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${ebook.title}" supprimé')),
        );
      }
    }
  }

  Future<void> _moveEbookToFolder(Ebook ebook) async {
    await _showMoveToFolderDialog([ebook.id]);
  }

  // ─── Actions sur la sélection ────────────────────────────────────────────────

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer les livres'),
        content: Text('Supprimer $count livre(s) sélectionné(s) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedIds) {
        await _ebookBox!.delete(id);
      }
      _exitSelectionMode();
      setState(() {});
    }
  }

  Future<void> _moveSelected() async {
    await _showMoveToFolderDialog(_selectedIds.toList());
    _exitSelectionMode();
  }

  // ─── Dossiers ────────────────────────────────────────────────────────────────

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau dossier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom du dossier'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final folder = Folder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        createdAt: DateTime.now(),
      );
      await _folderBox!.put(folder.id, folder);
      setState(() {});
    }
  }

  Future<void> _renameFolder(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le dossier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      folder.name = newName;
      await _folderBox!.put(folder.id, folder);
      setState(() {});
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final bookCount = _ebookBox?.values
            .where((e) => e.folderId == folder.id)
            .length ??
        0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le dossier'),
        content: Text(bookCount > 0
            ? 'Supprimer "${folder.name}" ? Les $bookCount livre(s) seront déplacés à la racine.'
            : 'Supprimer le dossier "${folder.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Déplacer les livres du dossier vers la racine
      for (final ebook in _ebookBox!.values.where((e) => e.folderId == folder.id)) {
        ebook.folderId = null;
        await _ebookBox!.put(ebook.id, ebook);
      }
      await _folderBox!.delete(folder.id);

      // Si on était dans ce dossier, revenir à la racine
      if (_currentFolderId == folder.id) {
        setState(() => _currentFolderId = null);
      }
      setState(() {});
    }
  }

  Future<void> _showMoveToFolderDialog(List<String> ebookIds) async {
    final folders = _folders;
    String? targetFolderId = _currentFolderId;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Déplacer dans un dossier'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Option racine
                RadioListTile<String?>(
                  title: const Text('Aucun dossier (racine)'),
                  value: null,
                  groupValue: targetFolderId,
                  onChanged: (v) => setDialogState(() => targetFolderId = v),
                ),
                // Dossiers existants
                ...folders.map((f) => RadioListTile<String?>(
                      title: Text(f.name),
                      value: f.id,
                      groupValue: targetFolderId,
                      onChanged: (v) =>
                          setDialogState(() => targetFolderId = v),
                    )),
                // Créer un nouveau dossier
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _createFolder();
                    // Rouvrir le dialog après création
                    if (mounted) await _showMoveToFolderDialog(ebookIds);
                  },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Nouveau dossier'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, targetFolderId ?? '__null__'),
              child: const Text('Déplacer'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      final folderId = result == '__null__' ? null : result;
      for (final id in ebookIds) {
        final ebook = _ebookBox!.get(id);
        if (ebook != null) {
          ebook.folderId = folderId;
          await _ebookBox!.put(id, ebook);
        }
      }
      setState(() {});
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_ebookBox == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ValueListenableBuilder(
      valueListenable: _ebookBox!.listenable(),
      builder: (context, _, __) {
        final books = _visibleEbooks;
        final folders = _folders;
        final isRoot = _currentFolderId == null;

        return Scaffold(
          appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
          body: (books.isEmpty && folders.isEmpty && isRoot)
              ? _buildEmptyState()
              : _buildContent(books, folders, isRoot),
        );
      },
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    final currentFolder = _currentFolderId != null
        ? _folderBox?.get(_currentFolderId)
        : null;

    return AppBar(
      leading: _currentFolderId != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _currentFolderId = null),
            )
          : null,
      title: Text(currentFolder?.name ?? 'TalkTome'),
      centerTitle: true,
      elevation: 0,
      actions: [
        if (_currentFolderId == null)
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Nouveau dossier',
            onPressed: _createFolder,
          ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedIds.length} sélectionné(s)'),
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: 'Déplacer',
          onPressed: _moveSelected,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Supprimer',
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildContent(List<Ebook> books, List<Folder> folders, bool isRoot) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Dossiers (visibles seulement à la racine)
        if (isRoot && folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Dossiers',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          ...folders.map((folder) => _buildFolderTile(folder)),
          const Divider(indent: 16, endIndent: 16),
        ],

        // Livres
        if (books.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Aucun livre ici',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[500]),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Livres',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          _buildEbookGrid(books),
        ],
      ],
    );
  }

  Widget _buildFolderTile(Folder folder) {
    final bookCount = _ebookBox?.values
            .where((e) => e.folderId == folder.id)
            .length ??
        0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.folder, color: Colors.amber, size: 32),
        title: Text(folder.name),
        subtitle: Text('$bookCount livre(s)'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            if (action == 'rename') _renameFolder(folder);
            if (action == 'delete') _deleteFolder(folder);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'rename',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Renommer'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Supprimer', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () => setState(() => _currentFolderId = folder.id),
      ),
    );
  }

  Widget _buildProgressSubtitle(Ebook ebook) {
    final total = ebook.totalSentences;
    final pos = ebook.lastReadPosition;
    final hasProgress = total > 0 && pos > 0;
    final progress = hasProgress ? (pos / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${ebook.chapters.length} chapitres • ${ebook.totalWords} mots',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.grey[200],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            pos == 0
                ? 'Non commencé'
                : pos >= total - 1
                    ? 'Terminé ✓'
                    : '${(progress * 100).round()}% lu • phrase $pos / $total',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _buildEbookGrid(List<Ebook> books) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.62,
        ),
        itemCount: books.length,
        itemBuilder: (context, i) => _buildEbookCard(books[i]),
      ),
    );
  }

  Widget _buildEbookCard(Ebook ebook) {
    final isSelected = _selectedIds.contains(ebook.id);
    final isPdf = ebook.fileFormat == 'pdf';
    final total = ebook.totalSentences;
    final pos = ebook.lastReadPosition;
    final progress = (total > 0 && pos > 0) ? (pos / total).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: _isSelectionMode
          ? () => _toggleSelection(ebook.id)
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReaderScreen(ebook: ebook)),
              ).then((_) => setState(() {})),
      onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(ebook.id),
      child: Card(
        elevation: isSelected ? 0 : 2,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isSelected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Couverture ────────────────────────────────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(
                    title: ebook.title,
                    isPdf: isPdf,
                    coverImagePath: ebook.coverImagePath,
                  ),
                  if (_isSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  if (!_isSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _EbookCardMenu(
                        ebook: ebook,
                        onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ReaderScreen(ebook: ebook)),
                        ).then((_) => setState(() {})),
                        onRename: () => _renameEbook(ebook),
                        onSelect: () => _enterSelectionMode(ebook.id),
                        onMove: () => _moveEbookToFolder(ebook),
                        onDelete: () => _deleteEbook(ebook),
                      ),
                    ),
                ],
              ),
            ),
            // ── Infos ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ebook.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  if (total > 0)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                  if (total > 0) const SizedBox(height: 2),
                  Text(
                    pos == 0
                        ? isPdf ? 'PDF' : 'EPUB'
                        : pos >= total - 1
                            ? 'Terminé ✓'
                            : '${(progress * 100).round()}%',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEbookTile(Ebook ebook) {
    final isSelected = _selectedIds.contains(ebook.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : null,
      child: ListTile(
        leading: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(ebook.id),
              )
            : Icon(
                ebook.fileFormat == 'pdf'
                    ? Icons.picture_as_pdf
                    : Icons.import_contacts,
                color: Colors.blue,
              ),
        title: Text(ebook.title),
        subtitle: _buildProgressSubtitle(ebook),
        trailing: _isSelectionMode
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  if (action == 'open') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReaderScreen(ebook: ebook),
                      ),
                    ).then((_) => setState(() {}));
                  }
                  if (action == 'rename') _renameEbook(ebook);
                  if (action == 'select') _enterSelectionMode(ebook.id);
                  if (action == 'move') _moveEbookToFolder(ebook);
                  if (action == 'delete') _deleteEbook(ebook);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.play_arrow_outlined),
                      title: Text('Ouvrir'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Renommer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'select',
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Sélectionner'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_move_outline),
                      title: Text('Déplacer dans un dossier'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text(
                        'Supprimer',
                        style: TextStyle(color: Colors.red),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
        onTap: _isSelectionMode
            ? () => _toggleSelection(ebook.id)
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(ebook: ebook),
                  ),
                ).then((_) => setState(() {})),
        onLongPress: _isSelectionMode
            ? null
            : () => _enterSelectionMode(ebook.id),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Aucun livre',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Appuyez sur + pour ajouter un PDF ou EPUB',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Ne pas fermer la box ici — elle est partagée avec MainScreen et RecentScreen
    super.dispose();
  }
}

// ─── Couverture générée ────────────────────────────────────────────────────────

class BookCover extends StatelessWidget {
  final String title;
  final bool isPdf;
  final String? coverImagePath;

  const BookCover({required this.title, required this.isPdf, this.coverImagePath});

  // Couleur dérivée du titre pour varier les couvertures
  Color _baseColor() {
    final colors = [
      const Color(0xFF1565C0), // bleu foncé
      const Color(0xFF2E7D32), // vert foncé
      const Color(0xFF6A1B9A), // violet
      const Color(0xFFC62828), // rouge foncé
      const Color(0xFFE65100), // orange foncé
      const Color(0xFF00695C), // teal
      const Color(0xFF283593), // indigo
      const Color(0xFF4527A0), // deep purple
    ];
    final index = title.codeUnits.fold(0, (a, b) => a + b) % colors.length;
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    // Image réelle disponible → l'afficher directement
    if (coverImagePath != null) {
      final file = File(coverImagePath!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    // Couverture générée (fallback)
    final color = _baseColor();
    final initials = title
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.75)],
        ),
      ),
      child: Stack(
        children: [
          // Grandes initiales en filigrane
          Positioned(
            bottom: -8,
            right: -4,
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                color: Colors.white.withOpacity(0.15),
                height: 1,
              ),
            ),
          ),
          // Badge type de fichier
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isPdf ? 'PDF' : 'EPUB',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Icône centrale
          Center(
            child: Icon(
              isPdf ? Icons.picture_as_pdf_rounded : Icons.import_contacts_rounded,
              color: Colors.white.withOpacity(0.6),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Menu contextuel compact pour la grille ───────────────────────────────────

class _EbookCardMenu extends StatelessWidget {
  final Ebook ebook;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onSelect;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const _EbookCardMenu({
    required this.ebook,
    required this.onOpen,
    required this.onRename,
    required this.onSelect,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
      ),
      onSelected: (action) {
        switch (action) {
          case 'open': onOpen();
          case 'rename': onRename();
          case 'select': onSelect();
          case 'move': onMove();
          case 'delete': onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.play_arrow_outlined),
            title: Text('Ouvrir'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Renommer'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('Sélectionner'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'move',
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Déplacer'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Supprimer', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }
}
