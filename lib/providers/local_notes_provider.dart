import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/local_note_model.dart';

final localNotesProvider =
    NotifierProvider<LocalNotesNotifier, List<LocalNoteModel>>(
  LocalNotesNotifier.new,
);

class LocalNotesNotifier extends Notifier<List<LocalNoteModel>> {
  static const _indexFileName = 'local_notes_index.json';

  @override
  List<LocalNoteModel> build() => [];

  /// Persists the note to disk and adds it to the in-memory list.
  Future<void> addNote(LocalNoteModel note) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${note.id}.txt');
    await file.writeAsString(note.content);

    state = [note, ...state];
    await _persistIndex();
  }

  /// Removes the note from disk and the in-memory list.
  Future<void> removeNote(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$id.txt');
    if (await file.exists()) await file.delete();

    state = state.where((n) => n.id != id).toList();
    await _persistIndex();
  }

  /// Loads all saved notes from the index file into memory.
  Future<void> loadFromDisk() async {
    final dir = await getApplicationDocumentsDirectory();
    final indexFile = File('${dir.path}/$_indexFileName');
    if (!await indexFile.exists()) return;

    final json = jsonDecode(await indexFile.readAsString()) as List;
    state = json
        .map((e) => LocalNoteModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _persistIndex() async {
    final dir = await getApplicationDocumentsDirectory();
    final indexFile = File('${dir.path}/$_indexFileName');
    final json = state.map((n) => n.toMap()).toList();
    await indexFile.writeAsString(jsonEncode(json));
  }
}
