/// Modèle pour lib/secrets.dart (fichier réel exclu de Git).
/// Copier ce fichier en "secrets.dart" et y mettre la vraie clé API.
class Secrets {
  static const String googleTtsApiKey = 'REMPLACER_PAR_LA_VRAIE_CLE';

  /// Clé Google AI Studio (aistudio.google.com), pour Gemini — dictionnaire
  /// du lecteur.
  static const String geminiApiKey = 'REMPLACER_PAR_LA_VRAIE_CLE';

  // Traduction en direct pendant la lecture : réutilise googleTtsApiKey
  // ci-dessus (Cloud Translation API doit être activée sur ce même projet
  // Google Cloud) — voir TranslationService.
}
