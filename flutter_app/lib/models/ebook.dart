import 'package:hive/hive.dart';
import 'chapter.dart';

part 'ebook.g.dart';

@HiveType(typeId: 0)
class Ebook {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  final List<Chapter> chapters;

  @HiveField(3)
  int lastReadPosition = 0;

  @HiveField(4)
  String selectedVoiceName = "en-US-Neural2-D";

  @HiveField(5)
  final DateTime uploadedAt;

  @HiveField(6)
  final String fileFormat; // "pdf" or "epub"

  @HiveField(7)
  String? folderId; // null = dossier racine

  @HiveField(8)
  int totalSentences = 0; // nombre total de phrases du livre

  @HiveField(9)
  String? coverImagePath; // chemin local vers l'image de couverture extraite

  Ebook({
    required this.id,
    required this.title,
    required this.chapters,
    required this.uploadedAt,
    required this.fileFormat,
    this.lastReadPosition = 0,
    this.selectedVoiceName = "en-US-Neural2-D",
    this.folderId,
    this.totalSentences = 0,
    this.coverImagePath,
  });

  int get totalWords => chapters.fold(0, (sum, ch) => sum + ch.wordCount);

  int get totalChunks =>
      chapters.fold(0, (sum, ch) => sum + (ch.textContent.length ~/ 200));
}
