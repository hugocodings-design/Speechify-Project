import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../secrets.dart';
import 'local_llm_service.dart';

/// Traduit une phrase à la volée pendant la lecture (bulle de traduction en
/// direct, voir reader_screen.dart) — via l'API Google Cloud Translation,
/// directement depuis le téléphone, sans passer par notre backend (même
/// logique que les autres services directs : le PC de l'utilisateur n'a pas
/// besoin d'être allumé).
///
/// Contrairement au dictionnaire (quelques mots par jour), cette
/// fonctionnalité peut appeler l'API des centaines de fois par livre lu.
/// Google Cloud Translation a été choisi ici plutôt que DeepL pour son
/// palier gratuit RÉCURRENT (500 000 caractères GRATUITS chaque mois, sans
/// jamais expirer) — DeepL n'offre plus qu'un crédit unique d'1 million de
/// caractères depuis juillet 2026, après quoi il devient payant sans
/// alternative gratuite. Réutilise la même clé API que la synthèse vocale
/// (Secrets.googleTtsApiKey) : Cloud Translation est activé sur ce même
/// projet Google Cloud.
class TranslationService {
  static const _endpoint = 'https://translation.googleapis.com/language/translate/v2';

  static const _cacheBoxName = 'translation_cache';
  static const _cacheCap = 2000;
  static const _cachePurgeCount = 300;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Cache en mémoire — coût zéro pour re-traduire la même phrase dans la
  /// même session (ex: retour en arrière dans le livre).
  static final Map<String, String> _memoryCache = {};

  /// Traduit [text] (langue [sourceLang], code court ISO 'en'/'fr'/'es'/'pt')
  /// vers [targetLang] (même format — Google Translate v2 utilise des codes
  /// courts en minuscules, contrairement à DeepL qui voulait des majuscules).
  /// Résultat mis en cache (mémoire + Hive) pour que la relecture d'un livre
  /// déjà lu ne coûte plus rien et fonctionne hors-ligne.
  Future<String> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (sourceLang == targetLang) return text;

    final cacheKey = '$sourceLang|$targetLang|$text';
    final cached = _memoryCache[cacheKey];
    if (cached != null) return cached;

    final cacheBox = Hive.box(_cacheBoxName);
    final cachedRaw = cacheBox.get(cacheKey) as String?;
    if (cachedRaw != null) {
      _memoryCache[cacheKey] = cachedRaw;
      return cachedRaw;
    }

    final result = await _fetchFromGoogle(text: text, sourceLang: sourceLang, targetLang: targetLang);

    _memoryCache[cacheKey] = result;
    await cacheBox.put(cacheKey, result);
    await _purgeOldCacheEntriesIfNeeded(cacheBox);
    return result;
  }

  // ── Traduction d'un passage choisi (IA locale Qwen, sinon Google) ────────

  /// Traduction manuelle (bouton « Traduire ») : avec l'IA locale si elle est
  /// installée — meilleure qualité qu'un traducteur classique sur les
  /// tournures littéraires — chaque élément du flux étant la traduction
  /// partielle à jour. Sinon un seul élément venant de Google Translate.
  Stream<String> translateStream({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async* {
    if (sourceLang == targetLang) {
      yield text;
      return;
    }
    final local = LocalLlmService.instance;
    if (!await local.isInstalled()) {
      yield await translate(text: text, sourceLang: sourceLang, targetLang: targetLang);
      return;
    }
    final cacheKey = 'local|$sourceLang|$targetLang|$text';
    final cacheBox = Hive.box(_cacheBoxName);
    final cached = _memoryCache[cacheKey] ?? cacheBox.get(cacheKey) as String?;
    if (cached != null) {
      yield cached;
      return;
    }
    var last = '';
    await for (final partial
        in local.translate(text: text, sourceLang: sourceLang, targetLang: targetLang)) {
      last = partial;
      yield partial;
    }
    last = last.trim();
    if (last.isEmpty) throw Exception('Traduction locale vide');
    _memoryCache[cacheKey] = last;
    await cacheBox.put(cacheKey, last);
    await _purgeOldCacheEntriesIfNeeded(cacheBox);
  }

  // ── Traduction en direct sur le téléphone (ML Kit) ───────────────────────

  static const Map<String, TranslateLanguage> _mlkitLanguages = {
    'en': TranslateLanguage.english,
    'fr': TranslateLanguage.french,
    'es': TranslateLanguage.spanish,
    'pt': TranslateLanguage.portuguese,
  };
  static final Map<String, OnDeviceTranslator> _mlkitTranslators = {};
  static final Map<String, Future<bool>> _mlkitModelReady = {};

  /// Télécharge (une seule fois, ~30 Mo par langue) le modèle ML Kit de
  /// [lang]. Renvoie false si impossible (pas de réseau au premier usage).
  static Future<bool> _ensureMlkitModel(String lang) {
    return _mlkitModelReady[lang] ??= () async {
      final code = _mlkitLanguages[lang]?.bcpCode;
      if (code == null) return false;
      final manager = OnDeviceTranslatorModelManager();
      if (await manager.isModelDownloaded(code)) return true;
      final ok = await manager.downloadModel(code, isWifiRequired: false);
      if (!ok) _mlkitModelReady.remove(lang); // réessayer plus tard
      return ok;
    }();
  }

  /// Prépare à l'avance les modèles d'une paire de langues (appelé à
  /// l'activation de la traduction en direct) — la première phrase n'attend
  /// alors pas le téléchargement.
  static Future<void> prepareLive(String sourceLang, String targetLang) async {
    try {
      await Future.wait([_ensureMlkitModel(sourceLang), _ensureMlkitModel(targetLang)]);
    } catch (_) {}
  }

  /// Traduction en direct pendant la lecture : modèle de traduction
  /// neuronal SUR LE TÉLÉPHONE (Google ML Kit) — instantané, gratuit, hors
  /// ligne une fois les modèles téléchargés. Repli sur Google Cloud
  /// Translation seulement si les modèles ne sont pas disponibles.
  Future<String> translateLive({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (sourceLang == targetLang) return text;
    final cacheKey = 'mlkit|$sourceLang|$targetLang|$text';
    final cached = _memoryCache[cacheKey];
    if (cached != null) return cached;

    final src = _mlkitLanguages[sourceLang];
    final tgt = _mlkitLanguages[targetLang];
    if (src != null && tgt != null) {
      try {
        final ready = await _ensureMlkitModel(sourceLang) && await _ensureMlkitModel(targetLang);
        if (ready) {
          final translator = _mlkitTranslators['$sourceLang|$targetLang'] ??=
              OnDeviceTranslator(sourceLanguage: src, targetLanguage: tgt);
          final result = await translator.translateText(text);
          _memoryCache[cacheKey] = result;
          return result;
        }
      } catch (e) {
        debugPrint('[TRANSLATE] ML Kit indisponible, repli Google : $e');
      }
    }
    return translate(text: text, sourceLang: sourceLang, targetLang: targetLang);
  }

  Future<String> _fetchFromGoogle({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _endpoint,
          queryParameters: {'key': Secrets.googleTtsApiKey},
          data: {
            'q': [text],
            'source': sourceLang,
            'target': targetLang,
            'format': 'text',
          },
        );
        final translations = response.data!['data']['translations'] as List;
        return _unescapeHtml((translations.first as Map)['translatedText'] as String);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        // 429 = débit dépassé ; 5xx = pépin serveur transitoire.
        final isRetryable = status == 429 || (status != null && status >= 500);
        if (isRetryable && attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Google Translate injoignable après plusieurs tentatives');
  }

  /// Malgré `format: 'text'`, l'API renvoie encore certaines entités HTML
  /// (`&#39;`, `&quot;`, `&amp;`) — sans ce nettoyage on affiche
  /// littéralement "l&#39;homme" au lieu de "l'homme".
  String _unescapeHtml(String text) => text
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// Pas de TTL (une traduction ne change pas dans le temps), juste un
  /// plafond simple pour que le cache ne grossisse pas indéfiniment — plus
  /// haut que celui du dictionnaire car ce cache grossit une phrase à la
  /// fois pendant toute la durée d'un livre, pas un mot à la fois.
  Future<void> _purgeOldCacheEntriesIfNeeded(Box cacheBox) async {
    if (cacheBox.length <= _cacheCap) return;
    final keys = cacheBox.keys.toList();
    final toRemove = keys.take(_cachePurgeCount);
    await cacheBox.deleteAll(toRemove);
  }
}
