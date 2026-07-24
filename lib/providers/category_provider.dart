// lib/providers/category_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/category_model.dart';
import '../services/firestore_service.dart';

final categoryStreamProvider = StreamProvider.autoDispose<List<CategoryModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  
  return FirestoreService.instance.getUserCategories(user.uid);
});