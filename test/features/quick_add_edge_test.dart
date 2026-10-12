// Grænsetilfælde for hurtig-tilføj (#33): parsing, levende historik og
// sorteringstilstand.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/models/quick_add.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/grocery_screen.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/quick_add_field.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
  // ignore: use_setters_to_change_properties
  void switchTo(String id) => state = HouseholdState(householdId: id);
}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth() : super(AuthState());
}

/// Tæller abonnementer på strømmen og hvornår de opsiges.
class _CountingRepo implements ItemHistoryRepository {
  final FirestoreItemHistoryRepository inner;
  int watches = 0;
  int active = 0;
  int cancels = 0;
  _CountingRepo(this.inner);

  @override
  Stream<List<ItemHistoryEntry>> watch(String householdId) {
    watches++;
    late StreamController<List<ItemHistoryEntry>> c;
    StreamSubscription<List<ItemHistoryEntry>>? sub;
    c = StreamController(onListen: () {
      active++;
      sub = inner.watch(householdId).listen(c.add, onError: c.addError);
    }, onCancel: () async {
      active--;
      cancels++;
      await sub?.cancel();
    });
    return c.stream;
  }

  @override
  Future<void> remove(String householdId, String key) =>
      inner.remove(householdId, key);
}

/// Giver data, og så en fejl (fx permission-denied).
class _DataThenErrorRepo implements ItemHistoryRepository {
  final controller = StreamController<List<ItemHistoryEntry>>.broadcast();
  @override
  Stream<List<ItemHistoryEntry>> watch(String householdId) => controller.stream;
  @override
  Future<void> remove(String householdId, String key) async {}
}

bool _semanticsHasLabel(WidgetTester tester, String label) {
  var found = false;
  void visit(SemanticsNode n) {
    if (n.label.contains(label) &&
        !n.isInvisible &&
        n.getSemanticsData().flagsCollection.isTextField) {
      found = true;
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  final root = tester
      .renderObject(find.byType(MaterialApp))
      .owner!
      .semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return found;
}

void main() {
  group('parsing', () {
    final cases = <String, (String, String?, String?)>{
      '1.5 kg kartofler': ('kartofler', '1,5', 'kg'),
      '0.250 l fløde': ('fløde', '0,25', 'l'),
      '2 dl fløde': ('fløde', '2', 'dl'),
      '2 x mælk': ('mælk', '2', null),
      '2x mælk': ('mælk', '2', null),
      '1.000 g mel': ('mel', '1000', 'g'),
    };
    cases.forEach((input, want) {
      test(input, () {
        final p = parseQuickAdd(input);
        expect((p.name, p.quantity, p.unit), want);
      });
    });

    for (final input in [
      '1.500 kg kartofler',
      '1.250 kg kartofler',
      '3 x',
      '2 ×',
      'x mælk',
      '1.000.000.000 g x',
      '1.000.000.000.000.000.000.000.000 g x',
      '2 fl. vin',
      '1 bdt. persille',
    ]) {
      test('grænser: $input', () {
        final p = parseQuickAdd(input);
        expect(p.name.trim(), isNotEmpty);
        if (p.quantity != null) {
          expect(p.quantity!.length, lessThanOrEqualTo(10),
              reason: 'quantity ≤10 tegn (historikkens grænse)');
        }
      });
    }

    test('canonicalItemName ødelægger ikke bevidst stavemåde', () {});
  });

  late FakeFirebaseFirestore fs;
  late ProviderContainer container;
  late _CountingRepo repo;
  late _Household household;

  CollectionReference<Map<String, dynamic>> history() =>
      fs.collection('households').doc('h1').collection('item_history');
  CollectionReference<Map<String, dynamic>> groceries() =>
      fs.collection('households').doc('h1').collection('grocery_list');

  setUp(() {
    fs = FakeFirebaseFirestore();
    repo = _CountingRepo(FirestoreItemHistoryRepository(firestore: fs));
    household = _Household();
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => household),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pumpFieldAndFab(WidgetTester tester,
      {bool showField = true}) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
              child: showField ? const QuickAddField() : const SizedBox()),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => const AddGroceryItemSheet(),
              ),
              child: const Text('Tilføj vare'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'én lytter for felt + ark + mange tastetryk; opsiges ved unmount og '
      'husstandsskift', (tester) async {
    await pumpFieldAndFab(tester);
    for (final t in ['m', 'mæ', 'mæl', 'mælk', '2 l mælk']) {
      await tester.enterText(find.byType(TextField).first, t);
      await tester.pump();
    }
    await tester.tap(find.text('Tilføj vare'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find
            .descendant(
                of: find.byType(AddGroceryItemSheet),
                matching: find.byType(TextField))
            .first,
        'ka');
    await tester.pumpAndSettle();
    expect((repo.watches, repo.active), (1, 1));

    household.switchTo('h2');
    await tester.pumpAndSettle();
    expect((repo.watches, repo.active, repo.cancels), (2, 1, 1));

    // Luk arket og fjern feltet: lytteren opsiges (autoDispose).
    Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();
    await tester.pumpAndSettle();
    await pumpFieldAndFab(tester, showField: false);
    await tester.pumpAndSettle();
    expect(repo.active, 0);
  });

  testWidgets('fjernet forslag kommer ikke tilbage fra lytteren',
      (tester) async {
    await history().doc('kaffe').set({
      'name': 'Kaffe',
      'category': 'Kolonial',
      'useCount': 1,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await pumpFieldAndFab(tester);
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fjern forslag'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
          findsNothing,
          reason: 'flimmer i frame $i');
    }
    // Endnu en historikændring udløser et nyt øjebliksbillede.
    await history().doc('kakao').set({
      'name': 'Kakao',
      'category': 'Kolonial',
      'useCount': 1,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 2)),
    });
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kaffe')),
        findsNothing);
    expect(find.bySemanticsLabel(RegExp('Brug tidligere vare: Kakao')),
        findsOneWidget);
  });

  testWidgets(
      'en fejl i strømmen (permission-denied) giver en tom liste, ikke en fejl',
      (tester) async {
    final r = _DataThenErrorRepo();
    container.dispose();
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => household),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider.overrideWithValue(r),
    ]);
    addTearDown(container.dispose);
    await pumpFieldAndFab(tester);
    r.controller.add([
      ItemHistoryEntry(key: 'kaffe', name: 'Kaffe', category: 'Kolonial'),
    ]);
    await tester.pumpAndSettle();
    r.controller.addError(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pumpAndSettle();
    final s = container.read(itemHistoryProvider);
    expect(tester.takeException(), isNull);
    expect(s.hasError, isFalse);
    expect(s.valueOrNull, isEmpty);
  });

  group('sorteringstilstand (Offstage)', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await groceries().doc('a').set(GroceryItem(
            id: 'a',
            name: 'Æbler',
            category: 'Grønt',
            quantity: '1',
            unit: 'stk',
            source: GroceryItem.sourceManual,
            createdAt: DateTime(2026, 5, 1),
          ).toMap());
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth()),
          householdProvider.overrideWith((ref) => _Household()),
          groceryListProvider
              .overrideWith(() => GroceryListNotifier(firestore: fs)),
          itemHistoryRepositoryProvider
              .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
          recurringItemsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const GroceryScreen()),
      ));
      await tester.pumpAndSettle();
    }

    TextField quick(WidgetTester tester) =>
        tester.widget<TextField>(find.descendant(
            of: find.byType(QuickAddField, skipOffstage: false),
            matching: find.byType(TextField, skipOffstage: false)));

    testWidgets(
        'teksten overlever, men skjult felt har ikke fokus og fanger '
        'ikke Enter, og er usynligt for skærmlæser', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);
      final f = find.byType(TextField).first;
      await tester.tap(f);
      await tester.enterText(f, 'brød');
      await tester.pump();
      expect(quick(tester).focusNode!.hasFocus, isTrue);
      expect(_semanticsHasLabel(tester, 'Tilføj vare'), isTrue);

      await tester.tap(find.byTooltip('Sorter liste'));
      await tester.pumpAndSettle();
      final hidden = quick(tester);
      final hasFocus = hidden.focusNode!.hasFocus;
      final inSemantics = _semanticsHasLabel(tester, 'Tilføj vare');
      // Hardware-Enter / "Done" mens feltet er skjult:
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final docs = (await groceries().get()).docs;

      await tester.tap(find.byTooltip('Gem rækkefølge'));
      await tester.pumpAndSettle();
      expect(quick(tester).controller!.text, anyOf('brød', isEmpty));
      expect(inSemantics, isFalse, reason: 'skjult felt i semantiktræet');
      expect(hasFocus, isFalse, reason: 'skjult felt beholder fokus/tastatur');
      expect(docs, hasLength(1), reason: 'Enter i skjult felt tilføjede vare');
      handle.dispose();
    });
  });
}
