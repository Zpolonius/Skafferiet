import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/board_note.dart';
import '../../core/providers/board_repository_provider.dart';
import '../../core/services/board_repository.dart';
import '../auth/auth_provider.dart';
import '../profile/household_provider.dart';
import 'board_policy.dart';

/// Husstandens opslagstavle, sorteret med fastgjorte sedler øverst.
///
/// Kender kun det abstrakte [BoardRepository] – ikke Firestore.
class BoardNotifier extends StreamNotifier<List<BoardNote>> {
  @override
  Stream<List<BoardNote>> build() {
    final householdId = ref.watch(householdProvider.select((s) => s.householdId));
    if (householdId == null) return Stream.value(const []);

    return ref.watch(boardRepositoryProvider).watchNotes(householdId).map(BoardPolicy.sorted);
  }

  BoardWriter get _writer => ref.read(boardRepositoryProvider);

  /// Husstand og bruger, som en ændring kræver. Kaster [StateError], hvis
  /// brugeren ikke er logget ind eller ikke har en husstand.
  ({String householdId, String uid}) _context() {
    final householdId = ref.read(householdProvider).householdId;
    final uid = ref.read(authProvider).user?.uid;
    if (householdId == null || uid == null) {
      throw StateError('Ingen husstand');
    }
    return (householdId: householdId, uid: uid);
  }

  void _check(String? error) {
    if (error != null) throw ArgumentError(error);
  }

  Future<void> addTextNote(String text) async {
    _check(BoardPolicy.validateText(text));
    final ctx = _context();
    await _writer.addNote(
      ctx.householdId,
      TextNote(id: '', authorId: ctx.uid, createdAt: DateTime.now(), text: text.trim()),
    );
  }

  Future<void> addPhotoNote(String imageUrl, {String caption = ''}) async {
    _check(BoardPolicy.validateCaption(caption));
    if (!PhotoNote.isAllowedImageUrl(imageUrl)) {
      throw ArgumentError('Ugyldigt billede');
    }
    final ctx = _context();
    await _writer.addNote(
      ctx.householdId,
      PhotoNote(
        id: '',
        authorId: ctx.uid,
        createdAt: DateTime.now(),
        imageUrl: imageUrl,
        caption: caption.trim(),
      ),
    );
  }

  Future<void> addChecklistNote(String title, List<String> items) async {
    _check(BoardPolicy.validateChecklist(title, items));
    final ctx = _context();
    await _writer.addNote(
      ctx.householdId,
      ChecklistNote(
        id: '',
        authorId: ctx.uid,
        createdAt: DateTime.now(),
        title: title.trim(),
        items: BoardPolicy.cleanItems(items),
      ),
    );
  }

  Future<void> togglePin(BoardNote note) async {
    final ctx = _context();
    await _writer.setPinned(ctx.householdId, note.id, !note.isPinned);
  }

  Future<void> toggleChecklistItem(ChecklistNote note, int index) async {
    if (index < 0 || index >= note.items.length) return;
    final ctx = _context();
    await _writer.setChecklistDone(ctx.householdId, note.id, note.toggled(index));
  }

  /// Sletter en seddel. Kaster [StateError], hvis brugeren ikke må.
  Future<void> deleteNote(BoardNote note) async {
    final ctx = _context();
    final adminUid = ref.read(householdProvider).adminUid;
    if (!BoardPolicy.canDelete(note, currentUid: ctx.uid, adminUid: adminUid)) {
      throw StateError('Kun forfatteren eller husstandens admin kan slette sedlen');
    }
    await _writer.deleteNote(ctx.householdId, note);
  }

  /// Rydder op efter et billede, der blev uploadet men aldrig gemt.
  Future<void> discardImage(String imageUrl) => _writer.deleteImage(imageUrl);
}

final boardProvider = StreamNotifierProvider<BoardNotifier, List<BoardNote>>(BoardNotifier.new);
