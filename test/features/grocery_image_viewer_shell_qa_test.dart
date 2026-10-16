import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
Finder get _hero => find.descendant(of: _viewer, matching: find.byType(Hero));

Future<FakeFirebaseFirestore> _pump(WidgetTester tester,
    {bool shell = false}) async {
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
    'imageUrl': _url,
    'isChecked': false,
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
    child: shell
        ? MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: GoRouter(initialLocation: '/grocery', routes: [
              StatefulShellRoute.indexedStack(
                builder: (c, s, nav) => Scaffold(
                    body: nav,
                    bottomNavigationBar:
                        const SizedBox(height: 80, child: Text('NAVBAR'))),
                branches: [
                  StatefulShellBranch(routes: [
                    GoRoute(
                        path: '/grocery',
                        builder: (c, s) => const GroceryScreen()),
                  ]),
                ],
              ),
            ]))
        : MaterialApp(theme: AppTheme.lightTheme, home: const GroceryScreen()),
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

double _scale(WidgetTester t) => t
    .widget<Transform>(find.descendant(
        of: find.byType(InteractiveViewer), matching: find.byType(Transform)))
    .transform
    .getMaxScaleOnAxis();

Future<void> _pinch(WidgetTester tester, double step, {int n = 10}) async {
  final c = tester.getCenter(_viewer);
  final g1 = await tester.startGesture(c - const Offset(60, 0), pointer: 7);
  final g2 = await tester.startGesture(c + const Offset(60, 0), pointer: 8);
  for (var i = 0; i < n; i++) {
    await g1.moveBy(Offset(-step, 0));
    await g2.moveBy(Offset(step, 0));
    await tester.pump();
  }
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'zoomet: lodret panorering, tryk/swipe lukker ikke; ved 1x lukker swipe igen',
      (tester) async {
    await _pump(tester);
    await tester.tap(_thumb);
    await tester.pumpAndSettle();
    await _pinch(tester, 12);
    expect(_scale(tester), greaterThan(1.5));
    final before = tester.getRect(_hero).top;
    await tester.dragFrom(tester.getCenter(_viewer), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(_hero).top, lessThan(before - 100));
    await tester.fling(_viewer, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(_viewer, findsOneWidget);
    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();
    expect(_viewer, findsOneWidget);
    await _pinch(tester, -12, n: 4);
    expect(_scale(tester), closeTo(1, 0.01));
    await tester.fling(_viewer, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(_viewer, findsNothing);
  });

  testWidgets(
      'GoRouter-skal: hero flyver, viewer dækker bundbaren, tilbage lukker',
      (tester) async {
    await _pump(tester, shell: true);
    final src = find.byKey(const Key('grocery_image_i1'));
    expect(src, findsOneWidget);
    await tester.tap(_thumb);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(src, findsNothing, reason: 'kilde-hero skjules under flyvning');
    await tester.pumpAndSettle();
    expect(tester.getRect(_viewer), const Rect.fromLTWH(0, 0, 600, 900));
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(_viewer, findsNothing);
    expect(src, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'semantik: rækken beholder afkrydsning, fysisk tryk åbner én viewer',
      (tester) async {
    final h = tester.ensureSemantics();
    final fs = await _pump(tester);
    final row = tester.getSemantics(find.text('Mælk'));
    expect(row.label, isNot(contains('Vis billede')));
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Mælk')));
    await tester.pumpAndSettle();
    expect(await _isChecked(fs), isTrue);
    expect(_viewer, findsNothing);
    await tester.tap(_thumb);
    await tester.pumpAndSettle();
    expect(_viewer, findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    h.dispose();
  });

  testWidgets('tryk på badge-hjørnet åbner vieweren', (tester) async {
    final fs = await _pump(tester);
    final r = tester.getRect(_thumb);
    await tester.tapAt(r.bottomRight - const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(_viewer, findsOneWidget);
    expect(await _isChecked(fs), isFalse);
  });
}
