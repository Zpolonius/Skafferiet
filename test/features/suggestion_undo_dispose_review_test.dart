import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

/// Skrivninger der svarer først når testen siger til (serverens afvisning
/// kommer efter en rundtur).
class _SlowRepo implements ItemHistoryRepository {
  final removeDone = Completer<void>();
  final restoreDone = Completer<void>();
  @override
  Stream<List<ItemHistoryEntry>> watch(String householdId) async* {
    yield [
      ItemHistoryEntry(
          key: 'kaffe',
          name: 'Kaffe',
          category: 'Kolonial',
          useCount: 7,
          lastUsed: DateTime(2026, 5, 1)),
    ];
    await Completer<void>().future;
  }

  @override
  Future<void> remove(String householdId, String key) => removeDone.future;
  @override
  Future<void> restore(String householdId, ItemHistoryEntry entry) =>
      restoreDone.future;
}

/// QA (#47): et svar fra serveren der kommer EFTER at arket er lukket, må
/// ikke kaste (arkets messenger er væk).
void main() {
  late _SlowRepo repo;
  late ProviderContainer container;

  // Oprettes i testens zone: en fejl fra en Completer i en anden fejlzone
  // ville blive rapporteret som ufanget.
  void setUpRepo() {
    repo = _SlowRepo();
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      itemHistoryRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  }

  Future<void> openRemoveClose(WidgetTester tester, {bool undo = false}) async {
    setUpRepo();
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
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fjern forslag').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    if (undo) {
      await tester.tap(find.text('Fortryd'));
      await tester.pump();
    }
    Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('sletningen afvises efter at arket er lukket', (tester) async {
    await openRemoveClose(tester);
    repo.removeDone.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('fortryd afvises efter at arket er lukket', (tester) async {
    await openRemoveClose(tester, undo: true);
    repo.restoreDone.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
