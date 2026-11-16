import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

/// QA (#47): overlay-værten i "Tilføj vare"-arket må ikke lække, blokere
/// barrieren når der ingen SnackBar er, eller forsvinde bag tastaturet.
void main() {
  late FakeFirebaseFirestore fs;
  late ProviderContainer container;

  setUp(() async {
    fs = FakeFirebaseFirestore();
    await fs
        .collection('households')
        .doc('h1')
        .collection('item_history')
        .doc('kaffe')
        .set({
      'name': 'Kaffe',
      'category': 'Kolonial',
      'useCount': 7,
      'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
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

  Future<void> removeKaffe(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fjern forslag').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Forslag fjernet'), findsOneWidget);
  }

  testWidgets('uden SnackBar: tryk øverst på barrieren lukker stadig arket',
      (tester) async {
    await pumpSheet(tester);
    expect(find.byType(AddGroceryItemSheet), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byType(AddGroceryItemSheet), findsNothing);
  });

  testWidgets('arket lukkes mens SnackBaren vises: ingen fejl, overlay væk',
      (tester) async {
    await pumpSheet(tester);
    await removeKaffe(tester);
    Navigator.of(tester.element(find.byType(AddGroceryItemSheet))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AddGroceryItemSheet), findsNothing);
    // #47 (fund 2): SnackBaren flyttes til rodens messenger, så fortrydelses-
    // vinduet ikke slutter med arket – og kun én ad gangen.
    expect(find.text('Forslag fjernet'), findsOneWidget);
    expect(find.text('Fortryd'), findsOneWidget);
    expect(find.byType(ScaffoldMessenger), findsOneWidget); // kun roden
    // Uret løber videre (SnackBarens timer) uden fejl.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Forslag fjernet'), findsNothing);

    // Åbn igen: virker stadig.
    await tester.tap(find.text('åbn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('med tastaturet oppe er SnackBaren synlig og kan trykkes',
      (tester) async {
    await pumpSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ka');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Fjern forslag').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fjern forslag').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Forslag fjernet'), findsOneWidget);
    expect(find.text('Fortryd').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Fortryd'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suggestion_kaffe')), findsOneWidget);
  });

  testWidgets('SnackBaren er en live region (skærmlæser annoncerer den)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester);
    await removeKaffe(tester);
    final hasLiveRegion = find
        .ancestor(
            of: find.text('Forslag fjernet'), matching: find.byType(Semantics))
        .evaluate()
        .any((e) => (e.widget as Semantics).properties.liveRegion == true);
    expect(hasLiveRegion, isTrue);
    handle.dispose();
  });
}
