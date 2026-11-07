import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_llm_service.dart';

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
