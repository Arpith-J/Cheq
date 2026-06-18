class TaskModel {
  final String id;
  final String title;
  final bool isCompleted;
  final DateTime dueDate;
  final String? groupId; // Reserved for future group/category feature

  const TaskModel({
    required this.id,
    required this.title,
    required this.dueDate,
    this.isCompleted = false,
    this.groupId,
  });

  TaskModel copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? dueDate,
    String? groupId,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: dueDate ?? this.dueDate,
      groupId: groupId ?? this.groupId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'dueDate': dueDate.toIso8601String(),
        'groupId': groupId,
      };

  factory TaskModel.fromMap(Map<String, dynamic> map) => TaskModel(
        id: map['id'] as String,
        title: map['title'] as String,
        isCompleted: (map['isCompleted'] as bool?) ?? false,
        dueDate: DateTime.parse(map['dueDate'] as String),
        groupId: map['groupId'] as String?,
      );
}