// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'annotation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnnotationAdapter extends TypeAdapter<Annotation> {
  @override
  final int typeId = 4;

  @override
  Annotation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Annotation(
      id: fields[0] as String,
      ebookId: fields[1] as String,
      chapterId: fields[2] as String,
      paragraphIndexInChapter: fields[3] as int,
      startOffset: fields[4] as int,
      endOffset: fields[5] as int,
      selectedText: fields[6] as String,
      createdAt: fields[7] as DateTime,
      note: fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Annotation obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.ebookId)
      ..writeByte(2)
      ..write(obj.chapterId)
      ..writeByte(3)
      ..write(obj.paragraphIndexInChapter)
      ..writeByte(4)
      ..write(obj.startOffset)
      ..writeByte(5)
      ..write(obj.endOffset)
      ..writeByte(6)
      ..write(obj.selectedText)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnotationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
