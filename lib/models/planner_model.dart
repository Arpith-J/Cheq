enum RepeatInterval { none, daily, weekly, monthly, custom }

class PlannerModel {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isDone;
  final bool isNotified;
  final RepeatInterval repeatInterval;
  final Duration? customInterval;

  const PlannerModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isDone = false,
    this.isNotified = false,
    this.repeatInterval = RepeatInterval.none,
    this.customInterval,
  });

  PlannerModel copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool? isDone,
    bool? isNotified,
    RepeatInterval? repeatInterval,
    Duration? customInterval,
  }) {
    return PlannerModel(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isDone: isDone ?? this.isDone,
      isNotified: isNotified ?? this.isNotified,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      customInterval: customInterval ?? this.customInterval,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'isDone': isDone,
      'isNotified': isNotified,
      'repeatInterval': repeatInterval.name,
      'customIntervalInSeconds': customInterval?.inSeconds,
    };
  }

  factory PlannerModel.fromMap(Map map) {
    return PlannerModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      isDone: map['isDone'] ?? false,
      isNotified: map['isNotified'] ?? false,
      repeatInterval: RepeatInterval.values.firstWhere(
        (e) => e.name == map['repeatInterval'],
        orElse: () => RepeatInterval.none,
      ),
      customInterval: map['customIntervalInSeconds'] != null
          ? Duration(seconds: map['customIntervalInSeconds'] as int)
          : null,
    );
  }
}