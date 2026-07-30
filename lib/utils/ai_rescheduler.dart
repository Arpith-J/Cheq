import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/planner_model.dart';
import '../services/firestore_service.dart';
import '../services/gemini_api_service.dart';

class AiResult {
  final bool success;
  final List<PlannerModel> originalSnapshot;
  final List<String> newSplitIds;

  AiResult(this.success, this.originalSnapshot, this.newSplitIds);
}

class AiRescheduler {
  static Future<AiResult> rebalanceWithAi({
    required List<PlannerModel> todaysTasks,
    required DateTime startFrom,
    required String apiKey,
  }) async {
    try {
      final pendingTasks = todaysTasks.where((t) {
        return !t.isDone && t.endTime.isAfter(startFrom);
      }).toList();

      if (pendingTasks.isEmpty) {
        return AiResult(false, [], []);
      }

      final simplifiedTasks = pendingTasks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'isTimeLocked': t.isTimeLocked,
                'startTime': t.startTime.toIso8601String(),
                'endTime': t.endTime.toIso8601String(),
              })
          .toList();

      final tasksJson = jsonEncode(simplifiedTasks);

      final prompt = '''
You are an advanced productivity scheduling assistant.

An unexpected schedule change has occurred at ${startFrom.toIso8601String()}.

Below is the user's remaining schedule in JSON format.

Rules:
1. Tasks with "isTimeLocked": true cannot be moved or changed.
2. Minimize disruption. Do not simply push all tasks down if a better local adjustment exists.
3. You may compress breaks like Break, Lunch, Rest, or Free Time to a minimum of 15 minutes if needed.
4. If a locked task interrupts a long flexible task, you may split the flexible task into two parts.
5. If you split a task, append "_partA" and "_partB" to the original ID.
6. If you split a task title, only append "(A)" and "(B)".
7. No overlaps are allowed.
8. Preserve all unchanged tasks exactly.
9. Return only valid JSON.

Input schedule:
$tasksJson

Return a raw JSON array of objects with exactly these fields:
id, title, startTime, endTime
''';

      final rawText = await GeminiApiService.generateText(
        apiKey: apiKey,
        model: 'gemini-3.6-flash',
        prompt: prompt,
        temperature: 0.2,
        maxOutputTokens: 500,
        responseMimeType: 'application/json',
      );

      if (rawText == null || rawText.trim().isEmpty) {
        return AiResult(false, [], []);
      }

      final updatedList = jsonDecode(rawText) as List<dynamic>;

      final List<PlannerModel> tasksToSave = [];
      final List<String> idsToDelete = [];

      for (final aiTask in updatedList) {
        if (aiTask is! Map<String, dynamic>) continue;

        final taskId = aiTask['id']?.toString();
        final title = aiTask['title']?.toString();
        final startTimeRaw = aiTask['startTime']?.toString();
        final endTimeRaw = aiTask['endTime']?.toString();

        if (taskId == null ||
            title == null ||
            startTimeRaw == null ||
            endTimeRaw == null) {
          continue;
        }

        final newStart = DateTime.tryParse(startTimeRaw);
        final newEnd = DateTime.tryParse(endTimeRaw);

        if (newStart == null || newEnd == null || !newEnd.isAfter(newStart)) {
          continue;
        }

        final isSplit = taskId.contains('_part');
        final baseId = isSplit ? taskId.split('_part')[0] : taskId;

        PlannerModel? originalTask;
        for (final task in pendingTasks) {
          if (task.id == baseId) {
            originalTask = task;
            break;
          }
        }
        if (originalTask == null) continue;

        if (isSplit) {
          if (!idsToDelete.contains(baseId)) {
            idsToDelete.add(baseId);
          }

          tasksToSave.add(
            originalTask.copyWith(
              id: taskId,
              title: title,
              startTime: newStart,
              endTime: newEnd,
            ),
          );
        } else {
          final changed = originalTask.startTime != newStart ||
              originalTask.endTime != newEnd ||
              originalTask.title != title;

          if (changed) {
            tasksToSave.add(
              originalTask.copyWith(
                title: title,
                startTime: newStart,
                endTime: newEnd,
              ),
            );
          }
        }
      }

      if (tasksToSave.isNotEmpty || idsToDelete.isNotEmpty) {
        final snapshotTasks = pendingTasks.where((t) {
          return tasksToSave.any((saved) => saved.id == t.id) ||
              idsToDelete.contains(t.id);
        }).toList();

        final newSplitIds = tasksToSave
            .where((t) => t.id.contains('_part'))
            .map((t) => t.id)
            .toList();

        await FirestoreService.instance
            .saveAndCleanTasksBatch(tasksToSave, idsToDelete);

        return AiResult(true, snapshotTasks, newSplitIds);
      }

      return AiResult(true, [], []);
    } catch (e) {
      debugPrint('⚠️ AI Rescheduler Failed: $e');
      return AiResult(false, [], []);
    }
  }
}