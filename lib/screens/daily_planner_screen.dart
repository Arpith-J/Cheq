import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planner_model.dart';
import '../providers/planner_provider.dart';
import '../services/firestore_service.dart';
import '../utils/liquid_rescheduler.dart';
import '../widgets/week_header.dart';
import '../widgets/planner/add_task_sheet.dart';
import '../widgets/planner/task_feed.dart';
import '../providers/ai_settings_provider.dart';
import '../utils/ai_rescheduler.dart';

class DailyPlannerScreen extends ConsumerStatefulWidget {
  const DailyPlannerScreen({super.key});

  @override
  ConsumerState<DailyPlannerScreen> createState() => _DailyPlannerScreenState();
}

class _DailyPlannerScreenState extends ConsumerState<DailyPlannerScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      FirestoreService.instance.syncWidgetChangesToFirestore();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirestoreService.instance.syncWidgetChangesToFirestore();
    }
  }

  void _openAddSheet(BuildContext context, WidgetRef ref, {PlannerModel? initialEntry}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: AddTaskSheet(initialEntry: initialEntry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          WeekHeader(),
          Expanded(child: TaskFeed()), // Extracted!
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'rebalance_fab',
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            tooltip: 'Auto-Rebalance Schedule',
            onPressed: () async {
              final day = ref.read(selectedDayProvider);
              final now = DateTime.now();
              
              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
              final startFrom = isToday ? now : DateTime(day.year, day.month, day.day);
              final currentTasks = ref.read(selectedDayEntriesProvider);
              
              final aiSettings = ref.read(aiSettingsProvider);
              bool aiSuccess = false;

              // 🚀 ATTEMPT AI RESCHEDULER FIRST
              if (aiSettings.isReschedulerEnabled && aiSettings.apiKey != null && aiSettings.apiKey!.isNotEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Gemini is reorganizing your day... '),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
                
                // Call the updated AI method
                final aiResult = await AiRescheduler.rebalanceWithAi(
                  todaysTasks: currentTasks,
                  startFrom: startFrom,
                  apiKey: aiSettings.apiKey!,
                );
                
                aiSuccess = aiResult.success;

                if (aiSuccess) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // clear "thinking" snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Schedule optimized by AI! '),
                        duration: const Duration(seconds: 5), // Give them time to click Undo
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        action: SnackBarAction(
                          label: 'UNDO',
                          textColor: Theme.of(context).colorScheme.primaryContainer,
                          onPressed: () async {
                            // ⏪ TRIGGER THE UNDO
                            await FirestoreService.instance.undoAiReschedule(
                              originalTasks: aiResult.originalSnapshot,
                              newlyCreatedSplitIds: aiResult.newSplitIds,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Original schedule restored. ⏪')),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  }
                  return; // Exit here so we don't run the liquid fallback
                }
              }
              
              // 💧 FALLBACK TO LIQUID ALGORITHM (Only runs if AI is off or fails)
              if (!aiSuccess) {
                await LiquidRescheduler.rebalance(currentTasks, startFrom);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Schedule smoothly rebalanced!'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            },
            child: const Icon(Icons.auto_fix_high_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'planner_fab',
            onPressed: () => _openAddSheet(context, ref),
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}