import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../main.dart';
import '../models/ebook.dart';
import '../screens/home_screen.dart' show BookCover;
import '../screens/reader_screen.dart';

/// Petite barre "en cours de lecture" affichée juste au-dessus de la barre
/// de navigation, sur tous les onglets — permet de mettre en pause/reprendre
/// et de revenir directement au livre en cours sans repasser par la
/// bibliothèque. Se cache d'elle-même tant qu'aucune session de lecture n'a
/// démarré.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final handler = audioHandler;
    if (handler == null) return const SizedBox.shrink();

    return ValueListenableBuilder<String?>(
      valueListenable: handler.currentEbookIdNotifier,
      builder: (context, ebookId, _) {
        if (ebookId == null) return const SizedBox.shrink();
        final ebook = Hive.box<Ebook>('ebooks').get(ebookId);
        if (ebook == null) return const SizedBox.shrink();

        return ValueListenableBuilder<int>(
          valueListenable: handler.currentIndexNotifier,
          builder: (context, currentIndex, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: handler.shouldBePlayingNotifier,
              builder: (context, playing, _) {
                final total = handler.totalSentenceCount;
                final progress =
                    total > 0 ? (currentIndex / total).clamp(0.0, 1.0) : 0.0;
                final wordsRemaining = ebook.totalWords * (1 - progress);
                final wpm = 150.0 * handler.speed;
                final minutesRemaining =
                    wpm > 0 ? (wordsRemaining / wpm).round() : 0;

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReaderScreen(ebook: ebook)),
                  ),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 42,
                            height: 42,
                            child: BookCover(
                              title: ebook.title,
                              isPdf: ebook.fileFormat == 'pdf',
                              coverImagePath: ebook.coverImagePath,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ebook.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatRemaining(minutesRemaining),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            size: 38,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            if (playing) {
                              handler.pause();
                            } else {
                              handler.play();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatRemaining(int minutes) {
    if (minutes <= 0) return 'Presque terminé';
    if (minutes < 60) return '$minutes min restantes';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m restantes';
  }
}
