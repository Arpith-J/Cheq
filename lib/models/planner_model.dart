// lib/models/planner_model.dart

class PlannerModel {
  final String   id;
  final String   title;
  final DateTime startTime;
  final DateTime endTime;
  final bool     isNotified;
  final bool     isDone;      // ← added

  const PlannerModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isNotified = false,
    this.isDone     = false,  // ← added
  });

  PlannerModel copyWith({
    String?   id,
    String?   title,
    DateTime? startTime,
    DateTime? endTime,
    bool?     isNotified,
    bool?     isDone,         // ← added
  }) {
    return PlannerModel(
      id:         id         ?? this.id,
      title:      title      ?? this.title,
      startTime:  startTime  ?? this.startTime,
      endTime:    endTime    ?? this.endTime,
      isNotified: isNotified ?? this.isNotified,
      isDone:     isDone     ?? this.isDone,     // ← added
    );
  }

  Map<String, dynamic> toMap() => {
        'id':         id,
        'title':      title,
        'startTime':  startTime.toIso8601String(),
        'endTime':    endTime.toIso8601String(),
        'isNotified': isNotified,
        'isDone':     isDone,                    // ← added
      };

  factory PlannerModel.fromMap(Map<String, dynamic> map) => PlannerModel(
        id:         map['id']         as String,
        title:      map['title']      as String,
        startTime:  DateTime.parse(map['startTime'] as String),
        endTime:    DateTime.parse(map['endTime']   as String),
        isNotified: (map['isNotified'] as bool?) ?? false,
        isDone:     (map['isDone']     as bool?) ?? false,     // ← added
      );

  @override
  String toString() =>
      'PlannerModel(id: $id, title: $title, startTime: $startTime, endTime: $endTime)';
}