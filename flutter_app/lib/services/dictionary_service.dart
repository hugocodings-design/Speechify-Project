import 'package:hive_flutter/hive_flutter.dart';
import 'local_llm_service.dart';
import 'sherpa_tts_service.dart';

/// Catégorie d'erreur réseau — permet à l'UI (dictionary_sheet.dart) d'afficher
/// un message localisé plutôt que le texte français codé en dur ci-dessous,
/// qui ne sert alors plus que de repli pour le debug (toString()).
enum DictionaryErrorCode { quotaExceeded, unexpectedResponse, unreachable, localModelMissing }

/// Levée sur un pépin réseau (timeout, pas de connexion, quota épuisé...).
class DictionaryNetworkException implements Exception {
  final String message;
  final DictionaryErrorCode code;
  DictionaryNetworkException(this.message, [this.code = DictionaryErrorCode.unreachable]);
  @override
  String toString() => 'Erreur réseau : $message';
}

/// Résultat d'une recherche de mot, prêt à être affiché OU enregistré tel
/// quel dans un DictionaryEntry (voir dictionary_sheet.dart). Contrairement
/// à un dictionnaire classique, l'IA locale rédige directement la définition et
/// les synonymes DANS LA LANGUE CIBLE choisie par l'utilisateur — pas
/// d'étape de traduction séparée, l'IA comprend le mot et explique son sens
/// dans la langue voulue en une seule requête.
class DictionaryLookup {
  final String word;
  final String translatedWord;
  final String partOfSpeech;
  final String definition;
  final String example;
  final List<String> synonyms;

  const DictionaryLookup({
    required this.word,
    required this.translatedWord,
    required this.partOfSpeech,
    required this.definition,
    required this.example,
    required this.synonyms,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'translatedWord': translatedWord,
        'partOfSpeech': partOfSpeech,
        'definition': definition,
        'example': example,
        'synonyms': synonyms,
      };

  factory DictionaryLookup.fromJson(Map<dynamic, dynamic> j) => DictionaryLookup(
        word: j['word'] as String,
        translatedWord: j['translatedWord'] as String,
        partOfSpeech: j['partOfSpeech'] as String,
        definition: j['definition'] as String,
        example: j['example'] as String,
        synonyms: (j['synonyms'] as List).cast<String>(),
      );
}

/// Cherche un mot (définition + synonymes, dans la langue choisie par
/// l'utilisateur) avec l'IA locale du téléphone — 100 % gratuit, aucune
/// API payante.
class DictionaryService {
  static const _cacheBoxName = 'dictionary_cache';
  static const _cacheCap = 500;
  static const _cachePurgeCount = 100;

  /// Cache en mémoire — coût zéro pour re-chercher le même mot dans la même
  /// session (ex: l'utilisateur ferme puis rouvre la fiche par erreur).
  static final Map<String, DictionaryLookup> _memoryCache = {};

  /// « fr-FR » → « fr ».
  static String shortLang(String locale) => locale.split('-').first.toLowerCase();

  /// Déduit la langue du livre depuis le nom de voix choisi pour ce livre.
  /// Voix IA locale (« sherpa-fr-siwis ») : sa langue déclarée. Sinon on
  /// cherche « xx-XX » n'importe où dans le nom (« local-en-US-f1 »).
  static String langFromVoiceName(String voiceName) {
    final ai = SherpaTtsService.voiceByName(voiceName);
    if (ai != null) return shortLang(ai.languageCode);
    final m = RegExp(r'([a-z]{2})-([A-Z]{2})').firstMatch(voiceName);
    return m?.group(1) ?? 'en';
  }

  /// Définition par l'IA locale (Qwen sur le téléphone — gratuit, hors
  /// ligne, aucune clé API). Chaque élément du flux est la fiche complétée
  /// au fur et à mesure que le modèle l'écrit : l'interface l'affiche dès
  /// les premiers mots. Résultat mis en cache (mémoire + Hive).
  /// [contextSentence] : la phrase où le mot apparaît, pour expliquer le sens
  /// qu'il a À CET ENDROIT (l'IA locale en tient compte).
  Stream<DictionaryLookup> lookupStream({
    required String word,
    required String sourceLang,
    required String targetLang,
    String? contextSentence,
  }) async* {
    final ctx = (contextSentence ?? '').trim();
    final local = LocalLlmService.instance;
    if (!await local.isAvailable()) {
      throw DictionaryNetworkException(
          'IA locale non installée', DictionaryErrorCode.localModelMissing);
    }

    // Clé de cache propre à l'IA locale, liée au contexte : un même mot peut
    // avoir un autre sens dans une autre phrase.
    final cacheKey = 'local|$sourceLang|$targetLang|${word.toLowerCase()}|${ctx.hashCode}';
    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      yield cached;
      return;
    }
    final cacheBox = Hive.box(_cacheBoxName);
    final cachedRaw = cacheBox.get(cacheKey);
    if (cachedRaw != null) {
      final l = DictionaryLookup.fromJson(cachedRaw as Map);
      _memoryCache[cacheKey] = l;
      yield l;
      return;
    }

    DictionaryLookup? last;
    await for (final d in local.define(
      word: word,
      sourceLang: sourceLang,
      targetLang: targetLang,
      contextSentence: ctx.isEmpty ? null : ctx,
    )) {
      last = DictionaryLookup(
        word: word,
        translatedWord: d.translatedWord,
        partOfSpeech: d.partOfSpeech,
        definition: d.definition,
        example: d.example,
        synonyms: d.synonyms,
      );
      if (d.hasContent) yield last;
      if (d.complete && d.hasContent) {
        _memoryCache[cacheKey] = last;
        await cacheBox.put(cacheKey, last.toJson());
        await _purgeOldCacheEntriesIfNeeded(cacheBox);
      }
    }
    if (last == null || last.definition.isEmpty) {
      throw DictionaryNetworkException(
          'Réponse inattendue de l\'IA locale', DictionaryErrorCode.unexpectedResponse);
    }
  }

  /// Pas de TTL (une définition ne change pas dans le temps), juste un
  /// plafond simple pour que le cache ne grossisse pas indéfiniment sur une
  /// utilisation de plusieurs années.
  Future<void> _purgeOldCacheEntriesIfNeeded(Box cacheBox) async {
    if (cacheBox.length <= _cacheCap) return;
    final keys = cacheBox.keys.toList();
    // L'ordre d'insertion Hive suffit ici (on ne fait qu'AJOUTER au cache,
    // jamais le réécrire) : les entrées les plus anciennes sont en tête.
    final toRemove = keys.take(_cachePurgeCount);
    await cacheBox.deleteAll(toRemove);
  }
}
