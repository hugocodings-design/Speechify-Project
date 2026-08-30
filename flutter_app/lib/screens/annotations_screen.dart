import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/annotation.dart';
import '../models/dictionary_entry.dart';
import '../models/translation_entry.dart';
import '../models/ebook.dart';
import '../widgets/dictionary_sheet.dart';
import 'reader_screen.dart';

/// Liste des passages surlignés, des mots de vocabulaire et des traductions
/// enregistrées, groupés par livre, dans trois onglets.
class AnnotationsScreen extends StatelessWidget {
  // Quand rempli (ex : ouvert depuis le menu "..." du lecteur), n'affiche
  // que les annotations/mots de ce livre — sinon tous les livres confondus,
  // comme dans l'onglet de navigation du bas.
  final String? filterEbookId;

  const AnnotationsScreen({Key? key, this.filterEbookId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.nav_annotations),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: filterEbookId != null,
          actions: filterEbookId == null
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.library_books_rounded),
                    tooltip: l10n.annotations_allAnnotations,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AnnotationsScreen()),
                    ),
                  ),
                ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.annotations_tabHighlights),
              Tab(text: l10n.annotations_tabDictionary),
              Tab(text: l10n.annotations_tabTranslations),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HighlightsList(filterEbookId: filterEbookId),
            _DictionaryList(filterEbookId: filterEbookId),
            _TranslationsList(filterEbookId: filterEbookId),
          ],
        ),
      ),
    );
  }
}

// ─── En-tête livre, partagé par les deux onglets ────────────────────────────

class _BookHeader extends StatelessWidget {
  final Ebook ebook;

  const _BookHeader({required this.ebook});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ebook.coverImagePath != null
                ? Image.file(
                    File(ebook.coverImagePath!),
                    width: 40,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallbackCover(),
                  )
                : _fallbackCover(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ebook.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _fallbackCover() => Container(
      width: 40,
      height: 54,
      color: Colors.grey[300],
      child: const Icon(Icons.menu_book_rounded, size: 20),
    );

String _relativeDate(BuildContext context, DateTime dt) {
  final l10n = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return l10n.annotations_justNow;
  if (diff.inHours < 1) return l10n.annotations_minutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.annotations_hoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.annotations_daysAgo(diff.inDays);
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ─── Onglet Surlignages ──────────────────────────────────────────────────────

class _HighlightsList extends StatelessWidget {
  final String? filterEbookId;

  const _HighlightsList({this.filterEbookId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Annotation>>(
      valueListenable: Hive.box<Annotation>('annotations').listenable(),
      builder: (context, box, _) {
        final ebookBox = Hive.box<Ebook>('ebooks');
        final byBook = <String, List<Annotation>>{};
        for (final a in box.values) {
          if (filterEbookId != null && a.ebookId != filterEbookId) continue;
          byBook.putIfAbsent(a.ebookId, () => []).add(a);
        }

        if (byBook.isEmpty) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.border_color_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  l10n.annotations_noHighlights,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.annotations_noHighlightsHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        final entries = byBook.entries.toList()
          ..sort((a, b) {
            final ta = a.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            final tb = b.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            return tb.compareTo(ta); // livres les plus récemment annotés en premier
          });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final ebookId = entries[i].key;
            final annotations = entries[i].value
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final ebook = ebookBox.get(ebookId);
            if (ebook == null) return const SizedBox.shrink(); // livre supprimé depuis

            return _BookSection(ebook: ebook, annotations: annotations);
          },
        );
      },
    );
  }
}

class _BookSection extends StatelessWidget {
  final Ebook ebook;
  final List<Annotation> annotations;

  const _BookSection({required this.ebook, required this.annotations});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BookHeader(ebook: ebook),
        ...annotations.map((a) => _AnnotationTile(ebook: ebook, annotation: a)),
        const Divider(height: 24),
      ],
    );
  }
}

class _AnnotationTile extends StatelessWidget {
  final Ebook ebook;
  final Annotation annotation;

  const _AnnotationTile({required this.ebook, required this.annotation});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      title: Text(
        '« ${annotation.selectedText} »',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text(
        _relativeDate(context, annotation.createdAt),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        tooltip: AppLocalizations.of(context)!.common_delete,
        onPressed: () => Hive.box<Annotation>('annotations').delete(annotation.id),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(ebook: ebook, jumpToAnnotation: annotation),
        ),
      ),
    );
  }
}

// ─── Onglet Dictionnaire ─────────────────────────────────────────────────────

class _DictionaryList extends StatelessWidget {
  final String? filterEbookId;

  const _DictionaryList({this.filterEbookId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<DictionaryEntry>>(
      valueListenable: Hive.box<DictionaryEntry>('dictionary').listenable(),
      builder: (context, box, _) {
        final ebookBox = Hive.box<Ebook>('ebooks');
        final byBook = <String, List<DictionaryEntry>>{};
        for (final e in box.values) {
          if (filterEbookId != null && e.ebookId != filterEbookId) continue;
          byBook.putIfAbsent(e.ebookId, () => []).add(e);
        }

        if (byBook.isEmpty) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.translate_rounded, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  l10n.annotations_noWords,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.annotations_noWordsHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        final entries = byBook.entries.toList()
          ..sort((a, b) {
            final ta = a.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            final tb = b.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            return tb.compareTo(ta);
          });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final ebookId = entries[i].key;
            final words = entries[i].value
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final ebook = ebookBox.get(ebookId);
            if (ebook == null) return const SizedBox.shrink(); // livre supprimé depuis

            return _DictionaryBookSection(ebook: ebook, entries: words);
          },
        );
      },
    );
  }
}

class _DictionaryBookSection extends StatelessWidget {
  final Ebook ebook;
  final List<DictionaryEntry> entries;

  const _DictionaryBookSection({required this.ebook, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BookHeader(ebook: ebook),
        ...entries.map((e) => _DictionaryTile(entry: e)),
        const Divider(height: 24),
      ],
    );
  }
}

class _DictionaryTile extends StatelessWidget {
  final DictionaryEntry entry;

  const _DictionaryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Un tap rouvre la vraie fiche (prononciation, synonymes) plutôt qu'un
    // simple dépliant : deux gestes pour deux niveaux de détail serait plus
    // confus qu'utile ici.
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      title: Row(
        children: [
          Text(entry.word, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (entry.translatedWord.isNotEmpty &&
              entry.translatedWord.toLowerCase() != entry.wordLower) ...[
            Text(' → ', style: TextStyle(color: Colors.grey[500])),
            Flexible(
              child: Text(
                entry.translatedWord,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.definition.isNotEmpty)
            Text(
              entry.definition,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            _relativeDate(context, entry.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        tooltip: AppLocalizations.of(context)!.common_delete,
        onPressed: () => Hive.box<DictionaryEntry>('dictionary').delete(entry.id),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.75,
          child: DictionarySheet(
            word: entry.word,
            sourceLang: entry.sourceLang,
            ebookId: entry.ebookId,
            chapterId: entry.chapterId,
            preloaded: entry,
          ),
        ),
      ),
    );
  }
}

// ─── Onglet Traductions ──────────────────────────────────────────────────────

class _TranslationsList extends StatelessWidget {
  final String? filterEbookId;

  const _TranslationsList({this.filterEbookId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<TranslationEntry>>(
      valueListenable: Hive.box<TranslationEntry>('translations').listenable(),
      builder: (context, box, _) {
        final ebookBox = Hive.box<Ebook>('ebooks');
        final byBook = <String, List<TranslationEntry>>{};
        for (final e in box.values) {
          if (filterEbookId != null && e.ebookId != filterEbookId) continue;
          byBook.putIfAbsent(e.ebookId, () => []).add(e);
        }

        if (byBook.isEmpty) {
          final l10n = AppLocalizations.of(context)!;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.g_translate_rounded, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  l10n.annotations_noTranslations,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.annotations_noTranslationsHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        final entries = byBook.entries.toList()
          ..sort((a, b) {
            final ta = a.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            final tb = b.value.map((x) => x.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
            return tb.compareTo(ta);
          });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final ebookId = entries[i].key;
            final translations = entries[i].value
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final ebook = ebookBox.get(ebookId);
            if (ebook == null) return const SizedBox.shrink(); // livre supprimé depuis

            return _TranslationBookSection(ebook: ebook, entries: translations);
          },
        );
      },
    );
  }
}

class _TranslationBookSection extends StatelessWidget {
  final Ebook ebook;
  final List<TranslationEntry> entries;

  const _TranslationBookSection({required this.ebook, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BookHeader(ebook: ebook),
        ...entries.map((e) => _TranslationTile(ebook: ebook, entry: e)),
        const Divider(height: 24),
      ],
    );
  }
}

class _TranslationTile extends StatelessWidget {
  final Ebook ebook;
  final TranslationEntry entry;

  const _TranslationTile({required this.ebook, required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      title: Text(
        '« ${entry.text} »',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.translatedText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          Text(
            _relativeDate(context, entry.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        tooltip: AppLocalizations.of(context)!.common_delete,
        onPressed: () => Hive.box<TranslationEntry>('translations').delete(entry.id),
      ),
      // Amène directement au passage exact dans le livre — plutôt que de
      // ré-ouvrir la fiche qui ne ferait que répéter le texte et sa
      // traduction, déjà visibles ici dans la liste.
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            ebook: ebook,
            jumpToChapterId: entry.chapterId,
            jumpToParagraphIndexInChapter: entry.paragraphIndexInChapter,
          ),
        ),
      ),
    );
  }
}
