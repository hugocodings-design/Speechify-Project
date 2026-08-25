import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/annotation.dart';
import '../models/ebook.dart';
import 'reader_screen.dart';

/// Liste des passages surlignés, groupés par livre. Le TabBar à un seul
/// onglet aujourd'hui laisse de la place pour un futur onglet
/// dictionnaire/traduction, sans rien construire de plus pour l'instant.
class AnnotationsScreen extends StatelessWidget {
  const AnnotationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Annotations'),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(tabs: [Tab(text: 'Surlignages')]),
        ),
        body: const TabBarView(
          children: [_HighlightsList()],
        ),
      ),
    );
  }
}

class _HighlightsList extends StatelessWidget {
  const _HighlightsList();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Annotation>>(
      valueListenable: Hive.box<Annotation>('annotations').listenable(),
      builder: (context, box, _) {
        final ebookBox = Hive.box<Ebook>('ebooks');
        final byBook = <String, List<Annotation>>{};
        for (final a in box.values) {
          byBook.putIfAbsent(a.ebookId, () => []).add(a);
        }

        if (byBook.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.border_color_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Aucun passage surligné',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  "Tenez le doigt sur un mot pendant la lecture pour surligner un passage",
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
        Padding(
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
        ),
        ...annotations.map((a) => _AnnotationTile(ebook: ebook, annotation: a)),
        const Divider(height: 24),
      ],
    );
  }

  Widget _fallbackCover() => Container(
        width: 40,
        height: 54,
        color: Colors.grey[300],
        child: const Icon(Icons.menu_book_rounded, size: 20),
      );
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
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text(
        _relativeDate(annotation.createdAt),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
        tooltip: 'Supprimer',
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

  String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
