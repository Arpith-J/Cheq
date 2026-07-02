import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/planner_model.dart'; // Make sure this path matches your model file location

class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Helper getter to fetch the active user's subcollection reference safely
  CollectionReference<Map<String, dynamic>>? get _plannerRef {
    final user = _auth.currentUser;
    if (user == null) return null;
    
    // Points directly to: users -> [uid] -> planner
    return _db.collection('users').doc(user.uid).collection('planner');
  }

  /// 📤 STREAM: Real-time synchronization loop that listens for database changes
  Stream<List<PlannerModel>> streamPlannerEntries() {
    final ref = _plannerRef;
    if (ref == null) return Stream.value([]);

    return ref.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return PlannerModel.fromMap(doc.data());
      }).toList();
    });
  }

  /// ➕ CREATE / UPDATE: Uploads or overwrites a task document
  Future<void> saveTask(PlannerModel task) async {
    try {
      await _plannerRef?.doc(task.id).set(task.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ Failed to save task to Firestore: $e");
    }
  }

  /// ❌ DELETE: Removes a task document permanently from the cloud
  Future<void> deleteTask(String taskId) async {
    try {
      await _plannerRef?.doc(taskId).delete();
    } catch (e) {
      debugPrint("❌ Failed to delete task from Firestore: $e");
    }
  }
}