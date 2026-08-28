import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../secrets.dart';

/// Levée sur un pépin réseau (timeout, pas de connexion, quota épuisé...).
class DictionaryNetworkException implements Exception {
  final String message;
  DictionaryNetworkException(this.message);
  @override
  String toString() => 'Erreur réseau : $message';
}

/// Résultat d'une recherche de mot, prêt à être affiché OU enregistré tel
/// quel dans un DictionaryEntry (voir dictionary_sheet.dart). Contrairement
/// à un dictionnaire classique, Gemini rédige directement la définition et
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

/// Cherche un mot (définition + synonymes, traduits dans la langue choisie
/// par l'utilisateur) via l'API Gemini — directement depuis le téléphone,
/// sans passer par notre backend (même logique que GoogleTtsDirectService :
/// le PC de l'utilisateur n'a plus besoin d'être allumé pour que l'app
/// fonctionne).
class DictionaryService {
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent';

  static const _cacheBoxName = 'dictionary_cache';
  static const _cacheCap = 500;
  static const _cachePurgeCount = 100;

  static const Map<String, String> _languageNames = {
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'pt': 'Portuguese',
  };

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// Cache en mémoire — coût zéro pour re-chercher le même mot dans la même
  /// session (ex: l'utilisateur ferme puis rouvre la fiche par erreur).
  static final Map<String, DictionaryLookup> _memoryCache = {};

  /// « fr-FR » → « fr ». Nos locales internes (voix TTS) sont des BCP-47
  /// complets ; on ne garde que le code court pour le nom de langue envoyé
  /// à Gemini et pour les clés de cache/dédoublonnage.
  static String shortLang(String locale) => locale.split('-').first.toLowerCase();

  /// Déduit la langue du livre depuis le nom de voix choisi pour ce livre.
  ///
  /// ⚠️ Utilise firstMatch (cherche N'IMPORTE OÙ dans la chaîne), PAS
  /// shortLang/split('-').first : les voix locales s'appellent
  /// « local-en-US-f1 », dont le premier segment est « local » et non
  /// « en ».
  static String langFromVoiceName(String voiceName) {
    final m = RegExp(r'([a-z]{2})-([A-Z]{2})').firstMatch(voiceName);
    return m?.group(1) ?? 'en';
  }

  /// Cherche [word] (langue [sourceLang], code court) et rédige le résultat
  /// en [targetLang] (code court). Résultat mis en cache (mémoire + Hive)
  /// pour que les recherches suivantes du même mot soient instantanées et
  /// fonctionnent hors-ligne.
  Future<DictionaryLookup> lookup({
    required String word,
    required String sourceLang,
    required String targetLang,
  }) async {
    final wordLower = word.toLowerCase();
    final cacheKey = '$sourceLang|$targetLang|$wordLower';

    final cached = _memoryCache[cacheKey];
    if (cached != null) return cached;

    final cacheBox = Hive.box(_cacheBoxName);
    final cachedRaw = cacheBox.get(cacheKey);
    if (cachedRaw != null) {
      final lookup = DictionaryLookup.fromJson(cachedRaw as Map);
      _memoryCache[cacheKey] = lookup;
      return lookup;
    }

    final result = await _fetchFromGemini(word: word, sourceLang: sourceLang, targetLang: targetLang);

    _memoryCache[cacheKey] = result;
    // Écrit dans le cache à CHAQUE recherche, indépendamment du bouton
    // "Enregistrer" — ce sont deux choses distinctes : le cache accélère
    // toute re-consultation (et évite de repayer/re-générer), l'enregistrement
    // construit la liste de vocabulaire volontaire de l'utilisateur.
    await cacheBox.put(cacheKey, result.toJson());
    await _purgeOldCacheEntriesIfNeeded(cacheBox);
    return result;
  }

  Future<DictionaryLookup> _fetchFromGemini({
    required String word,
    required String sourceLang,
    required String targetLang,
  }) async {
    final sourceName = _languageNames[sourceLang] ?? sourceLang;
    final targetName = _languageNames[targetLang] ?? targetLang;

    final prompt = sourceLang == targetLang
        ? 'Define the $sourceName word "$word". Give its part of speech, '
            'a clear definition, an example sentence using it, and up to 4 synonyms, '
            'all in $targetName.'
        : 'Define the $sourceName word "$word" for a $targetName speaker learning '
            '$sourceName. Give: its direct translation, its part of speech, a definition, '
            'and up to 4 synonyms — all written in $targetName — plus an example sentence '
            'in $sourceName showing the word used naturally.';

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ],
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'object',
          'properties': {
            'translatedWord': {'type': 'string'},
            'partOfSpeech': {'type': 'string'},
            'definition': {'type': 'string'},
            'example': {'type': 'string'},
            'synonyms': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['translatedWord', 'partOfSpeech', 'definition', 'synonyms'],
        },
        // Une définition de mot n'a besoin d'aucun raisonnement — sans ça,
        // Gemini dépense par défaut plusieurs centaines de tokens de
        // "réflexion" interne (facturés, et qui ralentissent la réponse)
        // pour une tâche qui n'en demande aucune.
        'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
      },
    };

    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _endpoint,
          queryParameters: {'key': Secrets.geminiApiKey},
          data: body,
        );
        final text = response.data!['candidates'][0]['content']['parts'][0]['text'] as String;
        final json = jsonDecode(text) as Map<String, dynamic>;
        return DictionaryLookup(
          word: word,
          translatedWord: (json['translatedWord'] as String?) ?? word,
          partOfSpeech: (json['partOfSpeech'] as String?) ?? '',
          definition: (json['definition'] as String?) ?? '',
          example: (json['example'] as String?) ?? '',
          synonyms: ((json['synonyms'] as List?) ?? const []).cast<String>(),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        // 429 = quota épuisé (par minute ou par jour selon le palier) — le
        // ré-essayer tout de suite avec un court délai ne fait qu'aggraver
        // l'épuisement du quota au lieu de le laisser se libérer. On
        // n'insiste qu'en cas de vrai pépin serveur transitoire (5xx).
        final isRetryable = status != null && status >= 500;
        if (isRetryable && attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        if (status == 429) {
          throw DictionaryNetworkException('Quota Gemini temporairement épuisé — réessayez dans un instant');
        }
        throw DictionaryNetworkException(e.message ?? 'Gemini injoignable');
      } on FormatException {
        // Gemini n'a, dans de très rares cas, pas respecté le schéma JSON
        // demandé — pas la peine de retenter avec les mêmes paramètres.
        throw DictionaryNetworkException('Réponse inattendue du service');
      } catch (e) {
        // Gemini a répondu, mais dans une forme qu'on ne sait pas
        // interpréter (structure JSON inattendue) — pas la peine de
        // retenter avec les mêmes paramètres.
        throw DictionaryNetworkException('Erreur inattendue : $e');
      }
    }
    throw DictionaryNetworkException('Gemini injoignable après plusieurs tentatives');
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
