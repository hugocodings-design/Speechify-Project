import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../config.dart';

class Voice {
  final String name;
  final String displayName;
  final String languageCode;
  /// Vrai pour une voix locale (moteur du téléphone, hors ligne) plutôt
  /// qu'une voix cloud (Google TTS, nécessite le réseau + quota API).
  final bool isLocal;
  /// Faux pour les voix qui ne renvoient pas de marqueurs SSML (ex: Chirp3-HD
  /// de Google, qui accepte le SSML mais ignore silencieusement les <mark>)
  /// — le surlignage se limite alors à la phrase entière, pas mot par mot.
  final bool hasWordTiming;

  const Voice({
    required this.name,
    required this.displayName,
    required this.languageCode,
    this.isLocal = false,
    this.hasWordTiming = true,
  });

  factory Voice.fromJson(Map<String, dynamic> json) {
    return Voice(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      languageCode: json['language_code'] as String,
    );
  }
}

class TtsService {
  final String apiBaseUrl;
  late final Dio _dio;
  final _logger = Logger();
  CancelToken _cancelToken = CancelToken();

  TtsService({this.apiBaseUrl = AppConfig.backendUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  /// Annuler toutes les requêtes en cours (appeler au dispose)
  void cancel() {
    _cancelToken.cancel('disposed');
    _cancelToken = CancelToken();
  }

  /// Fetch available voices from backend
  Future<List<Voice>> getAvailableVoices() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/voices', cancelToken: _cancelToken);

      if (response.statusCode == 200 && response.data != null) {
        final voices = (response.data!['voices'] as List)
            .map((v) => Voice.fromJson(v as Map<String, dynamic>))
            .toList();
        _logger.i('Fetched ${voices.length} voices');
        return voices;
      }
      throw Exception('Failed to fetch voices: ${response.statusCode}');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return [];
      _logger.e('Dio error fetching voices: $e');
      throw Exception('Failed to fetch voices: ${e.message}');
    } catch (e) {
      _logger.e('Error fetching voices: $e');
      rethrow;
    }
  }

  /// Synthesize text to speech
  /// Returns base64-encoded audio content
  Future<Map<String, dynamic>> synthesizeText({
    required String text,
    required String voiceName,
    String languageCode = "en-US",
  }) async {
    try {
      if (text.isEmpty) {
        throw Exception("Text cannot be empty");
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/synthesize',
        cancelToken: _cancelToken,
        data: {
          'text': text,
          'voice_name': voiceName,
          'language_code': languageCode,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        _logger.i('Text synthesized: ${text.length} chars');
        return response.data!;
      }
      throw Exception('Synthesis failed: ${response.statusCode}');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw Exception('cancelled');
      // Connexion coupée car l'app a été fermée pendant la synthèse
      final errStr = (e.message ?? '') + (e.error?.toString() ?? '');
      if (errStr.contains('connection abort') || errStr.contains('Software caused') || errStr.contains('Connection reset')) {
        throw Exception('cancelled');
      }
      _logger.e('Dio error during synthesis: $e');
      throw Exception('Synthesis failed: ${e.message}');
    } catch (e) {
      _logger.e('Error during synthesis: $e');
      rethrow;
    }
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('Health check failed: $e');
      return false;
    }
  }
}
