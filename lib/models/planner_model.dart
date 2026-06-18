class PlannerModel {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isNotified;

  const PlannerModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isNotified = false,
  });

  PlannerModel copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool? isNotified,
  }) {
    return PlannerModel(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isNotified: isNotified ?? this.isNotified,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'isNotified': isNotified,
      };

  factory PlannerModel.fromMap(Map<String, dynamic> map) => PlannerModel(
        id: map['id'] as String,
        title: map['title'] as String,
        startTime: DateTime.parse(map['startTime'] as String),
        endTime: DateTime.parse(map['endTime'] as String),
        isNotified: (map['isNotified'] as bool?) ?? false,
      );
}