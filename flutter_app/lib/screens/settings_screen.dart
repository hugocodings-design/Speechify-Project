import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../main.dart' show themeModeNotifier, fontFamilyNotifier, fontSizeNotifier;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          // ── Apparence ────────────────────────────────────────────────────
          _SectionHeader(label: 'Apparence'),

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
          _SectionHeader(label: 'Texte'),

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

          const Divider(),

          // ── Connexion ────────────────────────────────────────────────────
          _SectionHeader(label: 'Connexion'),

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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
