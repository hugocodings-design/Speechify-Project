import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'local_llm_service.dart';

/// Traductions 100 % gratuites, faites sur le téléphone — aucune API payante :
///  - traduction en direct pendant la lecture : Google ML Kit (traducteur
///    neuronal embarqué, instantané, hors ligne une fois ses modèles de
///    langue téléchargés — téléchargement gratuit, ~30 Mo par langue) ;
///  - traduction d'un passage choisi (bouton « Traduire ») : l'IA locale
///    (Qwen), de meilleure qualité sur les tournures littéraires — ou ML Kit
///    si le modèle d'IA n'est pas installé.
class TranslationService {
  static const _cacheBoxName = 'translation_cache';
  static const _cacheCap = 2000;
  static const _cachePurgeCount = 300;

  /// Cache en mémoire — coût zéro pour re-traduire la même phrase dans la
  /// même session (ex: retour en arrière dans le livre).
  static final Map<String, String> _memoryCache = {};

  // ── Traduction d'un passage choisi (IA locale, sinon ML Kit) ─────────────

  /// Chaque élément du flux est la traduction (partielle avec l'IA locale,
  /// qui écrit au fil de l'eau) à jour.
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
      yield await translateLive(text: text, sourceLang: sourceLang, targetLang: targetLang);
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

  // ── Traduction en direct (ML Kit, sur le téléphone) ──────────────────────

  static const Map<String, TranslateLanguage> _mlkitLanguages = {
    'en': TranslateLanguage.english,
    'fr': TranslateLanguage.french,
    'es': TranslateLanguage.spanish,
    'pt': TranslateLanguage.portuguese,
  };
  static final Map<String, OnDeviceTranslator> _mlkitTranslators = {};
  static final Map<String, Future<bool>> _mlkitModelReady = {};

  /// Télécharge (une seule fois, gratuitement) le modèle ML Kit de [lang].
  /// Renvoie false si impossible (pas de réseau au tout premier usage).
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
    } catch (e) {
      debugPrint('[TRANSLATE] préparation ML Kit échouée : $e');
    }
  }

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
    if (src == null || tgt == null) {
      throw Exception('Langue non prise en charge : $sourceLang → $targetLang');
    }
    final ready = await _ensureMlkitModel(sourceLang) && await _ensureMlkitModel(targetLang);
    if (!ready) {
      throw Exception('Modèles de traduction pas encore téléchargés (connexion requise une fois)');
    }
    final translator = _mlkitTranslators['$sourceLang|$targetLang'] ??=
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: tgt);
    final result = await translator.translateText(text);
    _memoryCache[cacheKey] = result;
    return result;
  }

  /// Pas de TTL (une traduction ne change pas dans le temps), juste un
  /// plafond simple pour que le cache ne grossisse pas indéfiniment.
  Future<void> _purgeOldCacheEntriesIfNeeded(Box cacheBox) async {
    if (cacheBox.length <= _cacheCap) return;
    final keys = cacheBox.keys.toList();
    final toRemove = keys.take(_cachePurgeCount);
    await cacheBox.deleteAll(toRemove);
  }
}
