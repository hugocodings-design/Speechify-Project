import '../services/tts_service.dart';
import 'chirp3_personas.dart';

/// Catalogue des voix cloud Google — copie exacte de la liste vérifiée
/// côté backend (chaque nom a été confirmé réel via client.list_voices()).
/// Utilisé directement par l'app maintenant que la synthèse se fait en
/// appel direct à l'API Google (plus besoin du backend pour la liste).
const List<Voice> cloudVoices = [
  // English (US)
  Voice(name: 'en-US-Neural2-D', displayName: 'English (US) - Male D', languageCode: 'en-US'),
  Voice(name: 'en-US-Neural2-C', displayName: 'English (US) - Female C', languageCode: 'en-US'),
  Voice(name: 'en-US-Neural2-F', displayName: 'English (US) - Female F', languageCode: 'en-US'),

  // English (UK)
  Voice(name: 'en-GB-Neural2-B', displayName: 'English (UK) - Male B', languageCode: 'en-GB'),
  Voice(name: 'en-GB-Neural2-F', displayName: 'English (UK) - Female F', languageCode: 'en-GB'),

  // Français (Canada)
  Voice(name: 'fr-CA-Neural2-A', displayName: 'Français (Canada) - Féminin A', languageCode: 'fr-CA'),
  Voice(name: 'fr-CA-Neural2-B', displayName: 'Français (Canada) - Masculin B', languageCode: 'fr-CA'),
  Voice(name: 'fr-CA-Neural2-C', displayName: 'Français (Canada) - Féminin C', languageCode: 'fr-CA'),
  Voice(name: 'fr-CA-Neural2-D', displayName: 'Français (Canada) - Masculin D', languageCode: 'fr-CA'),

  // Français (France) — seulement 2 voix distinctes existent chez Google
  Voice(name: 'fr-FR-Neural2-F', displayName: 'Français (France) - Féminin F', languageCode: 'fr-FR'),
  Voice(name: 'fr-FR-Neural2-G', displayName: 'Français (France) - Masculin G', languageCode: 'fr-FR'),

  // Español (España)
  Voice(name: 'es-ES-Neural2-A', displayName: 'Español (España) - Femenino A', languageCode: 'es-ES'),
  Voice(name: 'es-ES-Neural2-F', displayName: 'Español (España) - Masculino F', languageCode: 'es-ES'),
  Voice(name: 'es-ES-Neural2-H', displayName: 'Español (España) - Femenino H', languageCode: 'es-ES'),
  Voice(name: 'es-ES-Neural2-G', displayName: 'Español (España) - Masculino G', languageCode: 'es-ES'),

  // Español (US)
  Voice(name: 'es-US-Neural2-A', displayName: 'Español (US) - Femenino A', languageCode: 'es-US'),
  Voice(name: 'es-US-Neural2-B', displayName: 'Español (US) - Masculino B', languageCode: 'es-US'),
  Voice(name: 'es-US-Neural2-C', displayName: 'Español (US) - Femenino C', languageCode: 'es-US'),

  // Português (Brasil)
  Voice(name: 'pt-BR-Neural2-A', displayName: 'Português (Brasil) - Feminino A', languageCode: 'pt-BR'),
  Voice(name: 'pt-BR-Neural2-B', displayName: 'Português (Brasil) - Masculino B', languageCode: 'pt-BR'),
  Voice(name: 'pt-BR-Neural2-C', displayName: 'Português (Brasil) - Feminino C', languageCode: 'pt-BR'),

  // Português (Portugal) — seulement 2 voix distinctes existent chez Google
  Voice(name: 'pt-PT-Wavenet-E', displayName: 'Português (Portugal) - Feminino E', languageCode: 'pt-PT'),
  Voice(name: 'pt-PT-Wavenet-F', displayName: 'Português (Portugal) - Masculino F', languageCode: 'pt-PT'),
];

/// Voix Chirp3-HD — générées à partir des 30 personas partagées x les
/// langues où Google les offre (voir chirp3_personas.dart). Pas de
/// surlignage mot par mot pour ces voix (hasWordTiming: false) : Google ne
/// renvoie pas de timepoints pour les marqueurs SSML sur ce tier, testé et
/// confirmé directement contre l'API.
final List<Voice> chirp3Voices = [
  for (final lang in chirp3Languages.entries)
    for (var i = 0; i < chirp3Personas.length; i++)
      Voice(
        // Le nom technique envoyé à Google reste celui d'origine (ex:
        // "en-US-Chirp3-HD-Kore") — seul l'affichage utilisateur change.
        name: '${lang.key}-Chirp3-HD-${chirp3Personas[i].name}',
        displayName:
            '${lang.value} - ${chirp3Personas[i].isFemale ? 'Féminin' : 'Masculin'} ${chirp3LocalizedNames[lang.key]![i]}',
        languageCode: lang.key,
        hasWordTiming: false,
      ),
];

/// Catalogue complet des voix cloud (Neural2 + Chirp3-HD), utilisé par
/// l'app à la place de [cloudVoices] seul.
final List<Voice> allCloudVoices = [...cloudVoices, ...chirp3Voices];
