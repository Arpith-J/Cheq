import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';

class HomeWidgetService {
  static Future<void> updateHomeScreenWidgetData(List<PlannerModel> tasks) async {
    try {
      // 🌟 FIX: We map directly to a single, cleanly defined variable array
      final List<Map<String, dynamic>> mappedTasks = tasks.map((t) {
        final hour = t.startTime.hour % 12 == 0 ? 12 : t.startTime.hour % 12;
        final minute = t.startTime.minute.toString().padLeft(2, '0');
        final period = t.startTime.hour < 12 ? 'AM' : 'PM';
        
        return {
          'title': t.title,
          'isDone': t.isDone,
          'time': '$hour:$minute $period'
        };
      }).toList();

      final String tasksJson = jsonEncode(mappedTasks);
      debugPrint("🚀 WIDGET DATA PUSHED: $tasksJson");

      // Write the preference data strings out asynchronously
      await Future.wait([
        HomeWidget.saveWidgetData<String>('daily_tasks_key', tasksJson),
        HomeWidget.saveWidgetData<String>('flutter.daily_tasks_key', tasksJson),
      ]);

      // Inform the native launcher interface framework manager to refresh
      await HomeWidget.updateWidget(
        name: 'DailyTaskWidgetProvider',
        androidName: 'DailyTaskWidgetProvider',
      );
    } catch (e) {
      debugPrint("⚠️ Asynchronous home widget sync failed: $e");
    }
  }
}