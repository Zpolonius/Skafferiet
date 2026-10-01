import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/board_note.dart';
import 'package:skafferiet/core/providers/board_repository_provider.dart';
import 'package:skafferiet/core/services/board_repository.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

/// Falsk lager til opslagstavlen. Fordi provideren kun kender det abstrakte
/// [BoardRepository], kan testene bruge denne i stedet for Firestore.
class FakeBoardRepository implements BoardRepository {
  FakeBoardRepository([List<BoardNote> initial = const []]) {
    _notes = [...initial];
  }

  late List<BoardNote> _notes;
  final _controller = StreamController<List<BoardNote>>.broadcast();

  final watched = <String>[];
  final added = <({String householdId, BoardNote note})>[];
  final pinned = <({String noteId, bool isPinned})>[];
  final done = <({String noteId, Set<int> done})>[];
  final deleted = <String>[];
  final discarded = <String>[];
  Object? failWith;

  void emit(List<BoardNote> notes) {
    _notes = [...notes];
    _controller.add(_notes);
  }

  @override
  Stream<List<BoardNote>> watchNotes(String householdId) async* {
    watched.add(householdId);
    yield _notes;
    yield* _controller.stream;
  }

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> addNote(String householdId, BoardNote note) async {
    _maybeFail();
    added.add((householdId: householdId, note: note));
  }

  @override
  Future<void> setPinned(String householdId, String noteId, bool isPinned) async {
    _maybeFail();
    pinned.add((noteId: noteId, isPinned: isPinned));
  }

  @override
  Future<void> setChecklistDone(String householdId, String noteId, Set<int> doneSet) async {
    _maybeFail();
    done.add((noteId: noteId, done: doneSet));
  }

  @override
  Future<void> deleteNote(String householdId, BoardNote note) async {
    _maybeFail();
    deleted.add(note.id);
  }

  @override
  Future<void> deleteImage(String imageUrl) async => discarded.add(imageUrl);
}

class MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  MockAuthNotifier(super.state);
}

class MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  MockHouseholdNotifier(super.state);
}

class MockUser extends Mock implements User {}

MockUser userWithUid(String uid) {
  final user = MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

/// Standard-overrides: bruger `me` i husstand `h1`, hvor `boss` er admin.
List<Override> boardOverrides(
  FakeBoardRepository repo, {
  String? uid = 'me',
  String? householdId = 'h1',
  String adminUid = 'boss',
  Map<String, String> memberNames = const {'me': 'Mette', 'other': 'Ole', 'boss': 'Bente'},
}) {
  return [
    boardRepositoryProvider.overrideWithValue(repo),
    authProvider.overrideWith(
      (ref) => MockAuthNotifier(AuthState(user: uid == null ? null : userWithUid(uid))),
    ),
    householdProvider.overrideWith(
      (ref) => MockHouseholdNotifier(HouseholdState(
        householdId: householdId,
        adminUid: adminUid,
        memberNames: memberNames,
      )),
    ),
  ];
}

TextNote textNote(String id,
    {String author = 'me', int minutesAgo = 0, bool pinned = false, String? text}) {
  return TextNote(
    id: id,
    authorId: author,
    createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    isPinned: pinned,
    text: text ?? 'Seddel $id',
  );
}
