import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/recurrence.dart';
import 'package:skafferiet/core/models/recurring_item.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_repository.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

GroceryItem _item(String name, String category,
        {String quantity = '500',
        String? unit = 'g',
        String source = 'manual'}) =>
    GroceryItem(
      id: 'x',
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
      source: source,
      createdAt: DateTime(2026),
    );

void main() {
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

  group('historik skrives når varer tilføjes og redigeres', () {
    test('addItem gemmer en historikpost som overlever at listen tømmes',
        () async {
      await container.read(groceryListProvider.future);
      final n = container.read(groceryListProvider.notifier);
      await n.addItem(_item('Hakket oksekød', 'Kød'));
      await n.clearAllItems();

      final doc = await history().doc('hakket oksekød').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['name'], 'Hakket oksekød');
      expect(doc.data()!['category'], 'Kød');
      expect(doc.data()!['unit'], 'g');
      expect(doc.data()!['quantity'], '500');
      expect(doc.data()!['useCount'], 1);
      expect(doc.data()!['lastUsed'], isNotNull);
      expect(
          (await fs
                  .collection('households')
                  .doc('h1')
                  .collection('grocery_list')
                  .get())
              .docs,
          isEmpty);
    });

    test('samme vare igen tæller useCount op og bruger seneste stavemåde',
        () async {
      await container.read(groceryListProvider.future);
      final n = container.read(groceryListProvider.notifier);
      await n.addItem(_item('hakket oksekød', 'Kød'));
      await n.addItem(
          _item('Hakket  Oksekød', 'Frost', quantity: '1', unit: 'pk'));

      final snap = await history().get();
      expect(snap.docs, hasLength(1));
      final d = snap.docs.single.data();
      expect(d['useCount'], 2);
      expect(d['name'], 'Hakket Oksekød');
      expect(d['category'], 'Frost');
      expect(d['unit'], 'pk');
    });

    test('updateItem opdaterer historikken', () async {
      await container.read(groceryListProvider.future);
      final n = container.read(groceryListProvider.notifier);
      await fs
          .collection('households')
          .doc('h1')
          .collection('grocery_list')
          .doc('g1')
          .set(_item('Mælk', 'Mejeri').toMap());
      await n.updateItem('g1',
          name: 'Letmælk', quantity: '2', unit: 'l', category: 'Mejeri');
      final doc = await history().doc('letmælk').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['useCount'], 1);
    });

    test('tomt navn skriver ingen historik', () async {
      await container.read(groceryListProvider.future);
      await container
          .read(groceryListProvider.notifier)
          .addItem(_item('   ', 'Kød'));
      expect((await history().get()).docs, isEmpty);
    });

    test('sletning og tømning af listen rører ikke historikken', () async {
      await container.read(groceryListProvider.future);
      final n = container.read(groceryListProvider.notifier);
      await n.addItem(_item('Smør', 'Mejeri'));
      final id = (await fs
              .collection('households')
              .doc('h1')
              .collection('grocery_list')
              .get())
          .docs
          .single
          .id;
      await n.removeItem(id);
      expect((await history().get()).docs, hasLength(1));
    });
  });

  test('en fast vare der lægges på listen noteres også i historikken',
      () async {
    final item = RecurringItem(
      id: 'r1',
      name: 'Toiletpapir',
      quantity: '1',
      unit: 'pk',
      category: 'Andet',
      recurrence: const WeeklyRecurrence(1),
      nextDate: DateTime(2026, 10, 2),
      createdBy: 'me',
      createdAt: DateTime(2026, 9, 1),
    );
    await fs
        .collection('households')
        .doc('h1')
        .collection('recurring_items')
        .doc('r1')
        .set(item.toMap());
    await FirestoreRecurringItemsRepository(firestore: fs).processOccurrence(
      'h1',
      'r1',
      today: DateTime(2026, 10, 2),
      now: DateTime(2026, 10, 2, 9),
    );
    final groceries = await fs
        .collection('households')
        .doc('h1')
        .collection('grocery_list')
        .get();
    expect(groceries.docs, hasLength(1));
    final doc = await history().doc('toiletpapir').get();
    expect(doc.data()!['useCount'], 1);
    expect(doc.data()!['category'], 'Andet');
    expect(doc.data()!['unit'], 'pk');
  });

  group('forslag i Tilføj vare', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AddGroceryItemSheet()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('viser forslag efter listen er tømt og udfylder felterne',
        (tester) async {
      await history().doc('hakket oksekød').set({
        'name': 'Hakket oksekød',
        'category': 'Kød',
        'unit': 'g',
        'quantity': '500',
        'useCount': 3,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField).first, 'hak');
      await tester.pumpAndSettle();
      expect(find.text('Hakket oksekød'), findsWidgets);
      final suggestion =
          find.byKey(const ValueKey('suggestion_hakket oksekød'));
      expect(suggestion, findsOneWidget);
      expect(tester.getSize(suggestion).height, greaterThanOrEqualTo(48));

      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      final name = tester.widget<TextField>(find.byType(TextField).first);
      expect(name.controller!.text, 'Hakket oksekød');
      expect(find.byKey(const ValueKey('suggestion_hakket oksekød')),
          findsNothing);
      final chip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Kød'));
      expect(chip.selected, isTrue);
    });

    testWidgets('en forslag kan fjernes og kommer ikke igen', (tester) async {
      await history().doc('æbler').set({
        'name': 'Æbler',
        'category': 'Grønt',
        'useCount': 1,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField).first, 'æb');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suggestion_æbler')), findsOneWidget);

      await tester.tap(find.byTooltip('Fjern forslag'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('suggestion_æbler')), findsNothing);
      expect((await history().doc('æbler').get()).exists, isFalse);
    });

    testWidgets('egne kategorier fra historikken vises som chips',
        (tester) async {
      await history().doc('babymos').set({
        'name': 'Babymos',
        'category': 'Baby',
        'useCount': 1,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await pumpSheet(tester);
      expect(find.widgetWithText(ChoiceChip, 'Baby'), findsOneWidget);
    });
  });
}
