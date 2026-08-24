import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ebook.dart';
import 'home_screen.dart' show BookCover;
import 'reader_screen.dart';

class RecentScreen extends StatelessWidget {
  const RecentScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speechify'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ValueListenableBuilder<Box<Ebook>>(
        valueListenable: Hive.box<Ebook>('ebooks').listenable(),
        builder: (context, box, _) {
          final allBooks = box.values.toList()
            ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

          // Livres en cours : commencés mais pas terminés
          final inProgress = allBooks
              .where((e) =>
                  e.lastReadPosition > 0 &&
                  e.totalSentences > 0 &&
                  e.lastReadPosition < e.totalSentences - 1)
              .toList();

          // 5 derniers ajoutés
          final recentlyAdded = allBooks.take(5).toList();

          if (allBooks.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              // ── En cours ────────────────────────────────────────────────
              if (inProgress.isNotEmpty) ...[
                _SectionHeader(label: 'En cours'),
                SizedBox(
                  height: 230,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: inProgress.length,
                    itemBuilder: (context, i) =>
                        _InProgressCard(ebook: inProgress[i]),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ── Récemment ajoutés ────────────────────────────────────────
              _SectionHeader(label: 'Récemment ajoutés'),
              ...recentlyAdded.map((e) => _RecentBookTile(ebook: e)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Aucun livre', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Appuie sur + pour ajouter un PDF ou EPUB',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets internes ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Colors.grey[600]),
      ),
    );
  }
}

/// Carte horizontale pour un livre en cours
class _InProgressCard extends StatelessWidget {
  final Ebook ebook;
  const _InProgressCard({required this.ebook});

  @override
  Widget build(BuildContext context) {
    final progress = ebook.totalSentences > 0
        ? (ebook.lastReadPosition / ebook.totalSentences).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(ebook: ebook)),
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Couverture ────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 140,
                height: 140,
                child: BookCover(
                  title: ebook.title,
                  isPdf: ebook.fileFormat == 'pdf',
                  coverImagePath: ebook.coverImagePath,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ebook.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            // Barre de progression
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).round()}% lu',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne simple pour les livres récemment ajoutés
class _RecentBookTile extends StatelessWidget {
  final Ebook ebook;
  const _RecentBookTile({required this.ebook});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 40,
            height: 56,
            child: BookCover(
              title: ebook.title,
              isPdf: ebook.fileFormat == 'pdf',
              coverImagePath: ebook.coverImagePath,
            ),
          ),
        ),
        title: Text(ebook.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${ebook.chapters.length} chapitres · ${ebook.totalWords} mots',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReaderScreen(ebook: ebook)),
        ),
      ),
    );
  }
}
