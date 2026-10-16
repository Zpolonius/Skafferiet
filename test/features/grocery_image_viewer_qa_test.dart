import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/grocery_screen.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth() : super(AuthState());
}

const _url = 'https://example.com/maelk.jpg';
final _viewer = find.byKey(const Key('image_viewer'));
final _thumb = find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.label == 'Vis billede af Mælk' &&
    w.properties.button == true);

Future<FakeFirebaseFirestore> _pump(WidgetTester tester,
    {String? imageUrl = _url, bool checked = false}) async {
  final fs = FakeFirebaseFirestore();
  await fs
      .collection('households')
      .doc('h1')
      .collection('grocery_list')
      .doc('i1')
      .set({
    'name': 'Mælk',
    'category': 'Mejeri',
    'quantity': '1',
    'unit': 'l',
    'imageUrl': imageUrl,
    'isChecked': checked,
    'source': 'manual',
    'createdAt': DateTime(2026).millisecondsSinceEpoch,
  });
  await tester.binding.setSurfaceSize(const Size(600, 900));
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
    child: MaterialApp(theme: AppTheme.lightTheme, home: const GroceryScreen()),
  ));
  await tester.pumpAndSettle();
  return fs;
}

Future<bool> _isChecked(FakeFirebaseFirestore fs) async {
  final doc = await fs
      .collection('households')
      .doc('h1')
      .collection('grocery_list')
      .doc('i1')
      .get();
  return doc.data()!['isChecked'] as bool;
}

void main() {
  testWidgets('long-press på miniaturen åbner redigering', (tester) async {
    final fs = await _pump(tester);
    await tester.longPress(_thumb);
    await tester.pumpAndSettle();
    expect(find.text('Rediger vare'), findsOneWidget);
    expect(_viewer, findsNothing);
    expect(await _isChecked(fs), isFalse);
  });
  testWidgets('swipe fra miniaturen viser Rediger/Slet', (tester) async {
    await _pump(tester);
    await tester.drag(_thumb, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Rediger'), findsOneWidget);
    expect(find.text('Slet'), findsOneWidget);
    expect(_viewer, findsNothing);
  });
  testWidgets('afkrydset vare: miniature åbner viewer, forbliver afkrydset',
      (tester) async {
    final fs = await _pump(tester, checked: true);
    await tester.tap(_thumb);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(_viewer, findsOneWidget);
    expect(await _isChecked(fs), isTrue);
  });
  testWidgets('tryk lige til højre for miniaturen afkrydser', (tester) async {
    final fs = await _pump(tester);
    final r = tester.getRect(_thumb);
    await tester.tapAt(Offset(r.right + 6, r.center.dy));
    await tester.pumpAndSettle();
    expect(_viewer, findsNothing);
    expect(await _isChecked(fs), isTrue);
  });
  testWidgets('swipe ned (ikke zoomet) lukker; tryk på baggrund lukker',
      (tester) async {
    await _pump(tester);
    await tester.tap(_thumb);
    await tester.pumpAndSettle();
    await tester.fling(_viewer, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(_viewer, findsNothing);
    await tester.tap(_thumb);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    expect(_viewer, findsNothing);
  });
  testWidgets('dialog -> viewer -> luk -> dialog stadig der', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Mælk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_image')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Luk'));
    await tester.pumpAndSettle();
    expect(find.text('Rediger vare'), findsOneWidget);
    expect(_viewer, findsNothing);
  });
}
