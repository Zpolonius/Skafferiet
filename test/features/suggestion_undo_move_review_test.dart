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

/// QA (#47, runde 2): SnackBaren der flyttes til roden når arket lukkes.
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

  testWidgets('Fortryd på den flyttede SnackBar genskaber forslaget',
      (tester) async {
    await pumpApp(tester);
    await openAndRemove(tester);
    popSheet(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortryd'));
    await tester.pumpAndSettle();
    expect((await doc('kaffe').get()).data()!['useCount'], 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'to × lige før lukning: kun én SnackBar, Fortryd gælder den sidste',
      (tester) async {
    await pumpApp(tester);
    await openAndRemove(tester, times: 2);
    popSheet(tester);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(
          find.text('Forslag fjernet').evaluate().length, lessThanOrEqualTo(1));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fortryd'));
    await tester.pumpAndSettle();
    expect((await doc('kakao').get()).exists, isTrue);
  });

  testWidgets(
      'en bekræftelse som arket viser på roden når det lukker (fx "gemt som '
      'fast vare") bliver ikke skjult af den flyttede SnackBar',
      (tester) async {
    await pumpApp(tester);
    await openAndRemove(tester);
    final ctx = tester.element(find.byType(AddGroceryItemSheet));
    // Som add_grocery_item_sheet.dart:191-193 (fast vare): pop, så root-SnackBar.
    final root = ScaffoldMessenger.of(ctx);
    Navigator.pop(ctx, true);
    root.showSnackBar(const SnackBar(content: Text('Gemt som fast vare')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    // Bekræftelsen (4 s standard) må ikke være skjult efter godt 1 s.
    expect(find.text('Gemt som fast vare'), findsOneWidget);
  });

  testWidgets('varighed: den flyttede SnackBar starter forfra (6 s)',
      (tester) async {
    await pumpApp(tester);
    await openAndRemove(tester);
    await tester.pump(const Duration(seconds: 5));
    popSheet(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    // Dokumenterer adfærden: tiden starter forfra ved flytningen (8,6 s
    // efter × er den stadig synlig).
    expect(find.text('Forslag fjernet'), findsOneWidget);
  });

  testWidgets('åbn/luk arket mange gange: intet overlay bliver hængende',
      (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 4; i++) {
      await openAndRemove(tester);
      popSheet(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.byType(ScaffoldMessenger), findsOneWidget);
      await doc('kaffe').set({
        'name': 'Kaffe',
        'category': 'Kolonial',
        'useCount': 7,
        'lastUsed': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
    }
    // Uden SnackBar lukker et tryk øverst stadig arket.
    await tester.tap(find.text('åbn'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byType(AddGroceryItemSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
