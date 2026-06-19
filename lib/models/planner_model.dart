// Ensure this enum is present at the absolute top of the file, outside the class!
enum RepeatInterval { none, daily, weekly, monthly, custom }

class PlannerModel {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isDone;
  final bool isNotified; // Make sure this is present too since your provider uses it!
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
}