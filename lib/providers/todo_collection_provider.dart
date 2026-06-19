// lib/providers/todo_collection_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class TodoItem {
  final String id;
  final String text;
  final bool isDone;

  const TodoItem({
    required this.id,
    required this.text,
    required this.isDone,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'isDone': isDone,
      };

  factory TodoItem.fromMap(Map<String, dynamic> map) => TodoItem(
        id: map['id'] as String,
        text: map['text'] as String,
        isDone: (map['isDone'] as bool?) ?? false,
      );

  TodoItem copyWith({bool? isDone}) =>
      TodoItem(id: id, text: text, isDone: isDone ?? this.isDone);
}

class TodoCollection {
  final String id;
  final String title;
  final DateTime createdAt;
  final bool isArchived;
  final List<TodoItem> items;
  final int coinsReward;

  const TodoCollection({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.isArchived,
    required this.items,
    required this.coinsReward,
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
      isArchived:  (data['isArchived'] as bool?) ?? false,
      items:       rawItems
          .map((e) => TodoItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      coinsReward: (data['coinsReward'] as int?) ?? 10,
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
    final userRef = db.collection('users').doc(uid);

    await db.runTransaction((tx) async {
      final snap = await tx.get(colRef);
      if (!snap.exists) return;
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
      int coinIncrement = 0;
      
      if (!currentStatus) {
        // ── Checking an item as DONE ────────────────────────────────────────
        // Rule: +5 for completing any item (whether it's an independent task or inside a list)
        coinIncrement += 5;
        
        // Rule: If it's a multi-item list and this action completes it, add +10 bonus
        if (!isTask && allDone) {
          coinIncrement += 10;
        }
      } else {
        // ── Unchecking an item to UNDONE ─────────────────────────────────────
        // Rule: Remove 5 coins for unchecking the item
        coinIncrement -= 5;
        
        // Rule: If it was a completed list, strip the 10 coin completion bonus too
        final wasArchived = data['isArchived'] as bool? ?? false;
        if (!isTask && wasArchived) {
          coinIncrement -= 10;
        }
      }

      tx.update(colRef, {'items': updated});

      if (allDone) {
        tx.update(colRef, {
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(), // Track completion time
        });
      }else{
        // Restores the card to active states if any single item is unchecked
        tx.update(colRef, {
          'isArchived': false,
          'archivedAt': FieldValue.delete(), // Clears completion time tracking
        });
      }
      if (coinIncrement != 0) {
        tx.update(userRef, {
          'coins': FieldValue.increment(coinIncrement),
        });
      }
    });
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