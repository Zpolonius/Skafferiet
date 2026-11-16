import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

/// QA (#47, runde 3): kø i roden og Fortryd lige før arket lukkes.
void main() {
  late FakeFirebaseFirestore fs;
  late ProviderContainer container;

  DocumentReference<Map<String, dynamic>> doc(String key) =>
      fs.collection('households').doc('h1').collection('item_history').doc(key);

  setUp(() async {
    fs = FakeFirebaseFirestore();
    await doc('kaffe').set({
      'name': 'Kaffe',
      'category': 'Kolonial',
      'useCount': 7,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
    });
    await doc('kakao').set({
      'name': 'Kakao',
      'category': 'Kolonial',
      'useCount': 3,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 2)),
    });
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider
          .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pumpApp(WidgetTester tester) async {
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
  }

  Future<void> openAndRemove(WidgetTester tester, {int times = 1}) async {
    await tester.tap(find.text('åbn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byTooltip('Fjern forslag').first);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 600));
  }

  void popSheet(WidgetTester tester) =>
      Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();

  testWidgets(
      'Fortryd i arket og så luk med det samme: flyttes ikke, og useCount '
      'tælles ikke dobbelt', (tester) async {
    await pumpApp(tester);
    await openAndRemove(tester);
    await tester.tap(find.text('Fortryd'));
    await tester.pump();
    popSheet(tester);
    await tester.pumpAndSettle();
    expect(find.text('Forslag fjernet'), findsNothing,
        reason: 'allerede fortrudt, men flyttet til roden');
    expect((await doc('kaffe').get()).data()!['useCount'], 7);
  });

  testWidgets(
      'afvist sletning mens den flyttede bar står i kø bag en bekræftelse: '
      'bekræftelsen skjules ikke og ingen død Fortryd bliver tilbage',
      (tester) async {
    final repo = _RejectLater(fs);
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await pumpApp(tester);
    await openAndRemove(tester);
    final ctx = tester.element(find.byType(AddGroceryItemSheet));
    final root = ScaffoldMessenger.of(ctx);
    Navigator.pop(ctx, true);
    root.showSnackBar(const SnackBar(content: Text('Gemt som fast vare')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Gemt som fast vare'), findsOneWidget);
    repo.reject!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Gemt som fast vare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Forslag fjernet'), findsNothing);
  });

  Future<_RejectLater> useRejectLater() async {
    final repo = _RejectLater(fs);
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      groceryListProvider
          .overrideWith(() => GroceryListNotifier(firestore: fs)),
      itemHistoryRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    return repo;
  }

  testWidgets(
      'afvist sletning, så Fortryd mens baren glider ud: useCount forbliver 7',
      (tester) async {
    final repo = await useRejectLater();
    await pumpApp(tester);
    await openAndRemove(tester);
    repo.reject!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Baren er på vej ud men endnu i træet.
    expect(find.text('Fortryd'), findsOneWidget);
    await tester.tap(find.text('Fortryd'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect((await doc('kaffe').get()).data()!['useCount'], 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Fortryd trykket, baren væk, og SÅ afvises sletningen: ingen close() '
      'på en lukket bar (rammer ikke en anden bar)', (tester) async {
    final repo = await useRejectLater();
    await pumpApp(tester);
    await openAndRemove(tester);
    await tester.tap(find.text('Fortryd'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(AddGroceryItemSheet));
    final root = ScaffoldMessenger.of(ctx);
    Navigator.pop(ctx);
    await tester.pumpAndSettle();
    root.showSnackBar(const SnackBar(content: Text('Anden besked')));
    await tester.pump(const Duration(milliseconds: 500));
    repo.reject!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Anden besked'), findsOneWidget);
  });

  testWidgets(
      'hurtig-tilføj: Fortryd trykket, baren væk, så afvises sletningen: '
      'en anden bar i roden lukkes ikke', (tester) async {
    final repo = await useRejectLater();
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: QuickAddField()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fjern forslag').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Fortryd'));
    await tester.pumpAndSettle();
    final root =
        ScaffoldMessenger.of(tester.element(find.byType(QuickAddField)));
    root.showSnackBar(const SnackBar(content: Text('Anden besked')));
    await tester.pump(const Duration(milliseconds: 500));
    repo.reject!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Anden besked'), findsOneWidget);
  });
}

class _RejectLater extends FirestoreItemHistoryRepository {
  void Function()? reject;
  _RejectLater(FakeFirebaseFirestore fs) : super(firestore: fs);
  @override
  Future<void> remove(String householdId, String key) {
    final c = Completer<void>();
    reject = () => c.completeError(Exception('permission-denied'));
    return c.future;
  }
}
