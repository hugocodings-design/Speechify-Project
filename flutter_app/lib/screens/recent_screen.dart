import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/ebook.dart';
import '../services/stats_service.dart';
import '../widgets/stat_tile.dart';
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
          final l10n = AppLocalizations.of(context)!;
          final allBooks = box.values.toList()
            ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

          // Livres en cours : commencés mais pas terminés, du plus
          // récemment ouvert au plus anciennement ouvert
          final inProgress = allBooks
              .where((e) => e.lastReadPosition > 0 && !e.isFinished)
              .toList()
            ..sort((a, b) => (b.lastOpenedAt ?? b.uploadedAt)
                .compareTo(a.lastOpenedAt ?? a.uploadedAt));

          if (allBooks.isEmpty) {
            return _buildEmptyState(context);
          }

          final stats = StatsService.instance;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final todaySec = stats.getTotalSeconds(today, today);
          final weekSec = stats.getTotalSeconds(
              today.subtract(const Duration(days: 6)), today);
          final streak = stats.getCurrentStreakDays();
          final finishedCount = allBooks.where((e) => e.isFinished).length;

          return ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              // ── En cours ────────────────────────────────────────────────
              if (inProgress.isNotEmpty) ...[
                _SectionHeader(label: l10n.recentScreen_inProgress),
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

              // ── Statistiques ────────────────────────────────────────────
              _SectionHeader(label: l10n.recentScreen_statistics),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            icon: Icons.today,
                            label: l10n.recentScreen_today,
                            value: StatsService.formatSeconds(todaySec),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            icon: Icons.calendar_view_week,
                            label: l10n.recentScreen_thisWeek,
                            value: StatsService.formatSeconds(weekSec),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            icon: Icons.local_fire_department,
                            label: l10n.recentScreen_streak,
                            value: l10n.recentScreen_streakDays(streak),
                            highlight: streak > 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatTile(
                            icon: Icons.menu_book,
                            label: l10n.recentScreen_inProgressAndFinished,
                            value: l10n.recentScreen_countRatio(inProgress.length, finishedCount),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(l10n.recentScreen_noBooks, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            l10n.recentScreen_addPrompt,
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
              AppLocalizations.of(context)!.recentScreen_percentRead((progress * 100).round()),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
