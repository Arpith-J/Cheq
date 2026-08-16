enum RepeatInterval { none, daily, weekly, monthly, custom }

class PlannerModel {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isDone;
  final bool isNotified;
  final bool isTimeLocked; 
  final bool isRewarded;
  final int coinsAwarded;
  final RepeatInterval repeatInterval;
  final Duration? customInterval;
  final String? repeatGroupId;
  final String? categoryName;
  final int? categoryColor;
  final String? groupId; // Group the task belongs to (null = personal/private)
  final String? assignedTo; // User UID this task is assigned to (null = creator)
  final DateTime? createdAt; // When the task was added (used to order group tasks)

  const PlannerModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isDone = false,
    this.isNotified = false,
    this.isTimeLocked = false, // Defaults to flexible
    this.isRewarded = false,
    this.coinsAwarded = 0,
    this.repeatInterval = RepeatInterval.none,
    this.customInterval,
    this.repeatGroupId,
    this.categoryName,
    this.categoryColor,
    this.groupId,
    this.assignedTo,
    this.createdAt,
  });

  PlannerModel copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool? isDone,
    bool? isNotified,
    bool? isTimeLocked,
    bool? isRewarded,
    int? coinsAwarded,
    RepeatInterval? repeatInterval,
    Duration? customInterval,
    String? repeatGroupId,
    String? categoryName,
    int? categoryColor,
    String? groupId,
    String? assignedTo,
    DateTime? createdAt,
  }) {
    return PlannerModel(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isDone: isDone ?? this.isDone,
      isNotified: isNotified ?? this.isNotified,
      isTimeLocked: isTimeLocked ?? this.isTimeLocked,
      isRewarded: isRewarded ?? this.isRewarded,
      coinsAwarded: coinsAwarded ?? this.coinsAwarded,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      customInterval: customInterval ?? this.customInterval,
      repeatGroupId: repeatGroupId ?? this.repeatGroupId,
      categoryName: categoryName ?? this.categoryName,
      categoryColor: categoryColor ?? this.categoryColor,
      groupId: groupId ?? this.groupId,
      assignedTo: assignedTo ?? this.assignedTo,
      createdAt: createdAt ?? this.createdAt,
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
      'isTimeLocked': isTimeLocked,
      'isRewarded': isRewarded,
      'coinsAwarded': coinsAwarded,
      'repeatInterval': repeatInterval.name,
      'customIntervalInSeconds': customInterval?.inSeconds,
      'repeatGroupId': repeatGroupId,
      'categoryName': categoryName,
      'categoryColor': categoryColor,
      'groupId': groupId,
      'assignedTo': assignedTo,
      'createdAt': createdAt?.toIso8601String(),
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
      isTimeLocked: map['isTimeLocked'] ?? false,
      isRewarded: map['isRewarded'] ?? false,
      coinsAwarded: (map['coinsAwarded'] as int?) ?? 0,
      repeatInterval: RepeatInterval.values.firstWhere(
        (e) => e.name == map['repeatInterval'],
        orElse: () => RepeatInterval.none,
      ),
      customInterval: map['customIntervalInSeconds'] != null
          ? Duration(seconds: map['customIntervalInSeconds'] as int)
          : null,
      repeatGroupId: map['repeatGroupId'] as String?,
      categoryName: map['categoryName'] as String?,
      categoryColor: map['categoryColor'] as int?,
      groupId: map['groupId'] as String?,
      assignedTo: map['assignedTo'] as String?,
      createdAt: _parseDate(map['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}