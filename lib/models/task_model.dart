class TaskModel {
  final String id;
  final String title;
  final bool isCompleted;
  final DateTime dueDate;
  final String? groupId; // Group the task belongs to (null = personal/private)
  final String? assignedTo; // User UID this task is assigned to (null = creator)

  const TaskModel({
    required this.id,
    required this.title,
    required this.dueDate,
    this.isCompleted = false,
    this.groupId,
    this.assignedTo,
  });

  TaskModel copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? dueDate,
    String? groupId,
    String? assignedTo,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: dueDate ?? this.dueDate,
      groupId: groupId ?? this.groupId,
      assignedTo: assignedTo ?? this.assignedTo,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'dueDate': dueDate.toIso8601String(),
        'groupId': groupId,
        'assignedTo': assignedTo,
      };

  factory TaskModel.fromMap(Map<String, dynamic> map) => TaskModel(
        id: map['id'] as String,
        title: map['title'] as String,
        isCompleted: (map['isCompleted'] as bool?) ?? false,
        dueDate: DateTime.parse(map['dueDate'] as String),
        groupId: map['groupId'] as String?,
        assignedTo: map['assignedTo'] as String?,
      );
}