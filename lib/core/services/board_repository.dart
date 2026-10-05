import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/board_note.dart';

/// Læseadgang til opslagstavlen (ISP: forhåndsvisningen på Hjem behøver
/// kun at kunne læse).
abstract class BoardReader {
  /// Live-strøm af husstandens sedler, usorteret.
  Stream<List<BoardNote>> watchNotes(String householdId);
}

/// Skriveadgang til opslagstavlen.
abstract class BoardWriter {
  Future<void> addNote(String householdId, BoardNote note);
  Future<void> setPinned(String householdId, String noteId, bool isPinned);
  Future<void> setChecklistDone(String householdId, String noteId, Set<int> done);

  /// Sletter sedlen og, for billedsedler, billedet i Storage.
  Future<void> deleteNote(String householdId, BoardNote note);

  /// Sletter et uploadet billede, der aldrig blev til en seddel.
  Future<void> deleteImage(String imageUrl);
}

/// Kontrakt for opslagstavlens lager (DIP: provideren kender kun denne).
abstract class BoardRepository implements BoardReader, BoardWriter {}

/// Firestore/Storage-implementering. Sedler ligger i
/// `households/{householdId}/board_notes`.
class FirestoreBoardRepository implements BoardRepository {
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseStorage? _storageOverride;

  FirestoreBoardRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestoreOverride = firestore,
        _storageOverride = storage;

  // Hentes først ved brug, så repository'et kan oprettes uden Firebase
  // (fx i widget-tests, hvor der ikke er nogen husstand).
  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _notes(String householdId) =>
      _firestore.collection('households').doc(householdId).collection('board_notes');

  /// Højst så mange sedler hentes, så tavlen ikke bliver dyr og langsom
  /// efter lang tids brug.
  static const int maxNotes = 100;

  @override
  Stream<List<BoardNote>> watchNotes(String householdId) {
    return _notes(householdId)
        .orderBy('createdAt', descending: true)
        .limit(maxNotes)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BoardNote.fromMap(doc.data(), doc.id))
            .whereType<BoardNote>()
            .toList());
  }

  @override
  Future<void> addNote(String householdId, BoardNote note) {
    return _notes(householdId).add(note.toMap());
  }

  @override
  Future<void> setPinned(String householdId, String noteId, bool isPinned) {
    return _notes(householdId).doc(noteId).update({'isPinned': isPinned});
  }

  @override
  Future<void> setChecklistDone(String householdId, String noteId, Set<int> done) {
    return _notes(householdId).doc(noteId).update({'done': done.toList()..sort()});
  }

  @override
  Future<void> deleteNote(String householdId, BoardNote note) async {
    await _notes(householdId).doc(note.id).delete();
    if (note is PhotoNote) await deleteImage(note.imageUrl);
  }

  @override
  Future<void> deleteImage(String imageUrl) async {
    // Bedste forsøg: sedlen er væk uanset hvad, og et efterladt billede er
    // stadig kun synligt for husstanden (storage.rules).
    try {
      await _storage.refFromURL(imageUrl).delete();
    } catch (_) {}
  }
}
