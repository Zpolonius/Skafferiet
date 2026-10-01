import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:skafferiet/core/models/board_note.dart';
import 'package:skafferiet/features/board/board_note_card.dart';
import 'package:skafferiet/features/board/board_screen.dart';

import 'board_test_helpers.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('da_DK', null));

  Future<void> pumpBoard(WidgetTester tester, FakeBoardRepository repo, {String uid = 'me'}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: boardOverrides(repo, uid: uid),
      child: const MaterialApp(home: BoardScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openMenuOf(WidgetTester tester, String noteText) async {
    final card = find.ancestor(of: find.text(noteText), matching: find.byType(BoardNoteCard));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('Flere valg')));
    await tester.pumpAndSettle();
  }

  testWidgets('tom tavle viser tom-tilstand med knap', (tester) async {
    await pumpBoard(tester, FakeBoardRepository());
    expect(find.text('Tavlen er tom'), findsOneWidget);
    expect(find.text('Sæt en seddel op'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('sedler vises med forfatter', (tester) async {
    await pumpBoard(
        tester,
        FakeBoardRepository([
          textNote('1', text: 'Min seddel'),
          textNote('2', author: 'other', text: 'Oles seddel'),
          textNote('3', author: 'gone', text: 'Gammel seddel'),
        ]));
    expect(find.text('Min seddel'), findsOneWidget);
    expect(find.text('Dig'), findsOneWidget);
    expect(find.text('Ole'), findsOneWidget);
    expect(find.text('Tidligere medlem'), findsOneWidget);
    expect(find.text('Ny seddel'), findsOneWidget);
  });

  testWidgets('Slet vises kun på egne sedler for almindelige medlemmer', (tester) async {
    await pumpBoard(
        tester,
        FakeBoardRepository([
          textNote('1', text: 'Min seddel'),
          textNote('2', author: 'other', text: 'Oles seddel'),
        ]));

    await openMenuOf(tester, 'Oles seddel');
    expect(find.text('Fastgør øverst'), findsOneWidget);
    expect(find.text('Slet'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await openMenuOf(tester, 'Min seddel');
    expect(find.text('Slet'), findsOneWidget);
  });

  testWidgets('admin kan slette andres sedler', (tester) async {
    await pumpBoard(
        tester, FakeBoardRepository([textNote('2', author: 'other', text: 'Oles seddel')]),
        uid: 'boss');
    await openMenuOf(tester, 'Oles seddel');
    expect(find.text('Slet'), findsOneWidget);
  });

  testWidgets('sletning kræver bekræftelse', (tester) async {
    final repo = FakeBoardRepository([textNote('1', text: 'Min seddel')]);
    await pumpBoard(tester, repo);

    await openMenuOf(tester, 'Min seddel');
    await tester.tap(find.text('Slet'));
    await tester.pumpAndSettle();
    expect(find.text('Slet seddel?'), findsOneWidget);

    await tester.tap(find.text('Annuller'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);

    await openMenuOf(tester, 'Min seddel');
    await tester.tap(find.text('Slet'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Slet'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['1']);
    expect(find.text('Sedlen er slettet'), findsOneWidget);
  });

  testWidgets('fastgør fra menuen', (tester) async {
    final repo = FakeBoardRepository([textNote('1', text: 'Min seddel')]);
    await pumpBoard(tester, repo);
    await openMenuOf(tester, 'Min seddel');
    await tester.tap(find.text('Fastgør øverst'));
    await tester.pumpAndSettle();
    expect(repo.pinned, [(noteId: '1', isPinned: true)]);
  });

  testWidgets('fejl ved skrivning vises som besked', (tester) async {
    final repo = FakeBoardRepository([textNote('1', text: 'Min seddel')])
      ..failWith = Exception('offline');
    await pumpBoard(tester, repo);
    await openMenuOf(tester, 'Min seddel');
    await tester.tap(find.text('Fastgør øverst'));
    await tester.pumpAndSettle();
    expect(find.text('Kunne ikke opdatere sedlen'), findsOneWidget);
  });

  testWidgets('tryk på et punkt i en tjekliste krydser det af', (tester) async {
    final repo = FakeBoardRepository([
      ChecklistNote(
        id: 'c',
        authorId: 'other',
        createdAt: DateTime.now(),
        title: 'Weekend',
        items: const ['Kul', 'Pølser'],
        done: const {0},
      ),
    ]);
    await pumpBoard(tester, repo);
    expect(find.text('1 af 2 klaret'), findsOneWidget);
    await tester.tap(find.text('Pølser'));
    await tester.pumpAndSettle();
    expect(repo.done.single.noteId, 'c');
    expect(repo.done.single.done, {0, 1});
  });

  testWidgets('ny tekstseddel: knappen er slået fra, indtil der er tekst', (tester) async {
    final repo = FakeBoardRepository([textNote('1')]);
    await pumpBoard(tester, repo);

    await tester.tap(find.text('Ny seddel'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Sæt på tavlen');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('board_text_field')), '  Husk nøgler  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((repo.added.single.note as TextNote).text, 'Husk nøgler');
    expect(find.text('Sæt på tavlen'), findsNothing, reason: 'sheetet lukker');
    expect(find.text('Sedlen er sat op'), findsOneWidget);
  });

  testWidgets('ny seddel: fejl ved gem vises i sheetet, som forbliver åbent', (tester) async {
    final repo = FakeBoardRepository([textNote('1')])..failWith = Exception('offline');
    await pumpBoard(tester, repo);
    await tester.tap(find.text('Ny seddel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('board_text_field')), 'Hej');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sæt på tavlen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kunne ikke gemme sedlen'), findsOneWidget);
    expect(find.text('Sæt på tavlen'), findsOneWidget);
  });

  testWidgets('ny tjekliste kræver overskrift og mindst ét punkt', (tester) async {
    final repo = FakeBoardRepository([textNote('1')]);
    await pumpBoard(tester, repo);
    await tester.tap(find.text('Ny seddel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste'));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Sæt på tavlen');
    await tester.enterText(
        find.widgetWithText(TextField, 'Overskrift, fx "Husk til weekenden"'), 'Weekend');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Punkt 1'), 'Kul');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final note = repo.added.single.note as ChecklistNote;
    expect(note.title, 'Weekend');
    expect(note.items, ['Kul']);
  });

  testWidgets('punkter kan tilføjes og fjernes uden at blande indholdet', (tester) async {
    final repo = FakeBoardRepository([textNote('1')]);
    await pumpBoard(tester, repo);
    await tester.tap(find.text('Ny seddel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Overskrift, fx "Husk til weekenden"'), 'Indkøb');
    await tester.enterText(find.widgetWithText(TextField, 'Punkt 1'), 'Mælk');
    await tester.enterText(find.widgetWithText(TextField, 'Punkt 2'), 'Æg');
    await tester.tap(find.text('Tilføj punkt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Punkt 3'), 'Smør');

    // Fjern det første punkt – de to andre skal blive stående.
    await tester.tap(find.byTooltip('Fjern punkt').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Mælk'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sæt på tavlen'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sæt på tavlen'));
    await tester.pumpAndSettle();
    expect((repo.added.single.note as ChecklistNote).items, ['Æg', 'Smør']);
  });

  group('boardTimeLabel', () {
    final now = DateTime(2026, 10, 1, 15);
    test('i dag, i går og ældre', () {
      expect(boardTimeLabel(DateTime(2026, 10, 1, 9, 5), now: now), 'I dag kl. 9:05');
      expect(boardTimeLabel(DateTime(2026, 9, 30, 21, 30), now: now), 'I går kl. 21:30');
      expect(boardTimeLabel(DateTime(2026, 9, 3), now: now), startsWith('3. sep'));
    });
  });
}
