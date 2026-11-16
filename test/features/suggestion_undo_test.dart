import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/quick_add_field.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

/// Repo hvor serveren aldrig svarer (offline): skrivninger hænger, strømmen
/// viser kun det lokale. Kan få skrivninger til at fejle.
class _OfflineRepo implements ItemHistoryRepository {
  final List<ItemHistoryEntry> entries;
  bool failRemove = false;
  bool failRestore = false;
  bool hang = true;
  int restores = 0;
  final removeCompleter = Completer<void>();
  final removed = <String>[];
  _OfflineRepo(this.entries);

  @override
  Stream<List<ItemHistoryEntry>> watch(String householdId) async* {
    yield entries;
    await Completer<void>().future;
  }

  @override
  Future<void> remove(String householdId, String key) {
    removed.add(key);
    if (failRemove) return Future.error(Exception('permission-denied'));
    return hang ? removeCompleter.future : Future.value();
  }

  @override
  Future<void> restore(String householdId, ItemHistoryEntry entry) {
    restores++;
    if (failRestore) return Future.error(Exception('unavailable'));
    return hang ? Completer<void>().future : Future.value();
  }
}

/// "Fortryd" ved fjernelse af et forslag (#47), i både hurtig-tilføj og
/// "Tilføj vare"-arket.
void main() {
  late FakeFirebaseFirestore fs;
  late ProviderContainer container;

  DocumentReference<Map<String, dynamic>> doc(String key) =>
      fs.collection('households').doc('h1').collection('item_history').doc(key);

  final kaffeLastUsed = DateTime(2026, 5, 1, 12);

  Future<void> seed() async {
    await doc('kaffe').set({
      'name': 'Kaffe',
      'category': 'Kolonial',
      'unit': 'pk',
      'quantity': '2',
      'useCount': 7,
      'lastUsed': Timestamp.fromDate(kaffeLastUsed),
    });
    await doc('kakao').set({
      'name': 'Kakao',
      'category': 'Kolonial',
      'useCount': 3,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 2)),
    });
  }

  void makeContainer([ItemHistoryRepository? repo]) {
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider.overrideWithValue(
          repo ?? FirestoreItemHistoryRepository(firestore: fs)),
    ]);
    addTearDown(container.dispose);
  }

  setUp(() {
    fs = FakeFirebaseFirestore();
    makeContainer();
  });

  Future<void> pumpQuickAdd(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(child: QuickAddField()),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Åbner "Tilføj vare" som et rigtigt modalt ark (root-navigator), så vi
  /// kan se om SnackBaren er synlig OVER arket.
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppBottomSheet<bool>(
                context: context,
                builder: (_) => const AddGroceryItemSheet(),
              ),
              child: const Text('åbn'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('åbn'));
    await tester.pumpAndSettle();
  }

  Finder suggestion(String key) => find.byKey(ValueKey('suggestion_$key'));

  Future<void> typeKa(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
  }

  /// Rækkefølgen af forslagene (top til bund).
  List<String> order(WidgetTester tester) {
    final keys = ['kaffe', 'kakao']..sort((a, b) => tester
        .getTopLeft(suggestion(a))
        .dy
        .compareTo(tester.getTopLeft(suggestion(b)).dy));
    return keys;
  }

  group('hurtig-tilføj', () {
    testWidgets(
        '× viser "Forslag fjernet" med Fortryd, og Fortryd genskaber '
        'posten med samme felter og placering', (tester) async {
      await seed();
      await pumpQuickAdd(tester);
      await typeKa(tester);
      expect(order(tester), ['kaffe', 'kakao']);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      expect(suggestion('kaffe'), findsNothing);
      expect(find.text('Forslag fjernet'), findsOneWidget);
      expect(find.text('Fortryd'), findsOneWidget);
      await tester.pumpAndSettle();
      expect((await doc('kaffe').get()).exists, isFalse);

      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Fortryd'));
      await tester.pump();
      expect(suggestion('kaffe'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(order(tester), ['kaffe', 'kakao']);
      expect((await doc('kaffe').get()).data(), {
        'name': 'Kaffe',
        'category': 'Kolonial',
        'unit': 'pk',
        'quantity': '2',
        'useCount': 7,
        'lastUsed': Timestamp.fromDate(kaffeLastUsed),
      });
    });
  });

  group('Tilføj vare-arket', () {
    testWidgets('SnackBaren er synlig over arket og Fortryd kan trykkes',
        (tester) async {
      await seed();
      await pumpSheet(tester);
      await typeKa(tester);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(suggestion('kaffe'), findsNothing);
      final text = find.text('Forslag fjernet');
      expect(text, findsOneWidget);
      // Tryktest: det øverste element på SnackBarens position er SnackBaren
      // selv (ikke arkets bagvedliggende Scaffold eller barrieren).
      expect(text.hitTestable(), findsOneWidget);
      expect(find.text('Fortryd').hitTestable(), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(suggestion('kaffe'), findsOneWidget);
      expect(order(tester), ['kaffe', 'kakao']);
      expect((await doc('kaffe').get()).data()!['useCount'], 7);
    });
  });

  final kaffe = ItemHistoryEntry(
    key: 'kaffe',
    name: 'Kaffe',
    category: 'Kolonial',
    unit: 'pk',
    quantity: '2',
    useCount: 7,
    lastUsed: DateTime(2026, 5, 1, 12),
  );
  final kakao = ItemHistoryEntry(
    key: 'kakao',
    name: 'Kakao',
    category: 'Kolonial',
    useCount: 3,
    lastUsed: DateTime(2026, 5, 2),
  );

  group('offline og fejl', () {
    testWidgets(
        'offline: fjern og fortryd opdaterer skærmen med det samme uden at '
        'vente på serveren', (tester) async {
      final repo = _OfflineRepo([kaffe, kakao]);
      makeContainer(repo);
      await pumpQuickAdd(tester);
      await typeKa(tester);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      expect(suggestion('kaffe'), findsNothing);
      expect(find.text('Forslag fjernet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Fortryd'));
      await tester.pump();
      expect(suggestion('kaffe'), findsOneWidget);
      expect(order(tester), ['kaffe', 'kakao']);
      expect(repo.removed, ['kaffe']);
      expect(repo.restores, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Ingen fejlbesked mens serveren tier.
      expect(find.text('Kunne ikke fortryde. Prøv igen.'), findsNothing);
    });

    testWidgets('mislykkes sletningen, er forslaget tilbage og SnackBaren væk',
        (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])..failRemove = true;
      makeContainer(repo);
      await pumpQuickAdd(tester);
      await typeKa(tester);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pumpAndSettle();
      expect(suggestion('kaffe'), findsOneWidget);
      expect(find.text('Forslag fjernet'), findsNothing);
    });

    testWidgets('mislykkes fortryd, vises "Kunne ikke fortryde" med Prøv igen',
        (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])
        ..hang = false
        ..failRestore = true;
      makeContainer(repo);
      await pumpQuickAdd(tester);
      await typeKa(tester);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(find.text('Kunne ikke fortryde. Prøv igen.'), findsOneWidget);
      expect(find.text('Prøv igen'), findsOneWidget);
      // Forslaget blev ikke gemt, så det vises ikke som om det var det.
      expect(suggestion('kaffe'), findsNothing);

      repo.failRestore = false;
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Prøv igen'));
      await tester.pumpAndSettle();
      expect(repo.restores, 2);
      expect(suggestion('kaffe'), findsOneWidget);
    });

    testWidgets('et nyt × erstatter den forrige SnackBar', (tester) async {
      final repo = _OfflineRepo([kaffe, kakao]);
      makeContainer(repo);
      await pumpQuickAdd(tester);
      await typeKa(tester);

      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Forslag fjernet'), findsOneWidget);
      expect(find.text('Fortryd'), findsOneWidget);
    });

    testWidgets('i arket: mislykket fortryd vises synligt i arket',
        (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])
        ..hang = false
        ..failRestore = true;
      makeContainer(repo);
      await pumpSheet(tester);
      await typeKa(tester);
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(find.text('Kunne ikke fortryde. Prøv igen.').hitTestable(),
          findsOneWidget);
    });
  });

  group('Fortryd rører ikke nyere data og eksisterende data', () {
    Future<void> removeAndUndo(WidgetTester tester,
        {Future<void> Function()? between}) async {
      await pumpQuickAdd(tester);
      await typeKa(tester);
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pumpAndSettle();
      await between?.call();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'varen er tilføjet igen i mellemtiden: tælleren lægges oveni og '
        'lastUsed flyttes ikke bagud', (tester) async {
      await seed();
      final newer = Timestamp.fromDate(DateTime(2026, 6, 1));
      await removeAndUndo(tester, between: () async {
        // En anden i husstanden køber kaffe igen: ny post med useCount 1.
        await doc('kaffe').set({
          'name': 'Kaffe',
          'category': 'Kolonial',
          'unit': 'g',
          'quantity': '500',
          'useCount': 1,
          'lastUsed': newer,
        });
      });
      final d = (await doc('kaffe').get()).data()!;
      expect(d['useCount'], 8); // 1 (ny) + 7 (fortrudt), aldrig under 7
      expect(d['lastUsed'], newer);
      // Den nyere enhed/mængde bevares.
      expect((d['unit'], d['quantity']), ('g', '500'));
    });

    testWidgets('en nyere post med ældre lastUsed får den oprindelige tid',
        (tester) async {
      await seed();
      await removeAndUndo(tester, between: () async {
        await doc('kaffe').set({
          'name': 'Kaffe',
          'category': 'Kolonial',
          'useCount': 1,
          'lastUsed': Timestamp.fromDate(DateTime(2020)),
        });
      });
      final d = (await doc('kaffe').get()).data()!;
      expect(d['lastUsed'], Timestamp.fromDate(kaffeLastUsed));
      expect(d['useCount'], 8);
    });

    testWidgets(
        'gammel post med ekstra felt og uden unit/quantity: efter fjern + '
        'fortryd er den en gyldig post med de seks felter', (tester) async {
      await doc('kaffe').set({
        'name': 'Kaffe',
        'category': 'Kolonial',
        'useCount': 4,
        'lastUsed': Timestamp.fromDate(kaffeLastUsed),
        'legacyField': 'gammelt',
      });
      await removeAndUndo(tester);
      final d = (await doc('kaffe').get()).data()!;
      expect(d.keys.toSet(),
          {'name', 'category', 'unit', 'quantity', 'useCount', 'lastUsed'});
      expect((d['unit'], d['quantity']), (null, null));
      expect(d['useCount'], 4);
      expect(d['lastUsed'], Timestamp.fromDate(kaffeLastUsed));
    });

    testWidgets(
        'post uden useCount og lastUsed fås tilbage som gyldig post '
        '(useCount 1, lastUsed nu)', (tester) async {
      await doc('kaffe').set({'name': 'Kaffe', 'category': 'Kolonial'});
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await removeAndUndo(tester);
      final d = (await doc('kaffe').get()).data()!;
      expect(d['useCount'], 1);
      expect(d['lastUsed'], isA<Timestamp>());
      expect((d['lastUsed'] as Timestamp).toDate().isAfter(before), isTrue);
    });
  });

  test(
      'restore: en post med lastUsed null (ventende skrivning) skrives med et '
      'tidsstempel', () async {
    final repo = FirestoreItemHistoryRepository(firestore: fs);
    await repo.restore(
        'h1',
        const ItemHistoryEntry(
            key: 'te', name: 'Te', category: 'Kolonial', useCount: 2));
    final d = (await doc('te').get()).data()!;
    expect(d['lastUsed'], isA<Timestamp>());
    expect(d['useCount'], 2);
  });

  group('arket lukkes mens SnackBaren vises (fund 2)', () {
    Future<void> removeThenClose(WidgetTester tester,
        {bool undoFirst = false}) async {
      await pumpSheet(tester);
      await typeKa(tester);
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      if (undoFirst) {
        await tester.tap(find.text('Fortryd'));
        await tester.pump();
      }
      Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();
      await tester.pumpAndSettle();
    }

    testWidgets('SnackBaren flyttes til roden, vises én gang og Fortryd virker',
        (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])..hang = false;
      makeContainer(repo);
      await removeThenClose(tester);
      expect(find.text('Forslag fjernet'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(repo.restores, 1);
      expect(find.text('Forslag fjernet'), findsNothing);
    });

    testWidgets(
        'fejler fortryd fra den flyttede SnackBar, vises beskeden i '
        'roden med Prøv igen', (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])
        ..hang = false
        ..failRestore = true;
      makeContainer(repo);
      await removeThenClose(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(find.text('Kunne ikke fortryde. Prøv igen.'), findsOneWidget);
      expect(find.text('Prøv igen'), findsOneWidget);
      repo.failRestore = false;
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Prøv igen'));
      await tester.pumpAndSettle();
      expect(repo.restores, 2);
    });

    testWidgets(
        'en bekræftelse i roden skjules ikke; den flyttede SnackBar køes bag '
        'den og Fortryd virker bagefter', (tester) async {
      final repo = _OfflineRepo([kaffe, kakao])..hang = false;
      makeContainer(repo);
      await pumpSheet(tester);
      await typeKa(tester);
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // Som "gemt som fast vare": roden viser en bekræftelse, og arket lukkes.
      ScaffoldMessenger.of(tester.element(find.text('åbn')))
          .showSnackBar(const SnackBar(content: Text('Bekræftet')));
      Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Bekræftet'), findsOneWidget);
      expect(find.text('Forslag fjernet'), findsNothing);
      // Bekræftelsen får sin fulde tid (4 s), så følger "Forslag fjernet".
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Forslag fjernet'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();
      expect(repo.restores, 1);
    });

    testWidgets('allerede fortrudt: flyttes ikke igen', (tester) async {
      final repo = _OfflineRepo([kaffe, kakao]);
      makeContainer(repo);
      await removeThenClose(tester, undoFirst: true);
      expect(find.text('Forslag fjernet'), findsNothing);
      expect(repo.restores, 1);
    });

    testWidgets('afvist sletning efter lukning fjerner den flyttede SnackBar',
        (tester) async {
      final repo = _OfflineRepo([kaffe, kakao]);
      makeContainer(repo);
      await removeThenClose(tester);
      expect(find.text('Forslag fjernet'), findsOneWidget);
      repo.removeCompleter.completeError(Exception('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text('Forslag fjernet'), findsNothing);
    });
  });

  test('fejlet fortryd fjerner ikke en post der allerede er på listen igen',
      () async {
    final repo = _OfflineRepo([kaffe])
      ..hang = false
      ..failRestore = true;
    makeContainer(repo);
    final sub = container.listen(itemHistoryProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(itemHistoryProvider.future);
    // Posten er allerede på listen (tilføjet igen af en anden).
    await expectLater(
        container.read(itemHistoryProvider.notifier).restore(kaffe),
        throwsException);
    expect(container.read(itemHistoryProvider).value!.map((e) => e.key),
        ['kaffe']);
  });
}
