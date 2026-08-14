import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/tts_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Box _settingsBox;
  final TtsService _ttsService = TtsService();

  List<Voice> _voices = [];
  bool _loadingVoices = true;

  String _defaultVoice = 'en-US-Neural2-C';
  double _defaultSpeed = 1.0;

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box('settings');
    _loadSavedSettings();
    _loadVoices();
  }

  void _loadSavedSettings() {
    setState(() {
      _defaultVoice =
          _settingsBox.get('default_voice', defaultValue: 'en-US-Neural2-C') as String;
      _defaultSpeed =
          (_settingsBox.get('default_speed', defaultValue: 1.0) as num).toDouble();
    });
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await _ttsService.getAvailableVoices();
      if (mounted) {
        setState(() {
          _voices = voices;
          _loadingVoices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingVoices = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de charger les voix: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveVoice(String? voice) async {
    if (voice == null) return;
    await _settingsBox.put('default_voice', voice);
    setState(() => _defaultVoice = voice);
  }

  Future<void> _saveSpeed(double speed) async {
    await _settingsBox.put('default_speed', speed);
    setState(() => _defaultSpeed = speed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Section voix
          _buildSectionHeader('Voix par défaut'),
          _buildVoiceSelector(),

          const Divider(height: 32),

          // Section vitesse
          _buildSectionHeader('Vitesse de lecture par défaut'),
          _buildSpeedSelector(),

          const Divider(height: 32),

          // Section info
          _buildSectionHeader('À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Speechify'),
            subtitle: Text('Version 1.0.0 — Propulsé par Google Cloud TTS'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildVoiceSelector() {
    if (_loadingVoices) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_voices.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.warning_amber, color: Colors.orange),
        title: Text('Voix non disponibles'),
        subtitle: Text('Vérifiez la connexion au backend'),
      );
    }

    final voiceNames = _voices.map((v) => v.name).toList();
    final currentVoice =
        voiceNames.contains(_defaultVoice) ? _defaultVoice : voiceNames.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButton<String>(
        value: currentVoice,
        isExpanded: true,
        onChanged: _saveVoice,
        items: _voices.map((voice) {
          return DropdownMenuItem<String>(
            value: voice.name,
            child: Text(voice.displayName, overflow: TextOverflow.ellipsis),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSpeedSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _speedOptions.map((speed) {
          final isSelected = _defaultSpeed == speed;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${speed}x'),
              selected: isSelected,
              onSelected: (_) => _saveSpeed(speed),
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
