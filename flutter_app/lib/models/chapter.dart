import 'package:hive/hive.dart';

part 'chapter.g.dart';

@HiveType(typeId: 1)
class Chapter {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String textContent;

  @HiveField(3)
  final int wordCount;

  @HiveField(4)
  final int pageNumber;

  Chapter({
    required this.id,
    required this.title,
    required this.textContent,
    required this.wordCount,
    required this.pageNumber,
  });

  // Split text into chunks (~200 words each)
  List<String> get textChunks {
    final words = textContent.split(RegExp(r'\s+'));
    final chunks = <String>[];
    
    for (int i = 0; i < words.length; i += 200) {
      int end = i + 200;
      if (end > words.length) end = words.length;
      chunks.add(words.sublist(i, end).join(' '));
    }
    
    return chunks;
  }
}
