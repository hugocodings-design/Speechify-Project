import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/stats_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Période sélectionnée : 0=Jour, 1=Semaine, 2=Mois, 3=6 mois, 4=Année
  int _selectedPeriod = 1;

  static const _periodLabels = ['Jour', 'Semaine', 'Mois', '6 mois', 'Année'];

  DateTimeRange _getRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_selectedPeriod) {
      case 0: // Jour
        return DateTimeRange(start: today, end: today);
      case 1: // Semaine
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case 2: // Mois
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case 3: // 6 mois
        return DateTimeRange(start: DateTime(now.year, now.month - 5, 1), end: today);
      case 4: // Année
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      default:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('reading_stats').listenable(),
        builder: (context, box, _) {
          final stats = StatsService(box as dynamic);
          final range = _getRange();
          final totalSec = stats.getTotalSeconds(range.start, range.end);
          final weekAvgSec = stats.getWeeklyAverageSeconds();
          final allTimeSec = stats.getAllTimeSeconds();

          // Données du graphique
          final Map<String, int> chartData;
          if (_selectedPeriod <= 1) {
            chartData = stats.getDailyBreakdown(range.start, range.end);
          } else if (_selectedPeriod <= 2) {
            chartData = stats.getWeeklyBreakdown(range.start, range.end);
          } else {
            chartData = stats.getMonthlyBreakdown(range.start, range.end);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sélecteur de période ────────────────────────────────────
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _periodLabels.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ChoiceChip(
                      label: Text(_periodLabels[i]),
                      selected: _selectedPeriod == i,
                      onSelected: (_) => setState(() => _selectedPeriod = i),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Carte principale : temps de la période ──────────────────
                _StatCard(
                  icon: Icons.timer_outlined,
                  label: 'Temps de lecture — ${_periodLabels[_selectedPeriod].toLowerCase()}',
                  value: StatsService.formatSeconds(totalSec),
                  highlight: true,
                ),
                const SizedBox(height: 12),

                // ── Deux cartes secondaires ─────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.bar_chart_rounded,
                        label: 'Moy. par semaine',
                        value: StatsService.formatSeconds(weekAvgSec),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.auto_stories_outlined,
                        label: 'Total de lecture',
                        value: StatsService.formatSeconds(allTimeSec),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Graphique en barres ─────────────────────────────────────
                if (chartData.isNotEmpty) ...[
                  Text(
                    'RÉPARTITION',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 12),
                  _BarChart(data: chartData, period: _selectedPeriod),
                ],

                // ── Message si aucune donnée ────────────────────────────────
                if (allTimeSec == 0) ...[
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.headphones_outlined,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'Aucune lecture enregistrée',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Commence à lire pour voir tes statistiques',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Widgets internes ─────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? color.withOpacity(0.1)
            : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: highlight ? Border.all(color: color.withOpacity(0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: highlight ? color : Colors.grey[600], size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: highlight ? color : null,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final Map<String, int> data;
  final int period;

  const _BarChart({required this.data, required this.period});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b);
    const maxHeight = 100.0;
    const minHeight = 4.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: maxHeight + 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.entries.map((entry) {
            final height = maxVal > 0
                ? (entry.value / maxVal * maxHeight).clamp(minHeight, maxHeight)
                : minHeight;
            final isToday = entry.key ==
                StatsService.dateKey(DateTime.now());
            final barColor = isToday ? color : color.withOpacity(0.5);

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Valeur au survol (tooltip)
                    if (entry.value > 0)
                      Tooltip(
                        message: StatsService.formatSeconds(entry.value),
                        child: const SizedBox.shrink(),
                      ),
                    // Barre
                    Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Étiquette de date
                    Text(
                      _shortLabel(entry.key),
                      style: TextStyle(
                        fontSize: 9,
                        color: isToday ? color : Colors.grey[500],
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Transforme une clé 'YYYY-MM-DD' en étiquette courte
  String _shortLabel(String key) {
    final parts = key.split('-');
    if (parts.length < 3) return key;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    // Pour les périodes longues (mois, 6 mois, année), afficher mois
    if (period >= 3) {
      const monthNames = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun',
                          'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];
      return monthNames[(month - 1).clamp(0, 11)];
    }
    // Pour semaine/mois, afficher jour/mois
    return '$day/${month.toString().padLeft(2, '0')}';
  }
}
