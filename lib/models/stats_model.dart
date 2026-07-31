class StatsModel {
  final double totalHoursAllTime;
  final Map<DateTime, double> hoursPerDayThisWeek;
  final Map<String, double> hoursByCategory;

  const StatsModel({
    this.totalHoursAllTime = 0.0,
    this.hoursPerDayThisWeek = const {},
    this.hoursByCategory = const {},
  });

  StatsModel copyWith({
    double? totalHoursAllTime,
    Map<DateTime, double>? hoursPerDayThisWeek,
    Map<String, double>? hoursByCategory,
  }) {
    return StatsModel(
      totalHoursAllTime: totalHoursAllTime ?? this.totalHoursAllTime,
      hoursPerDayThisWeek: hoursPerDayThisWeek ?? this.hoursPerDayThisWeek,
      hoursByCategory: hoursByCategory ?? this.hoursByCategory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalHoursAllTime': totalHoursAllTime,
      'hoursPerDayThisWeek': hoursPerDayThisWeek.map(
        (key, value) => MapEntry(key.toIso8601String(), value),
      ),
      'hoursByCategory': hoursByCategory,
    };
  }

  factory StatsModel.fromMap(Map<String, dynamic> map) {
    return StatsModel(
      totalHoursAllTime: (map['totalHoursAllTime'] as num).toDouble(),
      hoursPerDayThisWeek: (map['hoursPerDayThisWeek'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(DateTime.parse(key), (value as num).toDouble()),
      ),
      hoursByCategory: (map['hoursByCategory'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
    );
  }
}
