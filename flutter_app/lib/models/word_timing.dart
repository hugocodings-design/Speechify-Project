/// Timestamp (en secondes depuis le début de la phrase) où un mot commence
/// à être prononcé — utilisé pour le surlignage mot par mot pendant la lecture.
class WordTiming {
  final String word;
  final double time;

  const WordTiming(this.word, this.time);

  factory WordTiming.fromJson(Map<String, dynamic> json) =>
      WordTiming(json['word'] as String, (json['time'] as num).toDouble());
}

/// Parse la liste "word_timings" renvoyée par le backend. Retourne une liste
/// vide (silencieusement) si le champ est absent ou mal formé — le
/// surlignage mot par mot devient simplement indisponible pour cette phrase,
/// sans casser la lecture.
List<WordTiming> parseWordTimings(dynamic raw) {
  if (raw is! List) return const [];
  final result = <WordTiming>[];
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      try {
        result.add(WordTiming.fromJson(item));
      } catch (_) {
        // Entrée mal formée — ignorée
      }
    }
  }
  return result;
}
