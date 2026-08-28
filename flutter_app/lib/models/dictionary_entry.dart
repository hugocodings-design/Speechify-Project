import 'package:hive/hive.dart';

part 'dictionary_entry.g.dart';

/// Un mot enregistré par l'utilisateur depuis le dictionnaire du lecteur.
/// La définition et les synonymes sont rédigés par Gemini directement dans
/// la langue cible choisie par l'utilisateur (voir DictionaryService) — pas
/// d'étape de traduction séparée.
///
/// TOUT le contenu affichable est recopié ici (traduction, définition,
/// exemple, synonymes) plutôt que d'être re-généré à l'ouverture de la
/// liste : la liste de vocabulaire doit rester consultable hors-ligne.
///
/// [ebookId] est TOUJOURS rempli : la liste « globale » n'est pas une box
/// séparée, c'est simplement la même box lue sans filtre — exactement le
/// schéma déjà utilisé par les annotations (voir annotations_screen.dart),
/// ce qui évite d'avoir à synchroniser deux stockages.
@HiveType(typeId: 5) // 0=Ebook 1=Chapter 2=AudioChunk 3=Folder 4=Annotation
class DictionaryEntry {
  @HiveField(0)
  final String id;

  /// Le mot tel qu'il apparaît dans le livre (casse d'origine conservée).
  @HiveField(1)
  final String word;

  /// Le mot en minuscules — clé de dédoublonnage, pour ne pas enregistrer
  /// deux fois « Subtle » et « subtle ».
  @HiveField(2)
  final String wordLower;

  @HiveField(3)
  final String ebookId;

  /// Vide si on n'a pas pu déterminer le chapitre (ex : fiche rouverte
  /// depuis la liste plutôt que depuis le texte).
  @HiveField(4)
  final String chapterId;

  /// Langue du mot (code court ISO : 'en', 'fr'…), déduite de la voix
  /// choisie pour ce livre — voir DictionaryService.langFromVoiceName.
  @HiveField(5)
  final String sourceLang;

  /// Langue dans laquelle Gemini a rédigé la définition au moment de la
  /// recherche. Conservée par entrée (et pas seulement lue depuis les
  /// réglages) pour que changer la langue du dictionnaire plus tard
  /// n'invalide pas les fiches déjà enregistrées.
  @HiveField(6)
  final String targetLang;

  @HiveField(7)
  final String translatedWord;

  /// Nature grammaticale, déjà dans la langue cible (Gemini la donne
  /// directement — pas de table de traduction locale nécessaire).
  @HiveField(8)
  final String partOfSpeech;

  @HiveField(9)
  final String definition;

  /// Phrase d'exemple, dans la langue DU MOT (utile pour reconnaître son
  /// usage naturel dans le livre).
  @HiveField(10)
  final String example;

  @HiveField(11)
  final List<String> synonyms;

  @HiveField(12)
  final DateTime createdAt;

  DictionaryEntry({
    required this.id,
    required this.word,
    required this.wordLower,
    required this.ebookId,
    required this.chapterId,
    required this.sourceLang,
    required this.targetLang,
    required this.translatedWord,
    required this.partOfSpeech,
    required this.definition,
    required this.example,
    required this.synonyms,
    required this.createdAt,
  });
}
