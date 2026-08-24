import 'package:hive/hive.dart';

/// Gère les statistiques de lecture dans une Hive box non-typée.
/// Format : clé 'YYYY-MM-DD' → secondes lues ce jour-là (int).
class StatsService {
  final Box _box;

  StatsService(this._box);

  /// Accès rapide à l'instance globale (box déjà ouverte au démarrage)
  static StatsService get instance => StatsService(Hive.box('reading_stats'));

  // ─── Écriture ─────────────────────────────────────────────────────────────

  /// Ajoute des secondes à la journée courante
  void addSeconds(int seconds) {
    final key = dateKey(DateTime.now());
    final current = _box.get(key, defaultValue: 0) as int;
    _box.put(key, current + seconds);
  }

  // ─── Lecture par période ───────────────────────────────────────────────────

  /// Total de secondes entre deux dates incluses
  int getTotalSeconds(DateTime start, DateTime end) {
    int total = 0;
    for (DateTime d = _date(start); !d.isAfter(_date(end)); d = d.add(const Duration(days: 1))) {
      total += (_box.get(dateKey(d), defaultValue: 0) as int);
    }
    return total;
  }

  /// Répartition jour par jour (pour graphique barre — période courte)
  Map<String, int> getDailyBreakdown(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (DateTime d = _date(start); !d.isAfter(_date(end)); d = d.add(const Duration(days: 1))) {
      final key = dateKey(d);
      result[key] = (_box.get(key, defaultValue: 0) as int);
    }
    return result;
  }

  /// Répartition semaine par semaine (pour graphique — période longue)
  /// Clé = date du lundi de la semaine
  Map<String, int> getWeeklyBreakdown(DateTime start, DateTime end) {
    final result = <String, int>{};
    // Premier lundi avant ou égal à start
    DateTime weekStart = _date(start).subtract(Duration(days: _date(start).weekday - 1));
    while (!weekStart.isAfter(_date(end))) {
      final weekEnd = weekStart.add(const Duration(days: 6));
      result[dateKey(weekStart)] = getTotalSeconds(
        weekStart,
        weekEnd.isAfter(_date(end)) ? _date(end) : weekEnd,
      );
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return result;
  }

  /// Répartition mois par mois (pour graphique — très longue période)
  Map<String, int> getMonthlyBreakdown(DateTime start, DateTime end) {
    final result = <String, int>{};
    DateTime month = DateTime(start.year, start.month, 1);
    while (!month.isAfter(_date(end))) {
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      final monthEnd = nextMonth.subtract(const Duration(days: 1));
      result[dateKey(month)] = getTotalSeconds(
        month,
        monthEnd.isAfter(_date(end)) ? _date(end) : monthEnd,
      );
      month = nextMonth;
    }
    return result;
  }

  // ─── Statistiques globales ─────────────────────────────────────────────────

  /// Moyenne de secondes par semaine (sur les 4 dernières semaines)
  int getWeeklyAverageSeconds() {
    final now = DateTime.now();
    final total = getTotalSeconds(now.subtract(const Duration(days: 28)), now);
    return (total / 4).round();
  }

  /// Total absolu de toutes les sessions enregistrées
  int getAllTimeSeconds() {
    int total = 0;
    for (final key in _box.keys) {
      total += (_box.get(key) as int? ?? 0);
    }
    return total;
  }

  // ─── Utilitaires ──────────────────────────────────────────────────────────

  /// Formate une date en clé Hive 'YYYY-MM-DD'
  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Formate des secondes en chaîne lisible : '2h 15min', '45min', '30s'
  static String formatSeconds(int seconds) {
    if (seconds <= 0) return '0min';
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m > 0 ? '${h}h ${m}min' : '${h}h';
    return '${m}min';
  }

  /// Tronque une DateTime à minuit (ignore l'heure)
  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
}
