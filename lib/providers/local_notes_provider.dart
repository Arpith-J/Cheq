import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// The app documents directory, cached after first lookup.
  Future<Directory> get _dir => getApplicationDocumentsDirectory();

  /// Persists the note to disk and adds it to the in-memory list.
  /// For text notes the [note.content] string is written as-is.
  /// For drawing notes the caller must store the compressed image bytes
  /// at the [note.filePath] before calling this method; only the index
  /// is updated here.
  Future<void> addNote(LocalNoteModel note) async {
    final dir = await _dir;

    if (note.type == NoteType.text) {
      final file = File('${dir.path}/${note.id}.txt');
      await file.writeAsString(note.content);
    }

    state = [note, ...state];
    await _persistIndex();
  }

  /// Updates a note in-place. For text notes the underlying .txt file is
  /// also rewritten so the on-disk content stays in sync.
  Future<void> updateNote(LocalNoteModel updated) async {
    final dir = await _dir;

    if (updated.type == NoteType.text) {
      final file = File('${dir.path}/${updated.id}.txt');
      await file.writeAsString(updated.content);
    }

    state = [
      for (final n in state)
        if (n.id == updated.id) updated else n,
    ];
    await _persistIndex();
  }

  /// Removes the note from disk and the in-memory list.
  Future<void> removeNote(String id) async {
    final dir = await _dir;
    final note = state.firstWhere((n) => n.id == id, orElse: () => state.first);

    // Delete the text file (if it exists)
    final txtFile = File('${dir.path}/$id.txt');
    if (await txtFile.exists()) await txtFile.delete();

    // Delete the drawing image file (if it exists)
    if (note.filePath != null) {
      final imgFile = File(note.filePath!);
      if (await imgFile.exists()) await imgFile.delete();
    }

    state = state.where((n) => n.id != id).toList();
    await _persistIndex();
  }

  /// Returns the raw bytes for a drawing note, or `null` for text notes.
  Future<Uint8List?> readDrawingBytes(LocalNoteModel note) async {
    if (note.type != NoteType.drawing || note.filePath == null) return null;
    final file = File(note.filePath!);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Loads all saved notes from the index file into memory.
  Future<void> loadFromDisk() async {
    final dir = await _dir;
    final indexFile = File('${dir.path}/$_indexFileName');
    if (!await indexFile.exists()) return;

    final json = jsonDecode(await indexFile.readAsString()) as List;
    state = json
        .map((e) => LocalNoteModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _persistIndex() async {
    final dir = await _dir;
    final indexFile = File('${dir.path}/$_indexFileName');
    final json = state.map((n) => n.toMap()).toList();
    await indexFile.writeAsString(jsonEncode(json));
  }
}
