import 'package:hive/hive.dart';

part 'annotation.g.dart';

/// Un passage surligné et sauvegardé par l'utilisateur.
///
/// [startOffset]/[endOffset] sont dans l'espace de caractères *normalisé* du
/// paragraphe tel que reconstruit par `_buildParagraphWidget` dans
/// reader_screen.dart (ancres invisibles + texte de phrase + espace), PAS
/// des offsets dans `Chapter.textContent` brut — ce sont deux espaces
/// différents (le second est aplati/retrimé par `_buildFlatList`, avec des
/// caractères d'ancre en plus). Utiliser le mauvais espace décale le
/// surlignage silencieusement.
@HiveType(typeId: 4)
class Annotation {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String ebookId;

  @HiveField(2)
  final String chapterId;

  @HiveField(3)
  final int paragraphIndexInChapter;

  @HiveField(4)
  final int startOffset;

  @HiveField(5)
  final int endOffset;

  @HiveField(6)
  final String selectedText;

  @HiveField(7)
  final DateTime createdAt;

  /// Réservé pour une note libre future (dictionnaire/traduction) — vide par
  /// défaut aujourd'hui, pour éviter une migration de schéma plus tard.
  @HiveField(8)
  final String note;

  Annotation({
    required this.id,
    required this.ebookId,
    required this.chapterId,
    required this.paragraphIndexInChapter,
    required this.startOffset,
    required this.endOffset,
    required this.selectedText,
    required this.createdAt,
    this.note = '',
  });
}
