import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'word_aligner.dart';

enum SherpaModelKind { piper, kokoro }

/// Un modèle de synthèse vocale installé dans `<support>/tts_models/<folder>`.
class SherpaModelSpec {
  const SherpaModelSpec({
    required this.id,
    required this.folder,
    required this.kind,
    required this.modelFile,
    required this.label,
  });

  final String id;
  final String folder;
  final SherpaModelKind kind;
  final String modelFile;
  final String label;
}

/// Une voix proposée dans le sélecteur. Un même modèle peut en porter
/// plusieurs (Kokoro : des dizaines ; Piper « upmc » : deux).
class SherpaVoice {
  const SherpaVoice({
    required this.name,
    required this.displayName,
    required this.languageCode,
    required this.modelId,
    this.sid = 0,
  });

  final String name;
  final String displayName;
  final String languageCode;
  final String modelId;
  final int sid;
}

/// Voix IA locales, gratuites : synthèse neuronale faite sur le téléphone
/// (sherpa-onnx). Aucune clé API, aucun réseau — seulement des fichiers de
/// modèle présents sur l'appareil.
class SherpaTtsService {
  SherpaTtsService._();
  static final SherpaTtsService instance = SherpaTtsService._();

  static const String voicePrefix = 'sherpa-';
  static bool isSherpaVoice(String voiceName) =>
      voiceName.startsWith(voicePrefix);

  static const List<SherpaModelSpec> models = [
    SherpaModelSpec(
      id: 'fr-siwis',
      folder: 'vits-piper-fr_FR-siwis-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'fr_FR-siwis-medium.onnx',
      label: 'Piper · Siwis (FR)',
    ),
    SherpaModelSpec(
      id: 'fr-tom',
      folder: 'vits-piper-fr_FR-tom-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'fr_FR-tom-medium.onnx',
      label: 'Piper · Tom (FR)',
    ),
    SherpaModelSpec(
      id: 'fr-upmc',
      folder: 'vits-piper-fr_FR-upmc-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'fr_FR-upmc-medium.onnx',
      label: 'Piper · UPMC (FR)',
    ),
    SherpaModelSpec(
      id: 'fr-miro',
      folder: 'vits-piper-fr_FR-miro-high',
      kind: SherpaModelKind.piper,
      modelFile: 'fr_FR-miro-high.onnx',
      label: 'Piper · Miro (FR)',
    ),
    SherpaModelSpec(
      id: 'pt-tugao',
      folder: 'vits-piper-pt_PT-tugao-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'pt_PT-tugao-medium.onnx',
      label: 'Piper · Tugão (PT)',
    ),
    SherpaModelSpec(
      id: 'pt-miro',
      folder: 'vits-piper-pt_PT-miro-high',
      kind: SherpaModelKind.piper,
      modelFile: 'pt_PT-miro-high.onnx',
      label: 'Piper · Miro (PT)',
    ),
    SherpaModelSpec(
      id: 'pt-dii',
      folder: 'vits-piper-pt_PT-dii-high',
      kind: SherpaModelKind.piper,
      modelFile: 'pt_PT-dii-high.onnx',
      label: 'Piper · Dii (PT)',
    ),
    SherpaModelSpec(
      id: 'pt-faber',
      folder: 'vits-piper-pt_BR-faber-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'pt_BR-faber-medium.onnx',
      label: 'Piper · Faber (BR)',
    ),
    SherpaModelSpec(
      id: 'pt-jeff',
      folder: 'vits-piper-pt_BR-jeff-medium',
      kind: SherpaModelKind.piper,
      modelFile: 'pt_BR-jeff-medium.onnx',
      label: 'Piper · Jeff (BR)',
    ),
    SherpaModelSpec(
      id: 'kokoro',
      folder: 'kokoro-int8-multi-lang-v1_0',
      kind: SherpaModelKind.kokoro,
      modelFile: 'model.int8.onnx',
      label: 'Kokoro',
    ),
  ];

  static const List<SherpaVoice> voices = [
    SherpaVoice(
      name: 'sherpa-fr-siwis',
      displayName: 'Siwis',
      languageCode: 'fr-FR',
      modelId: 'fr-siwis',
    ),
    SherpaVoice(
      name: 'sherpa-fr-tom',
      displayName: 'Tom',
      languageCode: 'fr-FR',
      modelId: 'fr-tom',
    ),
    SherpaVoice(
      name: 'sherpa-fr-upmc-jessica',
      displayName: 'Jessica',
      languageCode: 'fr-FR',
      modelId: 'fr-upmc',
      sid: 0,
    ),
    SherpaVoice(
      name: 'sherpa-fr-upmc-pierre',
      displayName: 'Pierre',
      languageCode: 'fr-FR',
      modelId: 'fr-upmc',
      sid: 1,
    ),
    SherpaVoice(
      name: 'sherpa-fr-miro',
      displayName: 'Miro',
      languageCode: 'fr-FR',
      modelId: 'fr-miro',
    ),
    SherpaVoice(
      name: 'sherpa-pt-tugao',
      displayName: 'Tugão',
      languageCode: 'pt-PT',
      modelId: 'pt-tugao',
    ),
    SherpaVoice(
      name: 'sherpa-pt-miro',
      displayName: 'Miro',
      languageCode: 'pt-PT',
      modelId: 'pt-miro',
    ),
    SherpaVoice(
      name: 'sherpa-pt-dii',
      displayName: 'Dii',
      languageCode: 'pt-PT',
      modelId: 'pt-dii',
    ),
    SherpaVoice(
      name: 'sherpa-pt-faber',
      displayName: 'Faber',
      languageCode: 'pt-BR',
      modelId: 'pt-faber',
    ),
    SherpaVoice(
      name: 'sherpa-pt-jeff',
      displayName: 'Jeff',
      languageCode: 'pt-BR',
      modelId: 'pt-jeff',
    ),
    // Kokoro : ordre des identifiants de voix du modèle multi-lang v1.0.
    SherpaVoice(
      name: 'sherpa-kokoro-af_heart',
      displayName: 'Heart',
      languageCode: 'en-US',
      modelId: 'kokoro',
      sid: 3,
    ),
    SherpaVoice(
      name: 'sherpa-kokoro-af_bella',
      displayName: 'Bella',
      languageCode: 'en-US',
      modelId: 'kokoro',
      sid: 2,
    ),
    SherpaVoice(
      name: 'sherpa-kokoro-am_michael',
      displayName: 'Michael',
      languageCode: 'en-US',
      modelId: 'kokoro',
      sid: 16,
    ),
    SherpaVoice(
      name: 'sherpa-kokoro-bf_emma',
      displayName: 'Emma',
      languageCode: 'en-GB',
      modelId: 'kokoro',
      sid: 21,
    ),
    SherpaVoice(
      name: 'sherpa-kokoro-bm_george',
      displayName: 'George',
      languageCode: 'en-GB',
      modelId: 'kokoro',
      sid: 26,
    ),
  ];

  static SherpaVoice? voiceByName(String name) {
    for (final v in voices) {
      if (v.name == name) return v;
    }
    return null;
  }

  static SherpaModelSpec modelById(String id) =>
      models.firstWhere((m) => m.id == id);

  Future<Directory> modelsRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/tts_models');
  }

  Future<String> _modelDir(SherpaModelSpec spec) async =>
      '${(await modelsRoot()).path}/${spec.folder}';

  Future<bool> isModelInstalled(String modelId) async {
    final spec = modelById(modelId);
    final dir = await _modelDir(spec);
    return File('$dir/${spec.modelFile}').exists();
  }

  /// Seules les voix dont le modèle est effectivement présent sur le
  /// téléphone sont proposées.
  Future<List<SherpaVoice>> installedVoices() async {
    final installed = <String, bool>{};
    final result = <SherpaVoice>[];
    for (final v in voices) {
      installed[v.modelId] ??= await isModelInstalled(v.modelId);
      if (installed[v.modelId]!) result.add(v);
    }
    return result;
  }

  // ── Synthèse (dans un isolate dédié : generate() est synchrone et lourd,
  //    sur le fil principal il ferait saccader l'écran et le surlignage) ────

  SendPort? _worker;
  Future<SendPort>? _workerStarting;

  Future<SendPort> _ensureWorker() {
    final existing = _worker;
    if (existing != null) return Future.value(existing);
    return _workerStarting ??= _startWorker();
  }

  Future<SendPort> _startWorker() async {
    final ready = ReceivePort();
    await Isolate.spawn(_workerMain, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    _worker = port;
    return port;
  }

  /// Synthétise [text] avec la voix [voiceName] et écrit un WAV dans [outPath].
  /// Renvoie l'instant de début (en secondes) de chaque mot de [text]
  /// (découpé sur les espaces), aligné sur l'audio réellement produit.
  Future<List<double>> synthesizeToFile({
    required String text,
    required String voiceName,
    required String outPath,
  }) async {
    final voice = voiceByName(voiceName);
    if (voice == null) {
      throw Exception('Voix IA locale inconnue : $voiceName');
    }
    final spec = modelById(voice.modelId);
    final dir = await _modelDir(spec);
    if (!await File('$dir/${spec.modelFile}').exists()) {
      throw Exception('Modèle ${spec.label} non installé sur ce téléphone');
    }

    final worker = await _ensureWorker();
    final reply = ReceivePort();
    worker.send({
      'reply': reply.sendPort,
      'key': spec.id,
      'kind': spec.kind.name,
      'dir': dir,
      'modelFile': spec.modelFile,
      'text': text,
      'sid': voice.sid,
      'outPath': outPath,
    });
    final res = await reply.first as Map;
    reply.close();
    if (res['ok'] != true) {
      throw Exception(res['error'] ?? 'Échec de la synthèse locale');
    }
    return (res['times'] as List).cast<double>();
  }
}

// ── Isolate de synthèse ─────────────────────────────────────────────────────

void _workerMain(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);
  sherpa.initBindings();

  String? loadedKey;
  sherpa.OfflineTts? tts;

  inbox.listen((dynamic raw) {
    final msg = raw as Map;
    final reply = msg['reply'] as SendPort;
    try {
      final key = msg['key'] as String;
      if (key != loadedKey) {
        tts?.free();
        tts = null;
        loadedKey = null;
        tts = sherpa.OfflineTts(_buildConfig(msg));
        loadedKey = key;
      }

      final audio = tts!.generate(
        text: msg['text'] as String,
        sid: msg['sid'] as int,
        speed: 1.0,
      );
      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        throw Exception('Synthèse vide');
      }
      File(msg['outPath'] as String)
          .writeAsBytesSync(_wavBytes(audio.samples, audio.sampleRate));
      final times = alignWordsToAudio(
          msg['text'] as String, audio.samples, audio.sampleRate);
      reply.send({'ok': true, 'times': times});
    } catch (e) {
      reply.send({'ok': false, 'error': '$e'});
    }
  });
}

sherpa.OfflineTtsConfig _buildConfig(Map msg) {
  final dir = msg['dir'] as String;
  final modelFile = msg['modelFile'] as String;
  final isKokoro = msg['kind'] == SherpaModelKind.kokoro.name;

  final model = isKokoro
      ? sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: '$dir/$modelFile',
            voices: '$dir/voices.bin',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
            dictDir: '$dir/dict',
            lexicon: '$dir/lexicon-us-en.txt,$dir/lexicon-zh.txt',
          ),
          numThreads: 4,
        )
      : sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: '$dir/$modelFile',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
          ),
          numThreads: 4,
        );

  return sherpa.OfflineTtsConfig(model: model);
}

/// WAV PCM 16 bits mono — lisible tel quel par just_audio.
Uint8List _wavBytes(Float32List samples, int sampleRate) {
  final n = samples.length;
  final data = ByteData(44 + n * 2);
  void tag(int offset, String text) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}
