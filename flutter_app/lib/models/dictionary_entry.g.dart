// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictionary_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DictionaryEntryAdapter extends TypeAdapter<DictionaryEntry> {
  @override
  final int typeId = 5;

  @override
  DictionaryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DictionaryEntry(
      id: fields[0] as String,
      word: fields[1] as String,
      wordLower: fields[2] as String,
      ebookId: fields[3] as String,
      chapterId: fields[4] as String,
      sourceLang: fields[5] as String,
      targetLang: fields[6] as String,
      translatedWord: fields[7] as String,
      partOfSpeech: fields[8] as String,
      definition: fields[9] as String,
      example: fields[10] as String,
      synonyms: (fields[11] as List).cast<String>(),
      createdAt: fields[12] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, DictionaryEntry obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.word)
      ..writeByte(2)
      ..write(obj.wordLower)
      ..writeByte(3)
      ..write(obj.ebookId)
      ..writeByte(4)
      ..write(obj.chapterId)
      ..writeByte(5)
      ..write(obj.sourceLang)
      ..writeByte(6)
      ..write(obj.targetLang)
      ..writeByte(7)
      ..write(obj.translatedWord)
      ..writeByte(8)
      ..write(obj.partOfSpeech)
      ..writeByte(9)
      ..write(obj.definition)
      ..writeByte(10)
      ..write(obj.example)
      ..writeByte(11)
      ..write(obj.synonyms)
      ..writeByte(12)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
