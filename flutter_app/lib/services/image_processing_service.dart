import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Traitement d'image pur Dart (`package:image`), exécuté dans un [Isolate]
/// pour ne jamais bloquer le thread UI : décoder un JPEG 12 Mpx prend
/// facilement une seconde.
class ImageProcessingService {
  /// Au-delà, ML Kit ne gagne plus rien et la latence explose.
  static const int _maxEdge = 2200;

  /// Résolution de travail après capture (on garde de la marge pour que le
  /// redressement d'un cadrage serré reste net).
  static const int _maxCaptureEdge = 2600;

  static Directory? _sessionDir;

  /// Dossier temporaire de la session courante. Recréé au premier appel.
  static Future<Directory> sessionDir() async {
    final existing = _sessionDir;
    if (existing != null && existing.existsSync()) return existing;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(
      '${tmp.path}/scan_session_${DateTime.now().millisecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    return _sessionDir = dir;
  }

  /// Supprime les images de la session. À appeler quand le livre est créé ou
  /// la session abandonnée.
  static Future<void> clearSession() async {
    final dir = _sessionDir;
    _sessionDir = null;
    if (dir != null && dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Un fichier encore ouvert par le décodeur d'images ne doit pas
        // faire échouer la création du livre.
      }
    }
  }

  static Future<String> _newPath(String suffix) async {
    final dir = await sessionDir();
    return '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$suffix.jpg';
  }

  /// Normalise une image fraîchement capturée ou importée : applique
  /// l'orientation EXIF (sans quoi les photos portrait arrivent couchées et
  /// l'OCR échoue) et réduit la résolution.
  static Future<String> prepareSource(String srcPath) async {
    final destPath = await _newPath('src');
    return Isolate.run(() => _prepareSourceSync(srcPath, destPath));
  }

  /// Rotation de 90° dans le sens horaire, réécrite sur le disque.
  ///
  /// On matérialise la rotation plutôt que de la porter comme un état :
  /// l'image sur le disque est toujours dans l'orientation d'affichage, donc
  /// le quadrilatère n'a jamais besoin d'être transposé.
  static Future<String> rotate90(String srcPath) async {
    final destPath = await _newPath('rot');
    return Isolate.run(() => _rotate90Sync(srcPath, destPath));
  }

  /// Redresse la zone délimitée par les 4 coins normalisés puis prépare
  /// l'image pour l'OCR.
  ///
  /// [quad] : 8 doubles normalisés, ordre TL, TR, BR, BL.
  static Future<String> rectifyAndEnhance(
    String srcPath,
    List<double> quad,
  ) async {
    final destPath = await _newPath('rect');
    return Isolate.run(() => _rectifySync(srcPath, quad, destPath));
  }

  /// Dimensions en pixels, via le décodeur de Flutter (rapide, et il gère
  /// déjà l'EXIF comme le fera le widget `Image.file`).
  static Future<ui.Size> imageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = ui.Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  // ---------------------------------------------------------------------
  // Exécuté dans l'isolate — pas d'accès aux plugins, uniquement du Dart pur.
  // ---------------------------------------------------------------------

  static String _prepareSourceSync(String srcPath, String destPath) {
    var image = _decode(srcPath);
    image = img.bakeOrientation(image);
    image = _fit(image, _maxCaptureEdge);
    File(destPath).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return destPath;
  }

  static String _rotate90Sync(String srcPath, String destPath) {
    final image = img.copyRotate(_decode(srcPath), angle: 90);
    File(destPath).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return destPath;
  }

  static String _rectifySync(
    String srcPath,
    List<double> quad,
    String destPath,
  ) {
    var src = _decode(srcPath);
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    img.Point at(int i) =>
        img.Point(quad[i * 2] * w, quad[i * 2 + 1] * h);

    final tl = at(0), tr = at(1), br = at(2), bl = at(3);

    double dist(img.Point a, img.Point b) {
      final dx = (a.x - b.x).toDouble();
      final dy = (a.y - b.y).toDouble();
      return math.sqrt(dx * dx + dy * dy);
    }

    // Le ratio cible vient du quadrilatère lui-même, pas de la photo : une
    // page prise en biais retrouve ainsi ses vraies proportions.
    var outW = math.max(dist(tl, tr), dist(bl, br));
    var outH = math.max(dist(tl, bl), dist(tr, br));

    // Cap à la résolution finale *avant* le redressement plutôt qu'après :
    // `copyRectify` écrit alors directement le résultat à sa taille
    // définitive en une seule passe d'interpolation, sans calculer puis
    // jeter des pixels qu'un second redimensionnement aurait de toute façon
    // supprimés. Résultat identique pour l'OCR (même résolution finale),
    // simplement moins de travail — et un peu plus net, une résampling
    // valant mieux que deux qui s'enchaînent.
    final longest = math.max(outW, outH);
    if (longest > _maxEdge) {
      final scale = _maxEdge / longest;
      outW *= scale;
      outH *= scale;
    }
    final outWi = outW.round().clamp(32, _maxEdge);
    final outHi = outH.round().clamp(32, _maxEdge);

    // Nuances de gris avant le redressement, pas après : ML Kit ne se sert
    // que de la luminance, donc `copyRectify` interpole 3x moins de données
    // (1 canal au lieu de 3) pour un résultat identique côté OCR.
    src = img.grayscale(src);

    var out = img.copyRectify(
      src,
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
      interpolation: img.Interpolation.cubic,
      toImage: img.Image(width: outWi, height: outHi, numChannels: 1),
    );

    // Prétraitement volontairement léger : ML Kit lit très bien un gris
    // contrasté, tandis qu'une binarisation dure détruit les caractères fins.
    out = img.adjustColor(out, contrast: 1.25);
    out = img.normalize(out, min: 0, max: 255);

    File(destPath).writeAsBytesSync(img.encodeJpg(out, quality: 90));
    return destPath;
  }

  static img.Image _decode(String path) {
    final image = img.decodeImage(File(path).readAsBytesSync());
    if (image == null) {
      throw const FormatException('Image illisible ou format non supporté');
    }
    return image;
  }

  static img.Image _fit(img.Image image, int maxEdge) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= maxEdge) return image;
    final scale = maxEdge / longest;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
