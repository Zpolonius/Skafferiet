// Grænsetilfælde for varehistorikken (#28): skriveren, matchningen og
// "Tilføj vare"-arket.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/services/item_history_writer.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

ItemHistoryEntry _e(String name, {int useCount = 1, DateTime? lastUsed}) =>
    ItemHistoryEntry(
      key: itemHistoryKey(name)!,
      name: name,
      category: 'Andet',
      useCount: useCount,
      lastUsed: lastUsed,
    );

void main() {
  // FieldValue-fabrikken skal være fake_cloud_firestore's, før skriveren
  // bygger FieldValue.increment i de rene tests nedenfor.
  setUpAll(FakeFirebaseFirestore.new);

  group('skriverens grænser (skal matche firestore.rules)', () {
    test('opskriftsmængder som double.toString() droppes, ikke afvises', () {
      for (final q in [(1 / 3).toString(), 1e-7.toString(), 1e21.toString()]) {
        final e = ItemHistoryWriter.entry(
            name: 'Mel', category: 'Kolonial', unit: 'g', quantity: q);
        expect(e, isNotNull, reason: q);
        final stored = e!.data['quantity'] as String?;
        expect(stored == null || stored.length <= 10, isTrue, reason: q);
      }
    });

    test('for lang enhed droppes, tom kategori/for langt navn springes over',
        () {
      expect(
          ItemHistoryWriter.entry(name: 'X', category: 'K', unit: 'u' * 21)!
              .data['unit'],
          isNull);
      expect(ItemHistoryWriter.entry(name: 'X', category: '   '), isNull);
      expect(ItemHistoryWriter.entry(name: 'X', category: 'k' * 41), isNull);
      expect(ItemHistoryWriter.entry(name: 'n' * 81, category: 'K'), isNull);
      // 40 emoji = 80 UTF-16-enheder: accepteres (reglerne tæller ikke flere).
      expect(
          ItemHistoryWriter.entry(name: '🥩' * 40, category: 'K'), isNotNull);
      expect(ItemHistoryWriter.entry(name: '🥩' * 41, category: 'K'), isNull);
    });

    test('ord-separator-navne giver gyldige nøgler', () {
      for (final n in ['/', '//', '.', '..', '__', '___', '__a__', ' ./. ']) {
        final k = itemHistoryKey(n)!;
        expect(k.contains('/'), isFalse);
        expect(k == '.' || k == '..', isFalse);
        expect(RegExp(r'^__.*__$').hasMatch(k), isFalse, reason: n);
      }
    });
  });

  group('matchning', () {
    final all = [
      _e('Oksekød'),
      _e('Østers'),
      _e('Æbler'),
      _e('Aal'),
    ];
    List<String> names(String q) =>
        suggestItems(all, q).map((e) => e.name).toList();

    test('ø matcher ikke o, æ ikke a, og omvendt', () {
      expect(names('ø'), ['Østers']);
      expect(names('o'), ['Oksekød']);
      expect(names('æ'), ['Æbler']);
      expect(names('a'), ['Aal']);
      expect(names('ÆB'), ['Æbler']);
    });

    test('ventende serverTimestamp (lastUsed null) giver ingen fejl', () {
      final list = [
        _e('Mælk a', useCount: 2),
        _e('Mælk b', useCount: 2, lastUsed: DateTime(2026)),
        _e('Mælk c', useCount: 3),
      ];
      expect(suggestItems(list, 'mæl').map((e) => e.name),
          ['Mælk c', 'Mælk b', 'Mælk a']);
    });

    test('fromMap tåler useCount som double (fx fra andre klienter)', () {
      final e = ItemHistoryEntry.fromMap('x', {
        'name': 'X',
        'category': 'K',
        'useCount': 2.0,
      });
      expect(e, isNotNull);
    });
  });

  group('ark', () {
    late FakeFirebaseFirestore fs;
    late ProviderContainer container;
    CollectionReference<Map<String, dynamic>> history() =>
        fs.collection('households').doc('h1').collection('item_history');

    setUp(() {
      fs = FakeFirebaseFirestore();
      container = ProviderContainer(overrides: [
        householdProvider.overrideWith((ref) => _Household()),
        groceryListProvider
            .overrideWith(() => GroceryListNotifier(firestore: fs)),
        itemHistoryRepositoryProvider
            .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
      ]);
      addTearDown(container.dispose);
    });

    Future<void> pump(WidgetTester tester, {double keyboard = 0}) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
              child: const Scaffold(
                resizeToAvoidBottomInset: false,
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: AddGroceryItemSheet(),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'enhed fra historikken som ikke er standard vælges uden crash, '
        'og varen kan tilføjes med 5 forslag + tastatur oppe', (tester) async {
      for (var i = 0; i < 6; i++) {
        await history().doc('mel $i').set({
          'name': 'Mel $i',
          'category': i == 0 ? 'Kolonial' : 'Andet',
          'unit': i == 0 ? 'dåse' : null,
          'quantity': i == 0 ? '2' : null,
          'useCount': 10 - i,
          'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
        });
      }
      await pump(tester, keyboard: 300);
      await tester.enterText(find.byType(TextField).first, 'mel');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fjern forslag'), findsNWidgets(5));
      expect(find.bySemanticsLabel(RegExp(r'^Brug tidligere vare: Mel 0')),
          findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const ValueKey('suggestion_mel 0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('suggestion_mel 0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('dåse'), findsOneWidget);
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Kolonial'))
              .selected,
          isTrue);

      final add = find.text('Tilføj til liste');
      await tester.scrollUntilVisible(add, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final g = await fs
          .collection('households')
          .doc('h1')
          .collection('grocery_list')
          .get();
      expect(g.docs.single.data(), containsPair('unit', 'dåse'));
      expect(g.docs.single.data(), containsPair('category', 'Kolonial'));
      expect(g.docs.single.data(), containsPair('quantity', '2'));
      expect((await history().doc('mel 0').get()).data()!['useCount'], 11);
    });

    testWidgets('det fulde navn skrevet skjuler forslaget', (tester) async {
      await history().doc('æbler').set({
        'name': 'Æbler',
        'category': 'Grønt',
        'useCount': 1,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'æbler ');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fjern forslag'), findsNothing);
    });
  });

  test('en vare med for langt navn kommer stadig på listen', () async {
    final fs = FakeFirebaseFirestore();
    final c = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
    ]);
    addTearDown(c.dispose);
    await c.read(groceryListProvider.future);
    await c.read(groceryListProvider.notifier).addItem(GroceryItem(
          id: 'x',
          name: 'n' * 200,
          category: 'k' * 100,
          quantity: '0.3333333333333333',
          unit: 'u' * 30,
          source: 'recipe',
          createdAt: DateTime(2026),
        ));
    expect((await fs.collection('households/h1/grocery_list').get()).docs,
        hasLength(1));
    expect((await fs.collection('households/h1/item_history').get()).docs,
        isEmpty);
  });
}
