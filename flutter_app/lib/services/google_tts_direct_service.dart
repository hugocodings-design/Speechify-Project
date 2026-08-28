import 'package:dio/dio.dart';
import '../secrets.dart';
import '../models/word_timing.dart';

/// Appelle l'API Google Cloud Text-to-Speech DIRECTEMENT depuis le
/// téléphone, avec une clé API — contourne complètement le backend
/// (donc plus besoin que le PC soit allumé ni sur le même Wi-Fi).
///
/// Réplique ce que fait le backend Python : texte envoyé en SSML avec un
/// marqueur avant chaque mot, pour récupérer les timestamps mot par mot
/// (nécessite l'API v1beta1, seule à exposer enableTimePointing).
class GoogleTtsDirectService {
  static const _endpoint =
      'https://texttospeech.googleapis.com/v1beta1/text:synthesize';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  CancelToken _cancelToken = CancelToken();

  /// Annule toute requête en cours (ex: l'utilisateur saute vers une autre
  /// phrase avant que la synthèse précédente ne soit terminée).
  void cancel() {
    _cancelToken.cancel('superseded');
    _cancelToken = CancelToken();
  }

  /// Synthétise [text] avec la voix [voiceName]/[languageCode]. Retourne la
  /// même forme que TtsService.synthesizeText : audio_content (base64) +
  /// word_timings, pour rester compatible avec le reste du pipeline.
  Future<Map<String, dynamic>> synthesizeText({
    required String text,
    required String voiceName,
    required String languageCode,
  }) async {
    if (text.trim().isEmpty) {
      throw Exception('Text cannot be empty');
    }

    final words = text.split(' ');
    final ssmlBody = [
      for (var i = 0; i < words.length; i++) '<mark name="w$i"/>${_xmlEscape(words[i])}'
    ].join(' ');
    final ssml = '<speak>$ssmlBody</speak>';

    final body = {
      'input': {'ssml': ssml},
      'voice': {'languageCode': languageCode, 'name': voiceName},
      'audioConfig': {'audioEncoding': 'MP3', 'speakingRate': 1.0},
      'enableTimePointing': ['SSML_MARK'],
    };

    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _endpoint,
          queryParameters: {'key': Secrets.googleTtsApiKey},
          data: body,
          cancelToken: _cancelToken,
        );

        final data = response.data!;
        final timepoints = (data['timepoints'] as List?) ?? [];
        final wordTimings = <Map<String, dynamic>>[];
        for (final tp in timepoints) {
          final markName = tp['markName'] as String?;
          final timeSeconds = tp['timeSeconds'];
          if (markName == null || timeSeconds == null) continue;
          final idx = int.tryParse(markName.substring(1));
          if (idx == null || idx < 0 || idx >= words.length) continue;
          wordTimings.add({'word': words[idx], 'time': timeSeconds});
        }

        return {
          'audio_content': data['audioContent'],
          'voice_used': voiceName,
          'characters_used': text.length,
          'format': 'mp3',
          'word_timings': wordTimings,
        };
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 429 && attempt < maxRetries - 1) {
          final delay = Duration(milliseconds: (500 * (1 << attempt)));
          await Future.delayed(delay);
          continue;
        }
        if (CancelToken.isCancel(e)) throw Exception('cancelled');
        final errStr = (e.message ?? '') + (e.error?.toString() ?? '');
        if (errStr.contains('connection abort') ||
            errStr.contains('Software caused') ||
            errStr.contains('Connection reset')) {
          throw Exception('cancelled');
        }
        rethrow;
      }
    }
    throw Exception('Synthesis failed after retries');
  }

  /// Caractères de contrôle C0 (0x00-0x1F, sauf tabulation/LF/CR) : illégaux
  /// en XML 1.0 quelle que soit leur position, donc dans le SSML aussi —
  /// mais AUCUN échappement (&amp;/&lt;/&gt;) ne peut les rendre valides,
  /// contrairement aux caractères spéciaux normaux. Une extraction PDF
  /// bancale peut en laisser un en PLEIN MILIEU d'un mot par ailleurs
  /// parfait (ex: "la⟨0x02⟩tter" au lieu de "latter"), invisible à l'écran
  /// mais qui fait rejeter toute la phrase par l'API Google TTS avec un
  /// générique "Request contains an invalid argument." — sans rien à voir
  /// avec le contenu texte apparent, ce qui le rend très difficile à
  /// repérer sans regarder les points de code un par un.
  static final RegExp _invalidXmlControlChars =
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

  String _xmlEscape(String text) {
    return text
        .replaceAll(_invalidXmlControlChars, '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Parse les timings mot par mot depuis la réponse — même format que
  /// celui utilisé par le pipeline existant côté backend.
  List<WordTiming> parseWordTimingsFromResult(Map<String, dynamic> result) =>
      parseWordTimings(result['word_timings']);
}
