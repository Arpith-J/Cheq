import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/planner_model.dart';

class HomeWidgetService {
  static String activeWidgetSkin = 'default';

  /// SharedPreferences keys consumed by the three native Android widgets.
  static const String todayDataKey = 'widget_data_today';
  static const String plannerDataKey = 'widget_data_planner';
  static const String todoDataKey = 'widget_data_todo';

  static Map<String, dynamic> _plannerTaskToMap(PlannerModel t) {
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
  }

  /// Pushes the THREE widget datasets to SharedPreferences and refreshes every
  /// registered home screen widget:
  ///  - [todayDataKey]  -> tasks scheduled for today with `isDone == false`.
  ///  - [plannerDataKey]-> every pending task (past, today, upcoming).
  ///  - [todoDataKey]   -> every pending item across active todo collections.
  ///
  /// [todoItems] is optional and must already be in widget-row shape
  /// (see [FirestoreService._fetchActiveTodoItems]).
  static Future<void> updateHomeScreenWidgets({
    required List<PlannerModel> tasks,
    List<Map<String, dynamic>>? todoItems,
    String? widgetSkin,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final todayTasks = tasks.where((t) {
        final taskDate =
            DateTime(t.startTime.year, t.startTime.month, t.startTime.day);
        return !t.isDone && taskDate.isAtSameMomentAs(today);
      }).toList();

      final plannerTasks = tasks.where((t) => !t.isDone).toList();

      final String todayJson =
          jsonEncode(todayTasks.map(_plannerTaskToMap).toList());
      final String plannerJson =
          jsonEncode(plannerTasks.map(_plannerTaskToMap).toList());
      final String todoJson = jsonEncode(todoItems ?? const []);

      final String resolvedSkin = widgetSkin ?? activeWidgetSkin;
      debugPrint(
          "🚀 WIDGET DATA PUSHED: today=$todayJson planner=$plannerJson todo=$todoJson (skin: $resolvedSkin)");

      await Future.wait([
        HomeWidget.saveWidgetData(todayDataKey, todayJson),
        HomeWidget.saveWidgetData(plannerDataKey, plannerJson),
        HomeWidget.saveWidgetData(todoDataKey, todoJson),
        HomeWidget.saveWidgetData('widget_skin', resolvedSkin),
        HomeWidget.updateWidget(
          name: 'DailyTaskWidgetProvider',
          androidName: 'DailyTaskWidgetProvider',
        ),
        HomeWidget.updateWidget(
          name: 'PlannerWidgetProvider',
          androidName: 'PlannerWidgetProvider',
        ),
        HomeWidget.updateWidget(
          name: 'TodoWidgetProvider',
          androidName: 'TodoWidgetProvider',
        ),
      ]);
    } catch (e) {
      debugPrint("⚠️ Asynchronous home widget sync failed: $e");
    }
  }
}
