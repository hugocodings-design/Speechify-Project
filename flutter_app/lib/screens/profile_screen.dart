import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../main.dart'
    show themeModeNotifier, fontFamilyNotifier, fontSizeNotifier, readerMarginNotifier,
        dictionaryLanguageNotifier, translationLanguageNotifier;
import '../services/stats_service.dart';
import '../widgets/section_header.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Période sélectionnée : 0=Jour, 1=Semaine, 2=Mois, 3=6 mois, 4=Année
  int _selectedPeriod = 1;

  static const _periodLabels = ['Jour', 'Semaine', 'Mois', '6 mois', 'Année'];

  // ── Paramètres (relocalisés depuis l'ancien settings_screen.dart) ────────
  late TextEditingController _serverUrlController;

  @override
  void initState() {
    super.initState();
    final settings = Hive.box('settings');
    _serverUrlController = TextEditingController(
      text: settings.get('serverUrl', defaultValue: 'http://192.168.0.160:8000') as String,
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  void _saveServerUrl(String value) {
    Hive.box('settings').put('serverUrl', value.trim());
  }

  void _setTheme(ThemeMode mode) {
    themeModeNotifier.value = mode;
    final key = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';
    Hive.box('settings').put('themeMode', key);
  }

  void _setFontSize(double size) {
    fontSizeNotifier.value = size;
    Hive.box('settings').put('fontSize', size);
  }

  void _setFontFamily(String? family) {
    fontFamilyNotifier.value = family;
    Hive.box('settings').put('fontFamily', family);
  }

  void _setReaderMargin(double margin) {
    readerMarginNotifier.value = margin;
    Hive.box('settings').put('readerMargin', margin);
  }

  void _setDictionaryLanguage(String code) {
    dictionaryLanguageNotifier.value = code;
    Hive.box('settings').put('dictionaryLanguage', code);
  }

  void _setTranslationLanguage(String code) {
    translationLanguageNotifier.value = code;
    Hive.box('settings').put('translationLanguage', code);
  }

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
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

                // ── Paramètres (relocalisés depuis l'onglet Paramètres) ──────
                const SizedBox(height: 16),
                const Divider(),
                _buildSettingsSection(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Apparence ────────────────────────────────────────────────────
        const SectionHeader(label: 'Apparence'),

        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, _) => Column(
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('Système'),
                secondary: const Icon(Icons.brightness_auto_rounded),
                value: ThemeMode.system,
                groupValue: themeMode,
                onChanged: (v) => _setTheme(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Clair'),
                secondary: const Icon(Icons.light_mode_rounded),
                value: ThemeMode.light,
                groupValue: themeMode,
                onChanged: (v) => _setTheme(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Sombre'),
                secondary: const Icon(Icons.dark_mode_rounded),
                value: ThemeMode.dark,
                groupValue: themeMode,
                onChanged: (v) => _setTheme(v!),
              ),
            ],
          ),
        ),

        const Divider(),

        // ── Texte ────────────────────────────────────────────────────────
        const SectionHeader(label: 'Texte'),

        ValueListenableBuilder<double>(
          valueListenable: fontSizeNotifier,
          builder: (context, fontSize, _) => Column(
            children: [
              ListTile(
                leading: const Icon(Icons.format_size_rounded),
                title: const Text('Taille du texte'),
                trailing: Text(
                  '${fontSize.toInt()} pt',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        onChanged: _setFontSize,
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 22)),
                  ],
                ),
              ),
            ],
          ),
        ),

        ValueListenableBuilder<String?>(
          valueListenable: fontFamilyNotifier,
          builder: (context, fontFamily, _) => ListTile(
            leading: const Icon(Icons.font_download_rounded),
            title: const Text('Police'),
            trailing: DropdownButton<String?>(
              value: fontFamily,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: null, child: Text('Défaut')),
                DropdownMenuItem(value: 'Georgia', child: Text('Georgia')),
                DropdownMenuItem(value: 'serif', child: Text('Serif')),
                DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
              ],
              onChanged: _setFontFamily,
            ),
          ),
        ),

        ValueListenableBuilder<double>(
          valueListenable: readerMarginNotifier,
          builder: (context, margin, _) => Column(
            children: [
              ListTile(
                leading: const Icon(Icons.vertical_align_center_rounded),
                title: const Text('Marge en mode texte seul'),
                subtitle: const Text(
                  "Espace au-dessus et au-dessous du texte quand on masque "
                  "le lecteur (l'œil) pendant la lecture",
                ),
                trailing: Text(
                  '${margin.toInt()} px',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Slider(
                  value: margin,
                  min: 0,
                  max: 120,
                  divisions: 12,
                  onChanged: _setReaderMargin,
                ),
              ),
            ],
          ),
        ),

        ValueListenableBuilder<String>(
          valueListenable: dictionaryLanguageNotifier,
          builder: (context, dictionaryLanguage, _) => ListTile(
            leading: const Icon(Icons.menu_book_rounded),
            title: const Text('Langue du dictionnaire'),
            subtitle: const Text('Langue des définitions pendant la lecture'),
            trailing: DropdownButton<String>(
              value: dictionaryLanguage,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'fr', child: Text('Français')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'pt', child: Text('Português')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
              ],
              onChanged: (value) {
                if (value != null) _setDictionaryLanguage(value);
              },
            ),
          ),
        ),

        ValueListenableBuilder<String>(
          valueListenable: translationLanguageNotifier,
          builder: (context, translationLanguage, _) => ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: const Text('Langue de traduction'),
            subtitle: const Text('Traduction en direct et manuelle pendant la lecture'),
            trailing: DropdownButton<String>(
              value: translationLanguage,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'fr', child: Text('Français')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'pt', child: Text('Português')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
              ],
              onChanged: (value) {
                if (value != null) _setTranslationLanguage(value);
              },
            ),
          ),
        ),

        const Divider(),

        // ── Connexion ────────────────────────────────────────────────────
        const SectionHeader(label: 'Connexion'),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _serverUrlController,
            decoration: InputDecoration(
              labelText: 'URL du serveur TTS',
              hintText: 'http://192.168.0.160:8000',
              prefixIcon: const Icon(Icons.dns_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded),
                tooltip: 'Enregistrer',
                onPressed: () {
                  _saveServerUrl(_serverUrlController.text);
                  FocusScope.of(context).unfocus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('URL enregistrée'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
            onSubmitted: _saveServerUrl,
            keyboardType: TextInputType.url,
          ),
        ),
      ],
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
