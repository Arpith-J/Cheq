enum NoteType { text, drawing }

class LocalNoteModel {
  final String id;
  final DateTime createdAt;
  final String? title;
  final String content;
  final String? filePath;
  final NoteType type;

  const LocalNoteModel({
    required this.id,
    required this.createdAt,
    this.title,
    required this.content,
    this.filePath,
    this.type = NoteType.text,
  });

  LocalNoteModel copyWith({
    String? id,
    DateTime? createdAt,
    String? title,
    String? content,
    String? filePath,
    NoteType? type,
  }) {
    return LocalNoteModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
        'content': content,
        'filePath': filePath,
        'type': type.name,
      };

  factory LocalNoteModel.fromMap(Map<String, dynamic> map) => LocalNoteModel(
        id: map['id'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        title: map['title'] as String?,
        content: map['content'] as String,
        filePath: map['filePath'] as String?,
        type: NoteType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => NoteType.text,
        ),
      );
}
