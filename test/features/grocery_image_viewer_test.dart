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
import 'package:skafferiet/shared/widgets/image_viewer.dart';

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
    {String? imageUrl = _url}) async {
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
  testWidgets('tryk på miniaturen åbner billedet uden at afkrydse varen',
      (tester) async {
    final fs = await _pump(tester);
    expect(_thumb, findsOneWidget);
    expect(_viewer, findsNothing);

    await tester.tap(_thumb);
    await tester.pumpAndSettle();

    expect(_viewer, findsOneWidget);
    expect(await _isChecked(fs), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('billedvieweren lukkes med lukkeknappen', (tester) async {
    await _pump(tester);
    await tester.tap(_thumb);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Luk'));
    await tester.pumpAndSettle();

    expect(_viewer, findsNothing);
  });

  testWidgets('tryk på navnet afkrydser stadig varen', (tester) async {
    final fs = await _pump(tester);
    await tester.tap(find.text('Mælk'));
    await tester.pumpAndSettle();

    expect(_viewer, findsNothing);
    expect(await _isChecked(fs), isTrue);
  });

  testWidgets('vare uden billede: tryk på ikonet afkrydser som før',
      (tester) async {
    final fs = await _pump(tester, imageUrl: null);
    expect(_thumb, findsNothing);

    await tester.tap(find.byIcon(Icons.egg_alt));
    await tester.pumpAndSettle();

    expect(_viewer, findsNothing);
    expect(await _isChecked(fs), isTrue);
  });

  testWidgets('i sorteringstilstand åbner miniaturen ikke billedet',
      (tester) async {
    final fs = await _pump(tester);
    await tester.tap(find.byTooltip('Sorter liste'));
    await tester.pumpAndSettle();

    expect(_thumb, findsNothing);
    final avatar = find.byKey(const Key('grocery_image_i1'));
    expect(avatar, findsOneWidget);
    await tester.tap(avatar);
    await tester.pumpAndSettle();

    expect(_viewer, findsNothing);
    expect(await _isChecked(fs), isTrue);
  });

  testWidgets('redigeringsdialogen viser billedet og åbner vieweren',
      (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('Mælk'));
    await tester.pumpAndSettle();
    expect(find.text('Rediger vare'), findsOneWidget);

    final dialogImage = find.byKey(const Key('edit_image'));
    expect(dialogImage, findsOneWidget);
    await tester.tap(dialogImage);
    await tester.pumpAndSettle();

    expect(_viewer, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redigeringsdialogen uden billede er uændret', (tester) async {
    await _pump(tester, imageUrl: null);
    await tester.longPress(find.text('Mælk'));
    await tester.pumpAndSettle();

    expect(find.text('Rediger vare'), findsOneWidget);
    expect(find.byKey(const Key('edit_image')), findsNothing);
  });

  testWidgets('zoomet billede kan panoreres (Dismissible æder ikke trækket)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showImageViewer(context, url: _url, heroTag: 't', label: 'Mælk'),
          child: const Text('Åbn'),
        ),
      ),
    ));
    await tester.tap(find.text('Åbn'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(_viewer);
    final a =
        await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final b =
        await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await a.moveTo(center - const Offset(120, 0));
    await b.moveTo(center + const Offset(120, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    Matrix4 matrix() => tester
        .widget<Transform>(find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(Transform)))
        .transform;
    expect(matrix().getMaxScaleOnAxis(), greaterThan(1.5));
    final before = matrix().getTranslation().clone();

    await tester.dragFrom(center, const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.dragFrom(center, const Offset(-100, 0));
    await tester.pumpAndSettle();

    expect(_viewer, findsOneWidget);
    final after = matrix().getTranslation();
    expect(after.y, isNot(closeTo(before.y, 1)));
    expect(after.x, isNot(closeTo(before.x, 1)));
  });

  testWidgets('semantik-tryk på miniaturen åbner viewer uden at afkrydse',
      (tester) async {
    final handle = tester.ensureSemantics();
    final fs = await _pump(tester);
    tester.semantics.tap(find.semantics.byLabel('Vis billede af Mælk'));
    await tester.pumpAndSettle();

    expect(_viewer, findsOneWidget);
    expect(await _isChecked(fs), isFalse);
    handle.dispose();
  });

  testWidgets('semantik-tryk på dialogens billede åbner viewer',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.longPress(find.text('Mælk'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('Vis billede af Mælk').last);
    await tester.pumpAndSettle();

    expect(_viewer, findsOneWidget);
    handle.dispose();
  });

  testWidgets('viewer lægges på root-navigatoren og dækker nested bundbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        bottomNavigationBar: const SizedBox(height: 80, child: Text('bar')),
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => TextButton(
              onPressed: () => showImageViewer(context,
                  url: _url, heroTag: 't', label: 'Mælk'),
              child: const Text('Åbn'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Åbn'));
    await tester.pumpAndSettle();

    expect(tester.getRect(_viewer).height, 900);
  });
}
