enum NoteType { text, drawing }

class LocalNoteModel {
  final String id;
  final DateTime createdAt;
  final String? title;
  final String content;
  final String? filePath;
  final NoteType type;

  /// JSON string of the Quill document (obtained from
  /// `document.toDelta().toJson()`). Null for legacy text/drawing notes.
  final String? quillDelta;

  /// JSON string of the saved drawing strokes (colors and thickness included).
  /// Null for legacy text notes.
  final String? vectorStrokes;

  const LocalNoteModel({
    required this.id,
    required this.createdAt,
    this.title,
    required this.content,
    this.filePath,
    this.type = NoteType.text,
    this.quillDelta,
    this.vectorStrokes,
  });

  LocalNoteModel copyWith({
    String? id,
    DateTime? createdAt,
    String? title,
    String? content,
    String? filePath,
    NoteType? type,
    String? quillDelta,
    String? vectorStrokes,
  }) {
    return LocalNoteModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      quillDelta: quillDelta ?? this.quillDelta,
      vectorStrokes: vectorStrokes ?? this.vectorStrokes,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
        'content': content,
        'filePath': filePath,
        'type': type.name,
        'quillDelta': quillDelta,
        'vectorStrokes': vectorStrokes,
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
        quillDelta: map['quillDelta'] as String?,
        vectorStrokes: map['vectorStrokes'] as String?,
      );
}
