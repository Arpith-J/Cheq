import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';

class HomeWidgetService {
  static Future<void> updateHomeScreenWidgetData(List<PlannerModel> tasks) async {
  try {
    final List<Map<String, dynamic>> mappedTasks = tasks.map((t) {
      final hour = t.startTime.hour % 12 == 0 ? 12 : t.startTime.hour % 12;
      final minute = t.startTime.minute.toString().padLeft(2, '0');
      final period = t.startTime.hour < 12 ? 'AM' : 'PM';

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final date = '${t.startTime.day} ${months[t.startTime.month - 1]} ${t.startTime.year}';

      return {
        'id': t.id,
        'title': t.title,
        'isDone': t.isDone,
        'time': '$hour:$minute $period',
        'date': date,
      };
    }).toList();

    final String tasksJson = jsonEncode(mappedTasks);
    debugPrint("🚀 WIDGET DATA PUSHED: $tasksJson");

    await Future.wait([
      HomeWidget.saveWidgetData('daily_tasks_key', tasksJson),
      HomeWidget.saveWidgetData('flutter.daily_tasks_key', tasksJson),
    ]);

    await HomeWidget.updateWidget(
      name: 'DailyTaskWidgetProvider',
      androidName: 'DailyTaskWidgetProvider',
    );
  } catch (e) {
    debugPrint("⚠️ Asynchronous home widget sync failed: $e");
  }
}
}