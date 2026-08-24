import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum LocalVoiceGender { male, female }

/// TTS local (moteur natif du téléphone) — fonctionne sans réseau, sans
/// quota, en 4G loin de chez soi. Qualité de voix inférieure aux voix
/// cloud "Journey"/"Neural2", mais dispo partout comme filet de secours.
class LocalTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  /// Appelé à chaque début de mot prononcé, avec l'offset du caractère de
  /// début dans le texte de l'utterance en cours — alimente le surlignage
  /// mot par mot pour les voix locales.
  void Function(int charStart)? _onWordBoundary;

  void setWordBoundaryHandler(void Function(int charStart)? handler) {
    _onWordBoundary = handler;
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _tts.awaitSpeakCompletion(true);
    _tts.setProgressHandler((text, start, end, word) {
      _onWordBoundary?.call(start);
    });
    _initialized = true;
  }

  /// Prononce [text] avec la voix [option] à la vitesse [speed] (1.0 = normal).
  /// Se termine quand la phrase est finie.
  Future<void> speak(String text, {required LocalVoiceOption option, double speed = 1.0}) async {
    await _ensureInit();
    await _tts.setLanguage(option.languageCode);
    try {
      await _tts.setVoice({'name': option.deviceVoiceName, 'locale': option.languageCode});
    } catch (_) {
      // Repli sur la voix par défaut de la langue si ce code précis n'existe
      // plus sur l'appareil (variations selon les mises à jour du moteur TTS)
    }
    // Les voix locales du moteur Android lisent nettement plus vite que les
    // voix cloud à vitesse "1.0" équivalente — on réduit le débit de base
    // pour un rythme comparable, tout en respectant le réglage de vitesse
    // choisi par l'utilisateur.
    const baseRateFactor = 0.7;
    await _tts.setSpeechRate((speed * baseRateFactor).clamp(0.25, 1.2));
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
  Future<void> pause() => _tts.pause();

  /// Diagnostic temporaire : liste toutes les voix installées sur l'appareil.
  Future<void> debugListVoices() async {
    await _ensureInit();
    final voices = await _tts.getVoices;
    debugPrint('[TTS-VOICES] ${voices.length} voix trouvées :');
    for (final v in voices) {
      debugPrint('[TTS-VOICES] $v');
    }
  }

  /// Diagnostic temporaire : fait parler chaque voix candidate de [names]
  /// l'une après l'autre, chacune annonçant son propre numéro. [phrases]
  /// permet d'adapter le texte annoncé à la langue testée.
  Future<void> debugSpeakCandidates(
    List<String> names,
    String languageCode, {
    List<String>? phrases,
  }) async {
    await _ensureInit();
    await _tts.setLanguage(languageCode);
    await _tts.setSpeechRate(0.5);
    for (var i = 0; i < names.length; i++) {
      debugPrint('[TTS-CANDIDATE] Voix numéro ${i + 1} = ${names[i]}');
      try {
        await _tts.setVoice({'name': names[i], 'locale': languageCode});
      } catch (e) {
        debugPrint('[TTS-CANDIDATE] Échec setVoice pour ${names[i]}: $e');
        continue;
      }
      final phrase = (phrases != null && i < phrases.length) ? phrases[i] : 'Voice number ${i + 1}.';
      await _tts.speak(phrase);
    }
  }

  /// Voix locales proposées — 3 masculines + 3 féminines par langue quand
  /// possible, identifiées à l'oreille (le moteur Android n'expose pas le
  /// genre). Anglais limité aux US (pas de UK). Le français (France) n'a
  /// que 2 voix masculines locales distinctes disponibles sur l'appareil.
  static const List<LocalVoiceOption> availableVoices = [
    // Anglais (US)
    LocalVoiceOption(
      name: 'local-en-US-f1', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-tpf-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-en-US-f2', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-sfg-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-en-US-f3', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-iob-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-en-US-m1', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-iom-local', gender: LocalVoiceGender.male,
    ),
    LocalVoiceOption(
      name: 'local-en-US-m2', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-tpd-local', gender: LocalVoiceGender.male,
    ),
    LocalVoiceOption(
      name: 'local-en-US-m3', language: 'Anglais (US)', languageCode: 'en-US',
      deviceVoiceName: 'en-us-x-iol-local', gender: LocalVoiceGender.male,
    ),

    // Français (France)
    LocalVoiceOption(
      name: 'local-fr-FR-f1', language: 'Français (France)', languageCode: 'fr-FR',
      deviceVoiceName: 'fr-fr-x-frc-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-fr-FR-f2', language: 'Français (France)', languageCode: 'fr-FR',
      deviceVoiceName: 'fr-fr-x-fra-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-fr-FR-f3', language: 'Français (France)', languageCode: 'fr-FR',
      deviceVoiceName: 'fr-fr-x-vlf-local', gender: LocalVoiceGender.female,
    ),
    LocalVoiceOption(
      name: 'local-fr-FR-m1', language: 'Français (France)', languageCode: 'fr-FR',
      deviceVoiceName: 'fr-fr-x-frb-local', gender: LocalVoiceGender.male,
    ),
    LocalVoiceOption(
      name: 'local-fr-FR-m2', language: 'Français (France)', languageCode: 'fr-FR',
      deviceVoiceName: 'fr-fr-x-frd-local', gender: LocalVoiceGender.male,
    ),
  ];
}

class LocalVoiceOption {
  final String name;
  final String language;
  final String languageCode;
  final String deviceVoiceName;
  final LocalVoiceGender gender;

  const LocalVoiceOption({
    required this.name,
    required this.language,
    required this.languageCode,
    required this.deviceVoiceName,
    required this.gender,
  });
}
