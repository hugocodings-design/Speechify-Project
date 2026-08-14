// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_chunk.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudioChunkAdapter extends TypeAdapter<AudioChunk> {
  @override
  final int typeId = 2;

  @override
  AudioChunk read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioChunk(
      id: fields[0] as String,
      chapterId: fields[1] as String,
      text: fields[2] as String,
      status: fields[4] as String,
      audioUrl: fields[3] as String?,
      playbackPosition: fields[5] as int,
      createdAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, AudioChunk obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.chapterId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.audioUrl)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.playbackPosition)
      ..writeByte(6)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioChunkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
