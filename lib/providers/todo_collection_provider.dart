// lib/providers/todo_collection_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planner_model.dart';
import '../services/firestore_service.dart';
import '../utils/stream_merge.dart';
import 'rewards_provider.dart';
import 'spaces_provider.dart';
import 'task_settings_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class TodoItem {
  final String id;
  final String text;
  final bool isDone;
  final String? groupId; // Group the item belongs to (null = personal/private)
  final String? assignedTo; // User UID this item is assigned to (null = creator)

  const TodoItem({
    required this.id,
    required this.text,
    required this.isDone,
    this.groupId,
    this.assignedTo,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'isDone': isDone,
        'groupId': groupId,
        'assignedTo': assignedTo,
      };

  factory TodoItem.fromMap(Map<String, dynamic> map) => TodoItem(
        id: map['id'] as String,
        text: map['text'] as String,
        isDone: (map['isDone'] as bool?) ?? false,
        groupId: map['groupId'] as String?,
        assignedTo: map['assignedTo'] as String?,
      );

  TodoItem copyWith({bool? isDone}) =>
      TodoItem(id: id, text: text, isDone: isDone ?? this.isDone, groupId: groupId, assignedTo: assignedTo);
}

class TodoCollection {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? archivedAt;
  final bool isArchived;
  final List<TodoItem> items;
  final int coinsReward;
  final String? groupId; // Group this collection belongs to (null = personal)
  final String? assignedTo; // User UID assigned to this collection (null = creator)

  const TodoCollection({
    required this.id,
    required this.title,
    required this.createdAt,
    this.archivedAt,
    required this.isArchived,
    required this.items,
    required this.coinsReward,
    this.groupId,
    this.assignedTo,
  });

  // Business Logic: Differentiate single line Tasks from compound Lists
  bool get isSingleTask => items.length == 1 && items.first.text == title;
  bool get isCompleted => items.isNotEmpty && items.every((i) => i.isDone);

  factory TodoCollection.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawItems = (data['items'] as List<dynamic>?) ?? [];
    return TodoCollection(
      id:          doc.id,
      title:       data['title'] as String? ?? '',
      createdAt:   (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      archivedAt:  (data['archivedAt'] as Timestamp?)?.toDate(),  
      isArchived:  (data['isArchived'] as bool?) ?? false,
      items:       rawItems
          .map((e) => TodoItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      coinsReward: (data['coinsReward'] as int?) ?? 10,
      groupId: data['groupId'] as String?,
      assignedTo: data['assignedTo'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String? _uid() => FirebaseAuth.instance.currentUser?.uid;

CollectionReference<Map<String, dynamic>> _collectionsRef() =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(_uid())
        .collection('todo_collections');

// ---------------------------------------------------------------------------
// StreamProvider — pulls all items up to 3 days old for completions
// ---------------------------------------------------------------------------

final todoCollectionsProvider = StreamProvider<List<TodoCollection>>((ref) {
  final uid = _uid();
  if (uid == null) return const Stream.empty();

  // Pull everything from the user. Filtering logic happens dynamically in the UI
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('todo_collections')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(TodoCollection.fromDoc).toList());
});

// ---------------------------------------------------------------------------
// Group task bridging — shared `spaces/{spaceId}/tasks` rendered as personal
// To-Do entries on the main dashboard, gated by the showGroupTasks toggle.
// ---------------------------------------------------------------------------

/// Converts a shared [PlannerModel] into a single-item [TodoCollection] so it
/// renders like a personal quick task. The [groupId] keeps it visually tagged
/// as collaborative, and every toggle is routed back to the Space document
/// (never to the personal `users/{uid}/todo_collections` collection).
TodoCollection groupTaskToTodoCollection(PlannerModel task, String spaceId) {
  final item = TodoItem(
    id: task.id,
    text: task.title,
    isDone: task.isDone,
    groupId: task.groupId ?? spaceId,
    assignedTo: task.assignedTo,
  );
  return TodoCollection(
    id: task.id,
    title: task.title,
    createdAt: task.createdAt ?? task.startTime,
    archivedAt: task.isDone ? DateTime.now() : null,
    isArchived: task.isDone,
    items: [item],
    coinsReward: 0,
    groupId: task.groupId ?? spaceId,
    assignedTo: task.assignedTo,
  );
}

/// Reconstructs the shared task document from a [TodoCollection] produced by
/// [groupTaskToTodoCollection], for routing toggles back through
/// [FirestoreService.toggleGroupTaskCompletion].
PlannerModel groupTaskFromTodoCollection(TodoCollection collection) =>
    PlannerModel(
      id: collection.id,
      title: collection.title,
      startTime: collection.createdAt,
      endTime: collection.createdAt,
      isDone: collection.items.isNotEmpty ? collection.items.first.isDone : false,
      groupId: collection.groupId,
      assignedTo: collection.assignedTo,
    );

/// Merged To-Do stream shown on the main dashboard: the user's personal
/// `todo_collections` plus their shared Space tasks as single-item cards,
/// sorted with pending tasks first, then by newest. Personal-only when the
/// [showGroupTasksProvider] toggle is off.
///
/// Only point-in-time checklist items from the Group To-Do tab surface here —
/// the exact inverse of [isGroupTimeBlocked]. Time-blocked Group Planner tasks
/// stay on the personal Daily Planner timeline instead of leaking onto this
/// To-Do list.
final mergedTodoCollectionsProvider = StreamProvider<List<TodoCollection>>(
  (ref) {
    final uid = _uid();
    if (uid == null) return const Stream.empty();

    final personal = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('todo_collections')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TodoCollection.fromDoc).toList());

    if (!ref.watch(showGroupTasksProvider)) return personal;

    return ref.watch(userSpacesProvider).when(
          data: (spaces) => mergeSpacesStreams<TodoCollection>(
            personal: personal,
            spaces: spaces,
            idOf: (col) => col.id,
            perSpace: (spaceId) => FirestoreService.instance
                .streamGroupTasks(spaceId)
                .map((tasks) => tasks
                    .where((t) =>
                        isGroupTaskRelevantTo(uid, t) &&
                        !isGroupTimeBlocked(t))
                    .map((t) => groupTaskToTodoCollection(t, spaceId))
                    .toList()),
          ).map((merged) {
            final sorted = [...merged]
              ..sort((a, b) {
                final aDone = a.isArchived ? 1 : 0;
                final bDone = b.isArchived ? 1 : 0;
                if (aDone != bDone) return aDone.compareTo(bDone);
                return b.createdAt.compareTo(a.createdAt);
              });
            return sorted;
          }),
          loading: () => personal,
          error: (_, _) => personal,
        );
  },
);

final completedTodoCollectionsProvider = Provider<List<TodoCollection>>((ref) {
  final asyncCollections = ref.watch(todoCollectionsProvider);
  final collections = asyncCollections.value ?? [];

  final today = DateTime.now();
  final threeDaysAgo = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 3));

  return collections.where((col) {
    if (!col.isArchived) return false; 
    if (col.archivedAt == null) return false;

    return col.archivedAt!.isAfter(threeDaysAgo);
  }).toList();
});

// ---------------------------------------------------------------------------
// AsyncNotifier — mutations
// ---------------------------------------------------------------------------

class TodoCollectionNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> createCollection(
    String title,
    List<String> initialItemTexts, {
    required int coinsReward,
  }) async {
    if (title.trim().isEmpty) return;

    final filteredTexts = initialItemTexts.where((t) => t.trim().isNotEmpty).toList();

    final items = filteredTexts
        .mapIndexed((i, text) => TodoItem(
              id:     'item_${DateTime.now().millisecondsSinceEpoch}_$i',
              text:   text.trim(),
              isDone: false,
            ))
        .map((e) => e.toMap())
        .toList();

    await _collectionsRef().add({
      'title':       title.trim(),
      'createdAt':   FieldValue.serverTimestamp(),
      'isArchived':  false,
      'items':       items,
      'coinsReward': coinsReward,
    });
  }

  Future<void> toggleItem(String collectionId, String itemId, bool currentStatus) async {
    final uid = _uid();
    if (uid == null) return;

    final db      = FirebaseFirestore.instance;
    final colRef  = db.collection('users').doc(uid).collection('todo_collections').doc(collectionId);

    // ── 1. Mutate the collection document atomically ─────────────────────────
    final result = await db.runTransaction((tx) async {
      final snap = await tx.get(colRef);
      if (!snap.exists) return null;
      final data     = snap.data()!;
      final isTask   = (data['items'] as List<dynamic>).length == 1 && (data['items'] as List<dynamic>).first['text'] == data['title'];
      final rawItems = List<Map<String, dynamic>>.from(
        (snap.data()!['items'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final updated = rawItems.map((item) {
        if (item['id'] == itemId) {
          return {...item, 'isDone': !currentStatus};
        }
        return item;
      }).toList();

      final allDone     = updated.every((item) => item['isDone'] == true);
      final wasArchived = data['isArchived'] as bool? ?? false;

      tx.update(colRef, {'items': updated});

      if (allDone) {
        tx.update(colRef, {
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(), // Track completion time
        });
      } else {
        // Restores the card to active states if any single item is unchecked
        tx.update(colRef, {
          'isArchived': false,
          'archivedAt': FieldValue.delete(), // Clears completion time tracking
        });
      }

      return (isTask: isTask, allDone: allDone, wasArchived: wasArchived);
    });

    if (result == null) return;

    // ── 2. Apply the coin economy through the rewards provider ───────────────
    final rewards = ref.read(rewardsProvider.notifier);
    if (!currentStatus) {
      // Checking an item as DONE:
      // Rule: +5 for completing any item (independent task or inside a list)
      await rewards.awardTodoCompletion();

      // Rule: If it's a multi-item list and this action completes it, add +10 bonus
      if (!result.isTask && result.allDone) {
        await rewards.awardTodoListCompletion();
      }
    } else {
      // Unchecking an item to UNDONE:
      // Rule: Remove 5 coins for unchecking the item
      await rewards.deductTodoCompletion();

      // Rule: If it was a completed list, strip the 10 coin completion bonus too
      if (!result.isTask && result.wasArchived) {
        await rewards.deductTodoListCompletion();
      }
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    await _collectionsRef().doc(collectionId).delete();
  }
}

final todoCollectionNotifierProvider = AsyncNotifierProvider<TodoCollectionNotifier, void>(
  TodoCollectionNotifier.new,
);

extension TodoIndexedMap<T> on List<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) f) sync* {
    var i = 0;
    for (final item in this) {
      yield f(i++, item);
    }
  }
} 