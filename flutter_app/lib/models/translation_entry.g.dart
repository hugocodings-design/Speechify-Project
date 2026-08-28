// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TranslationEntryAdapter extends TypeAdapter<TranslationEntry> {
  @override
  final int typeId = 6;

  @override
  TranslationEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TranslationEntry(
      id: fields[0] as String,
      text: fields[1] as String,
      translatedText: fields[2] as String,
      ebookId: fields[3] as String,
      chapterId: fields[4] as String,
      paragraphIndexInChapter: fields[8] as int,
      sourceLang: fields[5] as String,
      targetLang: fields[6] as String,
      createdAt: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, TranslationEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.translatedText)
      ..writeByte(3)
      ..write(obj.ebookId)
      ..writeByte(4)
      ..write(obj.chapterId)
      ..writeByte(8)
      ..write(obj.paragraphIndexInChapter)
      ..writeByte(5)
      ..write(obj.sourceLang)
      ..writeByte(6)
      ..write(obj.targetLang)
      ..writeByte(7)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
