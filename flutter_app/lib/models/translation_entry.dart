import 'package:hive/hive.dart';

part 'translation_entry.g.dart';

/// Un mot OU une phrase traduit manuellement par l'utilisateur (bouton
/// « Traduire » dans la barre de sélection du lecteur), et enregistré pour
/// consultation ultérieure — distinct de translation_cache (box interne, non
/// affichée, qui mémorise TOUTE traduction faite en direct pendant la
/// lecture pour ne pas re-payer/re-demander la même phrase).
///
/// [ebookId] est TOUJOURS rempli : la liste « globale » n'est pas une box
/// séparée, c'est simplement la même box lue sans filtre — exactement le
/// schéma déjà utilisé par les annotations et le dictionnaire (voir
/// annotations_screen.dart).
@HiveType(typeId: 6) // 0=Ebook 1=Chapter 2=AudioChunk 3=Folder 4=Annotation 5=DictionaryEntry
class TranslationEntry {
  @HiveField(0)
  final String id;

  /// Texte original tel que sélectionné dans le livre — un mot ou une
  /// phrase entière.
  @HiveField(1)
  final String text;

  @HiveField(2)
  final String translatedText;

  @HiveField(3)
  final String ebookId;

  /// Vide si on n'a pas pu déterminer le chapitre.
  @HiveField(4)
  final String chapterId;

  /// Index du paragraphe au sein du chapitre — permet de sauter directement
  /// au passage exact dans le livre depuis l'onglet Traductions (voir
  /// _findGlobalIndexForChapterParagraph dans reader_screen.dart), -1 si
  /// inconnu (ex: chapterId vide).
  @HiveField(8)
  final int paragraphIndexInChapter;

  /// Langue du texte original (code court ISO), déduite de la voix choisie
  /// pour ce livre — voir DictionaryService.langFromVoiceName.
  @HiveField(5)
  final String sourceLang;

  /// Langue de la traduction au moment de l'enregistrement. Conservée par
  /// entrée (et pas seulement lue depuis les réglages) pour que changer la
  /// langue de traduction plus tard n'invalide pas les fiches déjà
  /// enregistrées.
  @HiveField(6)
  final String targetLang;

  @HiveField(7)
  final DateTime createdAt;

  TranslationEntry({
    required this.id,
    required this.text,
    required this.translatedText,
    required this.ebookId,
    required this.chapterId,
    this.paragraphIndexInChapter = -1,
    required this.sourceLang,
    required this.targetLang,
    required this.createdAt,
  });
}
