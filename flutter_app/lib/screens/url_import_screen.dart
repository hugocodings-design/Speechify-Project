import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/ebook.dart';
import '../services/url_to_book_service.dart';

/// Une entrée de la liste : son URL, et le résultat de sa récupération une
/// fois celle-ci terminée (article, ou message d'erreur).
class _UrlEntry {
  _UrlEntry(this.url);
  final String url;
  UrlArticle? article;
  String? error;
  bool loading = true;
}

/// Ajout d'un livre à partir d'une ou plusieurs pages web.
///
/// Chaque lien est récupéré dès qu'il est ajouté (pas seulement à la
/// création du livre) : ça permet de détecter tout de suite une page qui se
/// poursuit sur un lien "suivant" et de proposer de l'ajouter aussi.
///
/// Les liens sont assemblés dans l'ordre où ils apparaissent dans la liste :
/// le premier devient le début du livre, le dernier la fin.
class UrlImportScreen extends StatefulWidget {
  const UrlImportScreen({Key? key}) : super(key: key);

  @override
  State<UrlImportScreen> createState() => _UrlImportScreenState();
}

class _UrlImportScreenState extends State<UrlImportScreen> {
  final _urlController = TextEditingController();
  final _entries = <_UrlEntry>[];
  bool _creating = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  bool get _hasUsableEntry => _entries.any((e) => e.article != null);

  Future<void> _addUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    if (_entries.any((e) => e.url == url)) return; // déjà dans la liste

    final entry = _UrlEntry(url);
    setState(() => _entries.add(entry));

    try {
      final article = await UrlToBookService.fetch(url);
      if (!mounted) return;
      setState(() {
        entry.article = article;
        entry.loading = false;
      });

      final next = article.continuationUrl;
      if (next != null && !_entries.any((e) => e.url == next)) {
        _offerContinuation(next);
      }
    } on UrlImportException catch (e) {
      if (!mounted) return;
      setState(() {
        entry.error = e.message;
        entry.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        entry.error = '$e';
        entry.loading = false;
      });
    }
  }

  void _offerContinuation(String nextUrl) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.urlImport_continuationFound),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.urlImport_add,
          onPressed: () => _addUrl(nextUrl),
        ),
      ),
    );
  }

  Future<void> _createBook() async {
    final l10n = AppLocalizations.of(context)!;
    final articles = _entries
        .map((e) => e.article)
        .whereType<UrlArticle>()
        .toList();
    if (articles.isEmpty) return;

    final now = DateTime.now();
    final controller = TextEditingController(
      text: articles.length == 1 ? '' : l10n.urlImport_defaultTitle(articles.length),
    );
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.urlImport_bookTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.urlImport_create),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;

    setState(() => _creating = true);

    final chapters = mergeUrlArticles(articles);
    var totalSentences = 0;
    for (final ch in chapters) {
      totalSentences += ch.textContent
          .split(RegExp(r'(?<=[.!?…])\s+'))
          .where((s) => s.trim().isNotEmpty)
          .length;
    }

    final resolvedTitle = title.isNotEmpty ? title : articles.first.title;

    final ebook = Ebook(
      id: now.millisecondsSinceEpoch.toString(),
      title: resolvedTitle,
      chapters: chapters,
      uploadedAt: now,
      fileFormat: 'url',
      totalSentences: totalSentences,
    );
    await Hive.box<Ebook>('ebooks').put(ebook.id, ebook);

    if (!mounted) return;

    final failedCount = _entries.where((e) => e.error != null).length;
    if (failedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.urlImport_partialFailure(failedCount)),
          backgroundColor: Colors.orange,
        ),
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mainScreen_addFromUrl)),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: l10n.mainScreen_urlHint,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          _addUrl(value);
                          _urlController.clear();
                        },
                        enabled: !_creating,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _creating
                          ? null
                          : () {
                              _addUrl(_urlController.text);
                              _urlController.clear();
                            },
                      icon: const Icon(Icons.add),
                      tooltip: l10n.urlImport_addLink,
                    ),
                  ],
                ),
              ),
              if (_entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.urlImport_orderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              Expanded(
                child: _entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.urlImport_empty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _entries.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            _entries.insert(newIndex, _entries.removeAt(oldIndex));
                          });
                        },
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return _buildTile(entry, index);
                        },
                      ),
              ),
            ],
          ),
          if (_creating)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: (_creating || !_hasUsableEntry) ? null : _createBook,
            icon: const Icon(Icons.auto_stories),
            label: Text(l10n.urlImport_create),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(_UrlEntry entry, int index) {
    final l10n = AppLocalizations.of(context)!;

    Widget leading;
    Widget title;
    Widget? subtitle;

    if (entry.loading) {
      leading = const SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
      title = Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else if (entry.article != null) {
      leading = CircleAvatar(radius: 14, child: Text('${index + 1}'));
      title = Text(
        entry.article!.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final words = entry.article!.chapters
          .fold<int>(0, (sum, c) => sum + c.wordCount);
      subtitle = Text(l10n.urlImport_words(words));
    } else {
      leading = const Icon(Icons.error_outline, color: Colors.red);
      title = Text(
        entry.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      subtitle = Text(
        entry.error ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.red),
      );
    }

    return Card(
      key: ValueKey(entry.url),
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: _creating
              ? null
              : () => setState(() => _entries.removeAt(index)),
        ),
      ),
    );
  }
}
