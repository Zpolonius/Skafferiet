import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
  // ignore: use_setters_to_change_properties
  void switchTo(String id) => state = HouseholdState(householdId: id);
}

void main() {
  late FakeFirebaseFirestore fs;
  late ProviderContainer container;

  CollectionReference<Map<String, dynamic>> groceries() =>
      fs.collection('households').doc('h1').collection('grocery_list');
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

  Future<void> pumpField(WidgetTester tester, {double width = 360}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
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

  Finder field() => find.byType(TextField);
  TextField textField(WidgetTester tester) => tester.widget(field());

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<List<Map<String, dynamic>>> stored() async =>
      (await groceries().get()).docs.map((d) => d.data()).toList();

  testWidgets('har pladsholder, add-ikon og skærmlæser-label', (tester) async {
    await pumpField(tester);
    expect(find.text('Tilføj vare…'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Tilføj vare')), findsWidgets);
    // Præcis én gang (ikke "Tilføj vare, Tilføj vare…").
    final node = tester.getSemantics(field());
    expect(node.label, 'Tilføj vare');
  });

  testWidgets('Enter tilføjer varen, tømmer feltet og beholder fokus',
      (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await submit(tester, 'brød');

    final items = await stored();
    expect(items, hasLength(1));
    expect(items.single['name'], 'Brød');
    expect(items.single['category'], 'Andet');
    expect(items.single['quantity'], '1');
    expect(items.single['unit'], 'stk');
    expect(items.single['source'], 'manual');
    expect(textField(tester).controller!.text, isEmpty);
    expect(textField(tester).focusNode!.hasFocus, isTrue);
    // Historikken skrives også.
    expect((await history().get()).docs, hasLength(1));
  });

  testWidgets('to varer i træk kun med tastaturet', (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await submit(tester, '2 l mælk');
    await submit(tester, 'brød');

    final items = await stored();
    expect(items.map((i) => i['name']), unorderedEquals(['Mælk', 'Brød']));
    final milk = items.firstWhere((i) => i['name'] == 'Mælk');
    expect((milk['quantity'], milk['unit']), ('2', 'l'));
    expect(textField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('tomt eller kun mellemrum tilføjer ingenting', (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await submit(tester, '');
    await submit(tester, '   ');
    expect(await stored(), isEmpty);
    expect((await history().get()).docs, isEmpty);
    expect(textField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('tilføj-knappen tilføjer også og beholder fokus', (tester) async {
    await pumpField(tester);
    await tester.enterText(field(), 'æg');
    await tester.pump();
    await tester.tap(find.byTooltip('Tilføj'));
    await tester.pumpAndSettle();
    expect((await stored()).single['name'], 'Æg');
    expect(textField(tester).controller!.text, isEmpty);
    expect(textField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('historik giver kategori, enhed og mængde', (tester) async {
    await history().doc('hakket oksekød').set({
      'name': 'Hakket oksekød',
      'category': 'Kød',
      'unit': 'g',
      'quantity': '500',
      'useCount': 3,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await pumpField(tester);
    await submit(tester, 'HAKKET oksekød');
    final item = (await stored()).single;
    expect(item['name'], 'Hakket oksekød');
    expect(item['category'], 'Kød');
    expect((item['quantity'], item['unit']), ('500', 'g'));
  });

  testWidgets('en vare tilføjet i denne session huskes til næste gang',
      (tester) async {
    await pumpField(tester);
    await submit(tester, '2 l mælk');
    await submit(tester, 'mælk');
    final milk = (await stored()).where((i) => i['name'] == 'Mælk').toList();
    expect(milk, hasLength(2));
    expect(milk.map((m) => m['unit']), everyElement('l'));
    expect(milk.map((m) => m['quantity']), everyElement('2'));
  });

  testWidgets('viser højst 5 forslag og et tryk tilføjer varen med det samme',
      (tester) async {
    for (var i = 0; i < 7; i++) {
      await history().doc('mad $i').set({
        'name': 'Mad $i',
        'category': 'Frost',
        'unit': 'pk',
        'quantity': '${i + 1}',
        'useCount': 10 - i,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
    }
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await tester.enterText(field(), 'ma');
    await tester.pumpAndSettle();
    expect(
        find.bySemanticsLabel(RegExp('Brug tidligere vare')), findsNWidgets(5));
    expect(find.byTooltip('Fjern forslag'), findsNWidgets(5));

    await tester
        .tap(find.bySemanticsLabel(RegExp('Brug tidligere vare: Mad 1,')));
    await tester.pumpAndSettle();
    final item = (await stored()).single;
    expect(item['name'], 'Mad 1');
    expect(item['category'], 'Frost');
    expect((item['quantity'], item['unit']), ('2', 'pk'));
    expect(textField(tester).controller!.text, isEmpty);
    expect(textField(tester).focusNode!.hasFocus, isTrue);
    expect(find.byTooltip('Fjern forslag'), findsNothing);
  });

  testWidgets('forslagsrækker er mindst 48 dp høje på 360 dp bredde',
      (tester) async {
    await history().doc('mælk').set({
      'name': 'Mælk',
      'category': 'Mejeri',
      'useCount': 1,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await pumpField(tester, width: 360);
    await tester.enterText(field(), 'mæ');
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('suggestion_mælk'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byTooltip('Flere valg')).height,
        greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flere valg åbner arket med navnet udfyldt og tømmer feltet',
      (tester) async {
    await pumpField(tester);
    await tester.enterText(field(), 'rugbrød');
    await tester.pump();
    await tester.tap(find.byTooltip('Flere valg'));
    await tester.pumpAndSettle();

    expect(find.byType(AddGroceryItemSheet), findsOneWidget);
    final sheetName = find
        .descendant(
            of: find.byType(AddGroceryItemSheet),
            matching: find.byType(TextField))
        .first;
    // Et nyt navn får stort begyndelsesbogstav, ens i hurtig-tilføj og arket.
    expect(tester.widget<TextField>(sheetName).controller!.text, 'Rugbrød');

    await tester.ensureVisible(find.text('Tilføj til liste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tilføj til liste'));
    await tester.pumpAndSettle();
    expect(find.byType(AddGroceryItemSheet), findsNothing);
    expect((await stored()).single['name'], 'Rugbrød');
    expect(textField(tester).controller!.text, isEmpty);
  });

  testWidgets('Flere valg lukket uden at tilføje beholder teksten',
      (tester) async {
    await pumpField(tester);
    await tester.enterText(field(), 'rugbrød');
    await tester.pump();
    await tester.tap(find.byTooltip('Flere valg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Luk'));
    await tester.pumpAndSettle();
    expect(textField(tester).controller!.text, 'rugbrød');
    expect(await stored(), isEmpty);
  });

  testWidgets('en fejl ved skrivning vises som SnackBar og feltet er tømt',
      (tester) async {
    container.dispose();
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => _FailingGroceryList(firestore: fs)),
      itemHistoryRepositoryProvider
          .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
    ]);
    addTearDown(container.dispose);
    await pumpField(tester);
    await submit(tester, 'brød');
    expect(find.text('Kunne ikke tilføje varen. Tjek din forbindelse.'),
        findsOneWidget);
    expect(textField(tester).controller!.text, isEmpty);
  });

  testWidgets('"Flere valg" for en kendt vare giver arket historikkens felter',
      (tester) async {
    await history().doc('mælk').set({
      'name': 'Mælk',
      'category': 'Mejeri',
      'unit': 'l',
      'quantity': '1',
      'useCount': 3,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await pumpField(tester);
    await tester.enterText(field(), 'mælk');
    await tester.pump();
    await tester.tap(find.byTooltip('Flere valg'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tilføj til liste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tilføj til liste'));
    await tester.pumpAndSettle();
    final item = (await stored()).single;
    expect(item['name'], 'Mælk');
    expect((item['category'], item['quantity'], item['unit']),
        ('Mejeri', '1', 'l'));
    final h = (await history().doc('mælk').get()).data()!;
    expect((h['category'], h['unit']), ('Mejeri', 'l'),
        reason: 'historikken må ikke overskrives med Grønt/stk');
  });

  testWidgets(
      '"Flere valg" bruger hele teksten som navn hvis historikken har den',
      (tester) async {
    await history().doc('2 minutes nudler').set({
      'name': '2 Minutes nudler',
      'category': 'Andet',
      'useCount': 1,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await pumpField(tester);
    await tester.enterText(field(), '2 minutes nudler');
    await tester.pump();
    await tester.tap(find.byTooltip('Flere valg'));
    await tester.pumpAndSettle();
    final sheetName = find
        .descendant(
            of: find.byType(AddGroceryItemSheet),
            matching: find.byType(TextField))
        .first;
    expect(tester.widget<TextField>(sheetName).controller!.text,
        '2 Minutes nudler');
  });

  for (final c in [('rugbrød', 'Rugbrød'), ('smør', 'SMØR')]) {
    testWidgets(
        'arket gemmer "${c.$1}" som "${c.$2}" (nyt navn stort, historikkens '
        'stavemåde bevares)', (tester) async {
      await history().doc('smør').set({
        'name': 'SMØR',
        'category': 'Mejeri',
        'useCount': 1,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
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
      await tester.enterText(find.byType(TextField).first, c.$1);
      await tester.pump();
      await tester.ensureVisible(find.text('Tilføj til liste'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tilføj til liste'));
      await tester.pumpAndSettle();
      expect((await stored()).single['name'], c.$2);
    });
  }

  group('historikken er live (#28 må ikke gå tilbage)', () {
    Future<void> seedRemote(String name, String category,
        {String household = 'h1'}) async {
      await fs
          .collection('households')
          .doc(household)
          .collection('item_history')
          .doc(itemHistoryKey(name))
          .set({
        'name': name,
        'category': category,
        'useCount': 1,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
    }

    testWidgets(
        'en vare en anden bruger efter listen er åbnet foreslås i feltet',
        (tester) async {
      await pumpField(tester);
      await seedRemote('Kaffe', 'Kolonial');
      await tester.enterText(field(), 'kaf');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsOneWidget);
    });

    testWidgets('og i arket "Tilføj vare" uden at forlade skærmen',
        (tester) async {
      await pumpField(tester);
      await seedRemote('Kaffe', 'Kolonial');
      await tester.tap(find.byTooltip('Flere valg'));
      await tester.pumpAndSettle();
      final sheetName = find
          .descendant(
              of: find.byType(AddGroceryItemSheet),
              matching: find.byType(TextField))
          .first;
      await tester.enterText(sheetName, 'kaf');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsOneWidget);
    });

    testWidgets('skift af husstand viser den nye husstands historik',
        (tester) async {
      final household = _Household();
      container.dispose();
      container = ProviderContainer(overrides: [
        householdProvider.overrideWith((ref) => household),
        groceryListProvider
            .overrideWith(() => GroceryListNotifier(firestore: fs)),
        itemHistoryRepositoryProvider
            .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
      ]);
      addTearDown(container.dispose);
      await seedRemote('Kaffe', 'Kolonial');
      await seedRemote('Kakao', 'Kolonial', household: 'h2');
      await pumpField(tester);
      await tester.enterText(field(), 'ka');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsOneWidget);
      household.switchTo('h2');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsNothing);
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kakao')),
          findsOneWidget);
    });

    testWidgets('fjern forslag er øjeblikkeligt og permanent', (tester) async {
      await seedRemote('Kaffe', 'Kolonial');
      await pumpField(tester);
      await tester.enterText(field(), 'ka');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fjern forslag'));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsNothing);
      await tester.pumpAndSettle();
      expect((await history().get()).docs, isEmpty);
    });

    testWidgets('en fejl i strømmen giver tom liste, ikke en fejlskærm',
        (tester) async {
      container.dispose();
      container = ProviderContainer(overrides: [
        householdProvider.overrideWith((ref) => _Household()),
        groceryListProvider
            .overrideWith(() => GroceryListNotifier(firestore: fs)),
        itemHistoryRepositoryProvider.overrideWithValue(_ErrorRepo()),
      ]);
      addTearDown(container.dispose);
      await pumpField(tester);
      await submit(tester, 'brød');
      expect((await stored()).single['name'], 'Brød');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('dobbelt-Enter lige efter hinanden giver én vare',
      (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.enterText(field(), 'brød');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await stored(), hasLength(1));
  });

  testWidgets('tastaturgenvej: Enter-tast på tastaturet virker også',
      (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await tester.enterText(field(), 'te');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await stored()).single['name'], 'Te');
  });
}

class _ErrorRepo implements ItemHistoryRepository {
  @override
  Stream<List<ItemHistoryEntry>> watch(String householdId) =>
      Stream.error(Exception('offline'));
  @override
  Future<void> remove(String householdId, String key) async {}
}

class _FailingGroceryList extends GroceryListNotifier {
  _FailingGroceryList({super.firestore});
  @override
  Future<void> addItem(item) async => throw Exception('offline');
}
