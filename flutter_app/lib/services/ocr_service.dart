import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reconnaissance de texte 100 % sur l'appareil (ML Kit, modèle latin
/// embarqué). Aucun appel réseau, donc le scan fonctionne hors-ligne et sans
/// que le backend tourne.
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get _r =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Texte reconnu, blocs séparés par une ligne vide pour préserver la
  /// structure en paragraphes (que [ScanToBookService] exploite ensuite).
  Future<String> recognizeText(String imagePath) async {
    final result = await _r.processImage(InputImage.fromFilePath(imagePath));
    return result.blocks
        .map((b) => b.lines.map((l) => l.text).join('\n'))
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
  }

  /// Zone occupée par le texte, en coordonnées **normalisées 0..1**.
  ///
  /// Plutôt qu'une détection de contours en Dart pur (fragile et lente), on
  /// demande à ML Kit où il voit du texte et on initialise le quadrilatère
  /// sur l'union de ses blocs. C'est aussi ce que l'utilisateur veut cadrer :
  /// le bloc de texte, pas le bord de la feuille.
  Future<Rect?> detectTextBounds(String imagePath, Size imageSize) async {
    if (imageSize.width <= 0 || imageSize.height <= 0) return null;

    final result = await _r.processImage(InputImage.fromFilePath(imagePath));
    Rect? union;
    for (final block in result.blocks) {
      union = union == null
          ? block.boundingBox
          : union.expandToInclude(block.boundingBox);
    }
    if (union == null || union.isEmpty) return null;

    const margin = 0.02; // un peu d'air, ML Kit colle aux glyphes
    final normalized = Rect.fromLTRB(
      union.left / imageSize.width - margin,
      union.top / imageSize.height - margin,
      union.right / imageSize.width + margin,
      union.bottom / imageSize.height + margin,
    );

    return Rect.fromLTRB(
      normalized.left.clamp(0.0, 1.0),
      normalized.top.clamp(0.0, 1.0),
      normalized.right.clamp(0.0, 1.0),
      normalized.bottom.clamp(0.0, 1.0),
    );
  }

  /// Le recognizer natif doit être fermé, sinon fuite mémoire côté Android.
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
