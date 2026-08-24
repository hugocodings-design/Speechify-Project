import 'dart:ui';

/// État d'une page en cours de scan.
///
/// Volontairement hors de Hive : une session de scan est transitoire. Les
/// images vivent dans le dossier temporaire de la session, et seul le résultat
/// final (un [Ebook] et ses [Chapter]) est persisté.
enum ScanStatus { captured, processing, done, failed }

class ScanPage {
  ScanPage({
    required this.id,
    required this.sourcePath,
    List<Offset>? quad,
  }) : quad = quad ?? defaultQuad();

  final String id;

  /// Image de travail, toujours dans l'orientation d'affichage (EXIF déjà
  /// appliqué, rotations manuelles réécrites sur le disque). C'est le
  /// référentiel unique des coordonnées de [quad].
  String sourcePath;

  /// Image redressée + contrastée, celle qui part à l'OCR.
  String? rectifiedPath;

  /// Les 4 coins, **normalisés 0..1**, dans l'ordre TL, TR, BR, BL.
  /// Normalisés pour survivre à l'écart entre la taille d'affichage et la
  /// résolution réelle du JPEG.
  List<Offset> quad;

  String? recognizedText;
  ScanStatus status = ScanStatus.captured;
  String? error;

  int get wordCount {
    final t = recognizedText?.trim() ?? '';
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }

  bool get hasText => wordCount > 0;

  /// Rectangle inséré à 90 % — le repli quand rien n'est détecté.
  static List<Offset> defaultQuad() => const [
        Offset(0.05, 0.05),
        Offset(0.95, 0.05),
        Offset(0.95, 0.95),
        Offset(0.05, 0.95),
      ];

  static List<Offset> quadFromRect(Rect r) => [
        Offset(r.left, r.top),
        Offset(r.right, r.top),
        Offset(r.right, r.bottom),
        Offset(r.left, r.bottom),
      ];

  List<double> get flatQuad =>
      [for (final p in quad) ...[p.dx, p.dy]];
}
