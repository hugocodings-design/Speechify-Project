import 'package:hive/hive.dart';

part 'folder.g.dart';

@HiveType(typeId: 3)
class Folder {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  final DateTime createdAt;

  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
  });
}
