import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';

class AiRescheduler {
  /// Calls Gemini to rebalance the schedule, then saves the result.
  static Future<bool> rebalanceWithAi({
    required List<PlannerModel> todaysTasks,
    required DateTime startFrom,
    required String apiKey,
  }) async {
    try {
      // 1. Filter tasks: Only send pending tasks that end after the interruption
      final pendingTasks = todaysTasks.where((t) {
        return !t.isDone && t.endTime.isAfter(startFrom);
      }).toList();

      if (pendingTasks.isEmpty) return false;

      // 2. Create a lightweight JSON payload to save AI tokens
      final List<Map<String, dynamic>> simplifiedTasks = pendingTasks.map((t) => {
        'id': t.id,
        'title': t.title,
        'isTimeLocked': t.isTimeLocked,
        'startTime': t.startTime.toIso8601String(),
        'endTime': t.endTime.toIso8601String(),
      }).toList();

      final String tasksJson = jsonEncode(simplifiedTasks);

      // 3. Initialize Gemini (Using 1.5 Flash for maximum speed and lowest cost)
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
      );

      // 4. The System Prompt
      final prompt = '''
You are an expert productivity scheduling assistant. 
An unexpected event has occurred at ${startFrom.toIso8601String()}.
Below is the user's remaining schedule in JSON format. 

Your Rules:
1. Tasks where "isTimeLocked" is true CANNOT be moved. Leave their times exactly as they are.
2. Tasks where "isTimeLocked" is false are flexible. Move them into the empty gaps around the locked tasks.
3. Keep the original duration of each flexible task exactly the same.
4. Do not overlap any tasks.
5. Keep flexible tasks in their original relative priority order if possible.

Input Schedule:
$tasksJson

Output STRICTLY a raw JSON array (NO markdown formatting, NO backticks) containing only the updated objects with 'id', 'startTime', and 'endTime'. Example:
[{"id": "entry_123", "startTime": "2024-10-25T14:00:00.000", "endTime": "2024-10-25T15:00:00.000"}]
''';

      // 5. Call the API
      final response = await model.generateContent([Content.text(prompt)]);
      final rawText = response.text?.trim() ?? '';

      // 6. Sanitize the output (in case Gemini accidentally adds markdown code blocks)
      String cleanJson = rawText;
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7, cleanJson.length - 3).trim();
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3, cleanJson.length - 3).trim();
      }

      // 7. Parse the response
      final List<dynamic> updatedList = jsonDecode(cleanJson);
      
      // 8. Merge the new times with our original task objects
      List<PlannerModel> tasksToSave = [];
      
      for (var aiTask in updatedList) {
        final String taskId = aiTask['id'];
        final DateTime newStart = DateTime.parse(aiTask['startTime']);
        final DateTime newEnd = DateTime.parse(aiTask['endTime']);

        // Find the original task to copy all its other properties (repeat rules, notifications, etc.)
        final originalTask = pendingTasks.firstWhere((t) => t.id == taskId);
        
        // Only update if the time actually changed
        if (originalTask.startTime != newStart || originalTask.endTime != newEnd) {
          tasksToSave.add(originalTask.copyWith(
            startTime: newStart,
            endTime: newEnd,
          ));
        }
      }

      // 9. Push to Firestore using your existing batch method!
      if (tasksToSave.isNotEmpty) {
        await FirestoreService.instance.saveTasksBatch(tasksToSave);
      }
      
      return true; // Success!

    } catch (e) {
      debugPrint("🤖 AI Rescheduler Failed: $e");
      return false; // Tells the UI to fallback to the Liquid algorithm
    }
  }
}