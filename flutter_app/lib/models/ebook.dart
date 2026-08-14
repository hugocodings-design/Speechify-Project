import 'package:hive/hive.dart';
import 'chapter.dart';

part 'ebook.g.dart';

@HiveType(typeId: 0)
class Ebook {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final List<Chapter> chapters;

  @HiveField(3)
  int lastReadPosition = 0;

  @HiveField(4)
  String selectedVoiceName = "en-US-Neural2-C";

  @HiveField(5)
  final DateTime uploadedAt;

  @HiveField(6)
  final String fileFormat; // "pdf" or "epub"

  Ebook({
    required this.id,
    required this.title,
    required this.chapters,
    required this.uploadedAt,
    required this.fileFormat,
    this.lastReadPosition = 0,
    this.selectedVoiceName = "en-US-Neural2-C",
  });

  int get totalWords => chapters.fold(0, (sum, ch) => sum + ch.wordCount);

  int get totalChunks =>
      chapters.fold(0, (sum, ch) => sum + (ch.textContent.length ~/ 200));
}
