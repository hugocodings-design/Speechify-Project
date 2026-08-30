// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ebook.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EbookAdapter extends TypeAdapter<Ebook> {
  @override
  final int typeId = 0;

  @override
  Ebook read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Ebook(
      id: fields[0] as String,
      title: fields[1] as String,
      chapters: (fields[2] as List).cast<Chapter>(),
      uploadedAt: fields[5] as DateTime,
      fileFormat: fields[6] as String,
      lastReadPosition: fields[3] as int,
      selectedVoiceName: fields[4] as String,
      folderId: fields[7] as String?,
      totalSentences: fields[8] as int? ?? 0,
      coverImagePath: fields[9] as String?,
      lastOpenedAt: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Ebook obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.chapters)
      ..writeByte(3)
      ..write(obj.lastReadPosition)
      ..writeByte(4)
      ..write(obj.selectedVoiceName)
      ..writeByte(5)
      ..write(obj.uploadedAt)
      ..writeByte(6)
      ..write(obj.fileFormat)
      ..writeByte(7)
      ..write(obj.folderId)
      ..writeByte(8)
      ..write(obj.totalSentences)
      ..writeByte(9)
      ..write(obj.coverImagePath)
      ..writeByte(10)
      ..write(obj.lastOpenedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EbookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
