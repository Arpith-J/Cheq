import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';

// 📸 1. THE NEW SNAPSHOT CLASS
class AiResult {
  final bool success;
  final List<PlannerModel> originalSnapshot;
  final List<String> newSplitIds;

  AiResult(this.success, this.originalSnapshot, this.newSplitIds);
}

class AiRescheduler {
  // 🔄 2. CHANGED RETURN TYPE HERE
  static Future<AiResult> rebalanceWithAi({
    required List<PlannerModel> todaysTasks,
    required DateTime startFrom,
    required String apiKey,
  }) async {
    try {
      final pendingTasks = todaysTasks.where((t) {
        return !t.isDone && t.endTime.isAfter(startFrom);
      }).toList();

      if (pendingTasks.isEmpty) return AiResult(false, [], []);

      final List<Map<String, dynamic>> simplifiedTasks = pendingTasks.map((t) => {
        'id': t.id,
        'title': t.title,
        'isTimeLocked': t.isTimeLocked,
        'startTime': t.startTime.toIso8601String(),
        'endTime': t.endTime.toIso8601String(),
      }).toList();

      final String tasksJson = jsonEncode(simplifiedTasks);

      final model = GenerativeModel(
        model: 'gemini-1.5-pro', 
        apiKey: apiKey,
      );

      final prompt = '''
You are an advanced productivity scheduling assistant. 
An unexpected schedule change has occurred at ${startFrom.toIso8601String()}.
Below is the user's remaining schedule in JSON format. 

Your Rules:
1. Tasks with "isTimeLocked": true CANNOT be moved or changed.
2. MINIMIZE DISRUPTION: Do not simply push all tasks down. Try to absorb the delay locally to keep the user's original flow intact.
3. COMPRESS BREAKS: If there are flexible tasks conceptually related to "Break", "Lunch", "Rest", or "Free Time", you may shrink their duration (minimum 15-30 mins) to make room for the urgent task.
4. SPLIT TASKS: If an urgent locked task drops right in the middle of a long flexible task, you MUST split the flexible task into two parts (before and after the interruption).
   - If you split a task, append "_partA" and "_partB" to its original ID (e.g., "entry_123_partA").
   - Update its title to include the split (e.g., "Study (A)" and "Study (B)").
5. KEEP NAMES SAME: Do not change task titles unless you are appending (A) and (B) for a split.
6. Absolutely no time overlaps allowed.

Input Schedule:
$tasksJson

Output STRICTLY a raw JSON array (NO markdown formatting, NO backticks) containing only the updated/split objects with 'id', 'title', 'startTime', and 'endTime'. 
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final rawText = response.text?.trim() ?? '';

      String cleanJson = rawText;
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7, cleanJson.length - 3).trim();
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3, cleanJson.length - 3).trim();
      }

      final List<dynamic> updatedList = jsonDecode(cleanJson);
      
      List<PlannerModel> tasksToSave = [];
      List<String> idsToDelete = [];
      
      for (var aiTask in updatedList) {
        final String taskId = aiTask['id'];
        final String title = aiTask['title'];
        final DateTime newStart = DateTime.parse(aiTask['startTime']);
        final DateTime newEnd = DateTime.parse(aiTask['endTime']);

        final bool isSplit = taskId.contains('_part');
        final String baseId = isSplit ? taskId.split('_part')[0] : taskId;

        final originalTask = pendingTasks.firstWhere((t) => t.id == baseId, orElse: () => pendingTasks.first);
        if (originalTask.id != baseId) continue; 

        if (isSplit) {
          if (!idsToDelete.contains(baseId)) {
            idsToDelete.add(baseId);
          }
          tasksToSave.add(originalTask.copyWith(
            id: taskId,
            title: title, 
            startTime: newStart,
            endTime: newEnd,
          ));
        } else {
          if (originalTask.startTime != newStart || originalTask.endTime != newEnd || originalTask.title != title) {
            tasksToSave.add(originalTask.copyWith(
              title: title,
              startTime: newStart,
              endTime: newEnd,
            ));
          }
        }
      }

      if (tasksToSave.isNotEmpty || idsToDelete.isNotEmpty) {
        // 📸 3. TAKE THE SNAPSHOT BEFORE RETURNING
        final snapshotTasks = pendingTasks.where((t) => 
            tasksToSave.any((saved) => saved.id == t.id) || 
            idsToDelete.contains(t.id)
        ).toList();
        
        final newSplitIds = tasksToSave.where((t) => t.id.contains('_part')).map((t) => t.id).toList();

        await FirestoreService.instance.saveAndCleanTasksBatch(tasksToSave, idsToDelete);
        
        return AiResult(true, snapshotTasks, newSplitIds); 
      }
      
      return AiResult(true, [], []); 

    } catch (e) {
      debugPrint("🤖 AI Rescheduler Failed: $e");
      return AiResult(false, [], []); 
    }
  }
}