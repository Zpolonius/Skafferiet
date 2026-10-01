import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/board_note.dart';
import 'package:skafferiet/features/board/board_provider.dart';

import 'board_test_helpers.dart';

void main() {
  late FakeBoardRepository repo;

  ProviderContainer makeContainer({String? uid = 'me', String? householdId = 'h1'}) {
    final container = ProviderContainer(
      overrides: boardOverrides(repo, uid: uid, householdId: householdId),
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => repo = FakeBoardRepository());

  test('uden husstand er tavlen tom, og lageret spørges ikke', () async {
    final container = makeContainer(householdId: null);
    expect(await container.read(boardProvider.future), isEmpty);
    expect(repo.watched, isEmpty);
  });

  test('sedler sorteres med fastgjorte øverst og nyeste først', () async {
    repo = FakeBoardRepository([
      textNote('old', minutesAgo: 60),
      textNote('pinned', minutesAgo: 600, pinned: true),
      textNote('new', minutesAgo: 1),
    ]);
    final container = makeContainer();
    final notes = await container.read(boardProvider.future);
    expect(notes.map((n) => n.id), ['pinned', 'new', 'old']);
    expect(repo.watched, ['h1']);
  });

  test('addTextNote trimmer teksten og skriver i brugerens navn', () async {
    final container = makeContainer();
    await container.read(boardProvider.notifier).addTextNote('  Husk mælk  ');
    expect(repo.added, hasLength(1));
    expect(repo.added.single.householdId, 'h1');
    final note = repo.added.single.note as TextNote;
    expect(note.text, 'Husk mælk');
    expect(note.authorId, 'me');
    expect(note.isPinned, isFalse);
  });

  test('addTextNote afviser tom og for lang tekst uden at gemme', () async {
    final notifier = makeContainer().read(boardProvider.notifier);
    await expectLater(notifier.addTextNote('   '), throwsArgumentError);
    await expectLater(notifier.addTextNote('a' * 501), throwsArgumentError);
    expect(repo.added, isEmpty);
  });

  test('addChecklistNote fjerner tomme punkter', () async {
    await makeContainer()
        .read(boardProvider.notifier)
        .addChecklistNote(' Weekend ', ['Kul', '', '  Pølser ']);
    final note = repo.added.single.note as ChecklistNote;
    expect(note.title, 'Weekend');
    expect(note.items, ['Kul', 'Pølser']);
    expect(note.done, isEmpty);
  });

  test('addPhotoNote afviser billeder uden for Firebase Storage', () async {
    final notifier = makeContainer().read(boardProvider.notifier);
    await expectLater(
      notifier.addPhotoNote('https://evil.example.com/x.jpg'),
      throwsArgumentError,
    );
    await notifier.addPhotoNote(
      'https://firebasestorage.googleapis.com/v0/b/b/o/households%2Fh1%2Fboard%2Fa.jpg?alt=media',
      caption: ' Aftensmad ',
    );
    expect((repo.added.single.note as PhotoNote).caption, 'Aftensmad');
  });

  test('ikke logget ind: ingen skrivning', () async {
    final notifier = makeContainer(uid: null).read(boardProvider.notifier);
    await expectLater(notifier.addTextNote('Hej'), throwsStateError);
    expect(repo.added, isEmpty);
  });

  test('togglePin vender fastgørelsen', () async {
    final notifier = makeContainer().read(boardProvider.notifier);
    await notifier.togglePin(textNote('a'));
    await notifier.togglePin(textNote('b', pinned: true));
    expect(repo.pinned, [(noteId: 'a', isPinned: true), (noteId: 'b', isPinned: false)]);
  });

  test('toggleChecklistItem sender det nye sæt og ignorerer ugyldige indeks', () async {
    final note = ChecklistNote(
      id: 'c',
      authorId: 'other',
      createdAt: DateTime(2026),
      title: 't',
      items: const ['a', 'b'],
      done: const {0},
    );
    final notifier = makeContainer().read(boardProvider.notifier);
    await notifier.toggleChecklistItem(note, 1);
    await notifier.toggleChecklistItem(note, 5);
    expect(repo.done, hasLength(1));
    expect(repo.done.single.done, {0, 1});
  });

  test('forfatteren må slette sin seddel', () async {
    await makeContainer().read(boardProvider.notifier).deleteNote(textNote('mine'));
    expect(repo.deleted, ['mine']);
  });

  test('andre end forfatter og admin må ikke slette', () async {
    final notifier = makeContainer().read(boardProvider.notifier);
    await expectLater(notifier.deleteNote(textNote('x', author: 'other')), throwsStateError);
    expect(repo.deleted, isEmpty);
  });

  test('admin må slette andres sedler', () async {
    await makeContainer(uid: 'boss')
        .read(boardProvider.notifier)
        .deleteNote(textNote('x', author: 'other'));
    expect(repo.deleted, ['x']);
  });

  test('discardImage sender billedet videre til sletning', () async {
    await makeContainer().read(boardProvider.notifier).discardImage('https://x/y');
    expect(repo.discarded, ['https://x/y']);
  });
}
