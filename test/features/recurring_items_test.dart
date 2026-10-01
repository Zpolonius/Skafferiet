import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/recurrence.dart';
import 'package:skafferiet/core/models/recurring_item.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/edit_grocery_item_dialog.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_item_sheet.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_repository.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_screen.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_service.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

// Torsdag 1. oktober 2026 kl. 10.
final _now = DateTime(2026, 10, 1, 10);

/// Falsk repository: husker kald i stedet for at skrive til Firestore.
class FakeRecurringRepository implements RecurringItemsRepository {
  final created = <({RecurringItem item, String? link})>[];
  final updated = <RecurringItem>[];
  final deleted = <String>[];
  final processed = <String>[];
  final weekdayChanges = <({int weekday, Map<String, DateTime> dates})>[];
  final failFor = <String>{};
  Completer<void>? blockProcessing;
  final controller = StreamController<List<RecurringItem>>.broadcast();
  List<RecurringItem> items = [];

  @override
  Stream<List<RecurringItem>> watch(String householdId) async* {
    yield items;
    yield* controller.stream;
  }

  @override
  Future<void> create(String householdId, RecurringItem item,
      {String? linkGroceryItemId}) async {
    created.add((item: item, link: linkGroceryItemId));
  }

  @override
  Future<void> update(String householdId, RecurringItem item) async =>
      updated.add(item);

  @override
  Future<void> delete(String householdId, String id) async => deleted.add(id);

  @override
  Future<void> setShoppingWeekday(String householdId, int weekday,
      Map<String, DateTime> newNextDates) async {
    weekdayChanges.add((weekday: weekday, dates: newNextDates));
  }

  @override
  Future<void> processOccurrence(String householdId, String recurringId,
      {required DateTime today, required DateTime now}) async {
    processed.add(recurringId);
    if (blockProcessing != null) await blockProcessing!.future;
    if (failFor.contains(recurringId)) throw Exception('offline');
  }
}

RecurringItem _recurring(
  String id, {
  Recurrence recurrence = const WeeklyRecurrence(1),
  required DateTime nextDate,
}) =>
    RecurringItem(
      id: id,
      name: 'Vare $id',
      quantity: '1',
      unit: 'stk',
      category: 'Andet',
      recurrence: recurrence,
      nextDate: nextDate,
      createdBy: 'uid',
      createdAt: DateTime(2026, 9, 1),
    );

const _draft = RecurringItemDraft(
  name: 'Mælk',
  quantity: '2',
  unit: 'l',
  category: 'Mejeri',
  recurrence: WeeklyRecurrence(1),
);

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState>
    with Mock
    implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

class _GroceryNotifier extends StreamNotifier<List<GroceryItem>>
    with Mock
    implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => Stream.value(const []);
}

class _UpdatingGroceryNotifier extends StreamNotifier<List<GroceryItem>>
    with Mock
    implements GroceryListNotifier {
  final updatedNames = <String>[];

  @override
  Stream<List<GroceryItem>> build() => Stream.value(const []);

  @override
  Future<void> updateItem(String id,
      {required String name,
      required String quantity,
      required String? unit,
      required String category}) async {
    updatedNames.add(name);
  }
}

void main() {
  group('RecurringItemsService', () {
    late FakeRecurringRepository repo;
    late RecurringItemsService service;

    setUp(() {
      repo = FakeRecurringRepository();
      service = RecurringItemsService(repo, now: () => _now);
    });

    test('ny ugentlig vare starter på næste indkøbsdag', () async {
      await service.create('h1', _draft,
          shoppingWeekday: DateTime.saturday, createdBy: 'uid');
      final item = repo.created.single.item;
      expect(item.nextDate, DateTime(2026, 10, 3));
      expect(item.createdBy, 'uid');
      expect(item.name, 'Mælk');
      expect(repo.created.single.link, isNull);
    });

    test('ny månedlig vare starter på næste forekomst af datoen', () async {
      await service.create(
        'h1',
        const RecurringItemDraft(
          name: 'Sodavand',
          quantity: '1',
          category: 'Andet',
          recurrence: MonthlyRecurrence(1),
        ),
        shoppingWeekday: null,
        createdBy: 'uid',
      );
      expect(repo.created.single.item.nextDate, DateTime(2026, 11, 1));
    });

    test('vare fra indkøbslisten linkes', () async {
      await service.create('h1', _draft,
          shoppingWeekday: DateTime.saturday,
          createdBy: 'uid',
          linkGroceryItemId: 'g1');
      expect(repo.created.single.link, 'g1');
    });

    test('redigering uden nyt interval beholder datoen', () async {
      final existing = _recurring('r1', nextDate: DateTime(2026, 10, 10));
      await service.update('h1', existing, _draft,
          shoppingWeekday: DateTime.saturday);
      expect(repo.updated.single.nextDate, DateTime(2026, 10, 10));
      expect(repo.updated.single.name, 'Mælk');
    });

    test('nyt interval starter forfra fra næste indkøbsdag', () async {
      final existing = _recurring('r1',
          recurrence: const WeeklyRecurrence(4),
          nextDate: DateTime(2026, 10, 24));
      await service.update('h1', existing, _draft,
          shoppingWeekday: DateTime.saturday);
      expect(repo.updated.single.nextDate, DateTime(2026, 10, 3));
    });

    test('skift af indkøbsdag flytter kun ugentlige varer', () async {
      await service.changeShoppingWeekday('h1', DateTime.friday, [
        _recurring('weekly', nextDate: DateTime(2026, 10, 10)),
        _recurring('monthly',
            recurrence: const MonthlyRecurrence(15),
            nextDate: DateTime(2026, 10, 15)),
      ]);
      final change = repo.weekdayChanges.single;
      expect(change.weekday, DateTime.friday);
      expect(change.dates, {'weekly': DateTime(2026, 10, 9)});
    });

    test('ensureShoppingWeekday gemmer kun når husstanden mangler en dag',
        () async {
      expect(
          await service.ensureShoppingWeekday('h1',
              current: DateTime.monday, chosen: DateTime.friday, items: []),
          DateTime.monday);
      expect(repo.weekdayChanges, isEmpty);

      expect(
          await service.ensureShoppingWeekday('h1',
              current: null, chosen: DateTime.friday, items: []),
          DateTime.friday);
      expect(repo.weekdayChanges.single.weekday, DateTime.friday);
    });

    test('processDue behandler kun forfaldne varer', () async {
      await service.processDue('h1', [
        _recurring('i-morgen', nextDate: DateTime(2026, 10, 2)), // forfalden
        _recurring('overstaaet', nextDate: DateTime(2026, 9, 20)), // forfalden
        _recurring('lørdag', nextDate: DateTime(2026, 10, 3)), // ikke endnu
      ]);
      expect(repo.processed, ['i-morgen', 'overstaaet']);
    });

    test('én fejl (fx offline) stopper ikke de andre', () async {
      repo.failFor.add('a');
      await service.processDue('h1', [
        _recurring('a', nextDate: DateTime(2026, 10, 1)),
        _recurring('b', nextDate: DateTime(2026, 10, 1)),
      ]);
      expect(repo.processed, ['a', 'b']);
    });

    test('kald under en kørsel køres bagefter i stedet for samtidig', () async {
      repo.blockProcessing = Completer<void>();
      final first = service
          .processDue('h1', [_recurring('a', nextDate: DateTime(2026, 10, 1))]);
      await Future<void>.delayed(Duration.zero);
      // Andet kald mens det første venter – må ikke starte parallelt.
      await service
          .processDue('h1', [_recurring('b', nextDate: DateTime(2026, 10, 1))]);
      expect(repo.processed, ['a']);

      repo.blockProcessing!.complete();
      await first;
      expect(repo.processed, ['a', 'b']);
    });
  });

  group('UI', () {
    late FakeRecurringRepository repo;

    Widget app(Widget child, {int? shoppingWeekday}) {
      final user = _MockUser();
      when(() => user.uid).thenReturn('uid-1');
      return ProviderScope(
        overrides: [
          recurringItemsRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(() => _now),
          authProvider
              .overrideWith((ref) => _MockAuthNotifier(AuthState(user: user))),
          householdProvider.overrideWith((ref) => _MockHouseholdNotifier(
                HouseholdState(
                    householdId: 'h1', shoppingWeekday: shoppingWeekday),
              )),
          groceryListProvider.overrideWith(() => _GroceryNotifier()),
        ],
        child: MaterialApp(home: child),
      );
    }

    /// Telefonstørrelse (411×914), så hele sheetet er synligt.
    void phoneSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
    }

    /// Scroller til elementet først – som brugeren ville gøre.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      // Luk tastaturet, ellers scroller det fokuserede felt sig tilbage.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester tester, {int? shoppingWeekday}) async {
      phoneSize(tester);
      await tester.pumpWidget(app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RecurringItemSheet.show(context),
              child: const Text('Åbn'),
            ),
          ),
        ),
        shoppingWeekday: shoppingWeekday,
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();
    }

    setUp(() => repo = FakeRecurringRepository());

    testWidgets('ny fast vare kræver navn', (tester) async {
      await openSheet(tester, shoppingWeekday: DateTime.saturday);
      await tapVisible(tester, find.text('Gem fast vare'));
      expect(find.text('Navn må ikke være tomt'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('uden indkøbsdag skal den vælges, og den gemmes for husstanden',
        (tester) async {
      await openSheet(tester);

      await tester.enterText(find.byKey(const Key('recurring_name')), 'Mælk');
      await tapVisible(tester, find.text('Gem fast vare'));
      expect(find.text('Vælg jeres indkøbsdag'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tapVisible(tester, find.text('Lør'));
      expect(
          find.text('Kommer på indkøbslisten i morgen '
              '(dagen før indkøb lør. 3. okt.)'),
          findsOneWidget);

      await tapVisible(tester, find.text('Gem fast vare'));
      expect(repo.weekdayChanges.single.weekday, DateTime.saturday);
      final created = repo.created.single.item;
      expect(created.name, 'Mælk');
      expect(created.createdBy, 'uid-1');
      expect(created.nextDate, DateTime(2026, 10, 3));
      expect(find.text('Ny fast vare'), findsNothing); // sheet lukket
    });

    testWidgets('månedlig viser datovælger og forhåndsvisning', (tester) async {
      await openSheet(tester, shoppingWeekday: DateTime.saturday);

      await tapVisible(tester, find.text('Hver måned'));
      expect(find.byKey(const Key('recurrence_day_of_month')), findsOneWidget);
      // Den 1. → 1. nov.; lægges på listen dagen før, lør. 31. okt.
      expect(find.textContaining('lør. 31. okt.'), findsOneWidget);
    });

    testWidgets(
        'vare fra listen: ingen enhed bevares og for lang mængde forklares',
        (tester) async {
      phoneSize(tester);
      final grocery = GroceryItem(
        id: 'g1',
        name: 'Hvidløg',
        category: 'Grønt',
        quantity: '0.3333333333',
        source: 'recipe',
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  RecurringItemSheet.show(context, fromGroceryItem: grocery),
              child: const Text('Åbn'),
            ),
          ),
        ),
        shoppingWeekday: DateTime.saturday,
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget); // ingen enhed, ikke "stk"
      await tapVisible(tester, find.text('Gem fast vare'));
      expect(find.text('Højst 10 tegn'), findsOneWidget);
      expect(repo.created, isEmpty);

      await tester.enterText(find.byKey(const Key('recurring_quantity')), '1');
      await tapVisible(tester, find.text('Gem fast vare'));
      expect(repo.created.single.link, 'g1');
      expect(repo.created.single.item.unit, isNull);
    });

    testWidgets('stop fast genkøb kræver bekræftelse', (tester) async {
      final item = _recurring('r1', nextDate: DateTime(2026, 10, 3));
      phoneSize(tester);
      await tester.pumpWidget(app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RecurringItemSheet.show(context, existing: item),
              child: const Text('Åbn'),
            ),
          ),
        ),
        shoppingWeekday: DateTime.saturday,
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Stop fast genkøb'));
      await tester.tap(find.text('Annuller'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);

      await tapVisible(tester, find.text('Stop fast genkøb'));
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['r1']);
    });

    testWidgets('oversigten viser indkøbsdag og varer', (tester) async {
      repo.items = [
        _recurring('r1', nextDate: DateTime(2026, 10, 3)),
        _recurring('r2',
            recurrence: const MonthlyRecurrence(15),
            nextDate: DateTime(2026, 10, 15)),
      ];
      await tester.pumpWidget(app(const RecurringItemsScreen(),
          shoppingWeekday: DateTime.saturday));
      await tester.pumpAndSettle();

      expect(find.text('Lørdag'), findsOneWidget);
      expect(find.textContaining('fredag – dagen før'), findsOneWidget);
      expect(find.text('Vare r1'), findsOneWidget);
      expect(find.text('På listen i morgen'), findsOneWidget);
      expect(find.text('1 stk · Hver måned d. 15.'), findsOneWidget);
    });

    testWidgets('tom oversigt viser forklaring', (tester) async {
      await tester.pumpWidget(app(const RecurringItemsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Ingen faste varer endnu'), findsOneWidget);
      expect(find.text('Ikke valgt'), findsOneWidget);
    });

    testWidgets('skift indkøbsdag fra oversigten', (tester) async {
      repo.items = [_recurring('r1', nextDate: DateTime(2026, 10, 3))];
      await tester.pumpWidget(app(const RecurringItemsScreen(),
          shoppingWeekday: DateTime.saturday));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skift'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fredag'));
      await tester.pumpAndSettle();
      expect(repo.weekdayChanges.single.weekday, DateTime.friday);
      expect(repo.weekdayChanges.single.dates, {'r1': DateTime(2026, 10, 2)});
    });

    testWidgets('"Tilføj vare" kan gemme som fast vare', (tester) async {
      phoneSize(tester);
      await tester.pumpWidget(app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) => const AddGroceryItemSheet(),
              ),
              child: const Text('Åbn'),
            ),
          ),
        ),
        shoppingWeekday: DateTime.saturday,
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      expect(find.text('Tilføj til liste'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '  Mælk  ');
      await tapVisible(tester, find.byKey(const Key('add_repeat_switch')));
      expect(find.text('Gem som fast vare'), findsOneWidget);

      await tapVisible(tester, find.text('Hver 2. uge'));
      await tapVisible(tester, find.text('Gem som fast vare'));

      final created = repo.created.single.item;
      expect(created.name, 'Mælk'); // trimmet
      expect(created.recurrence, const WeeklyRecurrence(2));
      expect(created.nextDate, DateTime(2026, 10, 3));
      expect(
          find.text(
              'Mælk er gemt som fast vare – første gang på listen: i morgen'),
          findsOneWidget);
    });

    testWidgets('rediger-dialogen tilbyder fast genkøb', (tester) async {
      Object? result;
      final item = GroceryItem(
        id: 'g1',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(app(Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<Object?>(
              context: context,
              builder: (_) => EditGroceryItemDialog(item: item),
            ),
            child: const Text('Åbn'),
          ),
        ),
      )));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Køb fast (gentag automatisk)'));
      await tester.pumpAndSettle();
      expect(result, isA<ManageRecurringRequest>());
      expect((result as ManageRecurringRequest).item.name, 'Mælk');
    });

    testWidgets('ugemte rettelser gemmes før fast genkøb', (tester) async {
      Object? result;
      final grocery = _UpdatingGroceryNotifier();
      final item = GroceryItem(
        id: 'g1',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [groceryListProvider.overrideWith(() => grocery)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Object?>(
                  context: context,
                  builder: (_) => EditGroceryItemDialog(item: item),
                ),
                child: const Text('Åbn'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit_name')), 'Letmælk');
      await tester.tap(find.text('Køb fast (gentag automatisk)'));
      await tester.pumpAndSettle();
      expect(grocery.updatedNames, ['Letmælk']);
      expect((result as ManageRecurringRequest).item.name, 'Letmælk');
    });

    test('skift af husstand nulstiller indkøbsdagen', () {
      final state = HouseholdState(householdId: 'a', shoppingWeekday: 6);
      expect(state.copyWith(householdId: 'b').shoppingWeekday, 6);
      expect(
          state
              .copyWith(householdId: 'b', clearShoppingWeekday: true)
              .shoppingWeekday,
          isNull);
    });
  });
}
