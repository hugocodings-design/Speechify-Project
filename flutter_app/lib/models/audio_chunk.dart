import 'package:hive/hive.dart';

part 'audio_chunk.g.dart';

@HiveType(typeId: 2)
class AudioChunk {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String chapterId;

  @HiveField(2)
  final String text;

  @HiveField(3)
  String? audioUrl;

  @HiveField(4)
  String status; // "pending", "synthesizing", "ready", "failed"

  @HiveField(5)
  int playbackPosition = 0;

  @HiveField(6)
  final DateTime createdAt;

  AudioChunk({
    required this.id,
    required this.chapterId,
    required this.text,
    required this.status,
    this.audioUrl,
    this.playbackPosition = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isReady => status == "ready" && audioUrl != null;
  bool get isPending => status == "pending";
  bool get isSynthesizing => status == "synthesizing";
  bool get isFailed => status == "failed";
}
