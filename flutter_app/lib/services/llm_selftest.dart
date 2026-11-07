import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_llm_service.dart';
import 'offline_dictionary_service.dart';
import 'sherpa_tts_service.dart';
import 'translation_service.dart';

/// Auto-test de l'IA locale, pour mesurer qualité et vitesse sur le vrai
/// téléphone sans passer par l'interface. Ne fait RIEN sauf en build debug
/// ET si le fichier `<support>/llm/selftest` existe (déposé via adb). Son
/// contenu optionnel `threads=N` force le nombre de threads. Le fichier est
/// supprimé dès la lecture : un seul passage par dépôt.
Future<void> runLlmSelfTestIfRequested() async {
  if (!kDebugMode) return;
  final support = await getApplicationSupportDirectory();
  final trigger = File('${support.path}/llm/selftest');
  if (!await trigger.exists()) return;
  final cfg = await trigger.readAsString();
  await trigger.delete();
  final t = RegExp(r'threads=(\d+)').firstMatch(cfg);
  if (t != null) LocalLlmService.threads = int.parse(t.group(1)!);

  final llm = LocalLlmService.instance;
  void log(String s) => debugPrint('[LLM-TEST] $s');

  if (cfg.contains('mlkit')) {
    final tr = TranslationService();
    final sw = Stopwatch()..start();
    await TranslationService.prepareLive('pt', 'fr');
    log('ML Kit modèles prêts : ${sw.elapsedMilliseconds} ms');
    for (final s in [
      'A casa no bosque estava vazia há muitos anos.',
      'Todas as noites uma luz acendia-se na janela do sótão.',
    ]) {
      final t = Stopwatch()..start();
      final out = await tr.translateLive(text: s, sourceLang: 'pt', targetLang: 'fr');
      log('ML Kit ${t.elapsedMilliseconds} ms : "$out"');
    }
    if (cfg.contains('only')) return;
  }
  if (cfg.contains('tts')) {
    final tmp = await getTemporaryDirectory();
    final tts = SherpaTtsService.instance;
    const samples = {
      'sherpa-kokoro-af_heart':
          'She had a way of making every room feel smaller, as if the walls leaned in to listen.',
      'sherpa-fr-siwis':
          "Il n'avait jamais su dire au revoir ; alors, ce matin-là, il partit sans un mot.",
      'sherpa-kokoro-pf_dora':
          'A casa no bosque estava vazia há muitos anos, mas todas as noites uma luz acendia-se.',
      'sherpa-pt-dii':
          'A casa no bosque estava vazia há muitos anos, mas todas as noites uma luz acendia-se.',
    };
    for (final th in [4, 6]) {
      SherpaTtsService.threads = th;
      for (final e in samples.entries) {
        for (final sp in [1.0, 1.5]) {
          for (var run = 0; run < 2; run++) {
            final sw = Stopwatch()..start();
            final r = await tts.synthesizeToFile(
                text: e.value, voiceName: e.key, outPath: '${tmp.path}/selftest.wav', speed: sp);
            final ms = sw.elapsedMilliseconds;
            // 1er passage = chargement du modèle inclus ; le 2e est le vrai débit.
            if (run == 1) {
              log('TTS ${e.key} threads=$th vitesse=$sp : ${r.duration.toStringAsFixed(1)} s '
                  'd\'audio en $ms ms → ${(r.duration * 1000 / ms).toStringAsFixed(1)}× temps réel');
            }
          }
        }
      }
    }
    SherpaTtsService.threads = 4;
    if (cfg.contains('only')) return;
  }
  if (cfg.contains('dict')) {
    final cases = [
      ('fr', 'en', 'regardait', 'Le vieil homme regardait la mer depuis des heures, sans rien dire.'),
      ('pt', 'fr', 'sótão', 'Todas as noites uma luz acendia-se na janela do sótão.'),
      ('en', 'fr', 'bank', 'They sat on the bank of the river and watched the boats.'),
      ('fr', 'fr', 'éphémère', 'Leur bonheur fut éphémère, comme un été trop court.'),
    ];
    for (final (src, tgt, word, ctx) in cases) {
      var sw = Stopwatch()..start();
      final o = await OfflineDictionaryService.instance
          .lookup(word: word, sourceLang: src, targetLang: tgt);
      log('BASE $word ($src→$tgt) : ${sw.elapsedMilliseconds} ms, déf en ${o?.definitionLang}, '
          'forme de ${o?.formOf}, ${o?.entries.length} entrées, 1er sens '
          '"${o?.entries.firstOrNull?.senses.firstOrNull?.gloss}"');
      sw = Stopwatch()..start();
      int? firstMs;
      LocalContextMeaning? last;
      await for (final m in llm.explainInContext(
          word: word,
          sentence: ctx,
          sourceLang: src,
          targetLang: tgt,
          senses: [for (final e in o?.entries ?? const <OfflineEntry>[]) ...e.senses.map((s) => s.gloss)])) {
        if (firstMs == null && m.meaning.isNotEmpty) firstMs = sw.elapsedMilliseconds;
        last = m;
      }
      log('   CONTEXTE : sens visible ${firstMs}ms, fini ${sw.elapsedMilliseconds}ms : '
          'trad="${last?.translation}" sens="${last?.meaning}"');
    }
    if (cfg.contains('only')) return;
  }
  log('début (threads=${LocalLlmService.threads})');

  var sw = Stopwatch()..start();
  await llm.warmUp();
  log('préchauffage : ${sw.elapsedMilliseconds} ms');

  final defs = [
    ('fr', 'en', 'regardait', 'Le vieil homme regardait la mer depuis des heures, sans rien dire.'),
    ('pt', 'fr', 'sótão', 'Todas as noites uma luz acendia-se na janela do sótão.'),
    ('en', 'fr', 'bank', 'They sat on the bank of the river and watched the boats.'),
    ('fr', 'fr', 'éphémère', 'Leur bonheur fut éphémère, comme un été trop court.'),
  ];
  for (final (src, tgt, word, ctx) in defs) {
    sw = Stopwatch()..start();
    int? firstMs;
    LocalDefinition? last;
    await for (final d in llm.define(
        word: word, sourceLang: src, targetLang: tgt, contextSentence: ctx)) {
      if (firstMs == null && d.hasContent) firstMs = sw.elapsedMilliseconds;
      last = d;
    }
    log('DEFINE $word ($src→$tgt) : 1er texte ${firstMs}ms, total ${sw.elapsedMilliseconds}ms');
    log('   trad="${last?.translatedWord}" type="${last?.partOfSpeech}"');
    log('   déf="${last?.definition}"');
    log('   ex="${last?.example}" syn=${last?.synonyms}');
  }

  final trs = [
    ('pt', 'fr', 'A casa no bosque estava vazia há muitos anos, mas todas as noites uma luz acendia-se na janela do sótão.'),
    ('fr', 'en', "Il n'avait jamais su dire au revoir ; alors, ce matin-là, il partit sans un mot, en laissant la porte entrouverte."),
    ('en', 'pt', 'She had a way of making every room feel smaller, as if the walls leaned in to listen.'),
  ];
  for (final (src, tgt, text) in trs) {
    sw = Stopwatch()..start();
    int? firstMs;
    var out = '';
    await for (final s in llm.translate(text: text, sourceLang: src, targetLang: tgt)) {
      firstMs ??= sw.elapsedMilliseconds;
      out = s;
    }
    log('TRANSLATE ($src→$tgt) : 1er mot ${firstMs}ms, total ${sw.elapsedMilliseconds}ms');
    log('   "$out"');
  }
  log('fin');
}
