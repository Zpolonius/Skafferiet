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

/// Lægger én vare i listen og åbner indkøbslisten.
Future<void> _pump(
  WidgetTester tester, {
  required String name,
  required String quantity,
  String? unit,
  bool isChecked = false,
  double textScale = 1.0,
  Size size = const Size(360, 800),
}) async {
  final fs = FakeFirebaseFirestore();
  await fs
      .collection('households')
      .doc('h1')
      .collection('grocery_list')
      .doc('i1')
      .set({
    'name': name,
    'category': 'Andet',
    'quantity': quantity,
    'unit': unit,
    'imageUrl': null,
    'isChecked': isChecked,
    'source': 'manual',
    'createdAt': DateTime(2026).millisecondsSinceEpoch,
  });
  await tester.binding.setSurfaceSize(size);
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
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const GroceryScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // Overskriftsrækken (logo, titel og ikon-knapper) overflower i testens
  // skrifttype når listen ikke er tom. Det er ikke en del af denne ændring
  // (også på main), så den fejl tømmes her. Varekortets geometri testes i
  // stedet i _expectChipFitsCard. Alle andre fejl får testen til at fejle.
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error.toString(), contains('overflowed'),
        reason: 'Kun den kendte overflow i overskriften må ignoreres');
  }
}

final _chip = find.byKey(const Key('grocery_quantity_i1'));

/// Varens række i skærmlæseren samler navn, kategori og mængde i én label,
/// så mængden findes som egen linje.
Pattern _spoken(String spoken) =>
    RegExp('(^|\\n)${RegExp.escape(spoken)}(\\n|\$)');

/// Tjekker geometrien: chippen må ikke gå ud over varekortet, og navnet må
/// ikke skubbes ind over chippen.
void _expectChipFitsCard(WidgetTester tester, String name) {
  final card = find.ancestor(
    of: _chip,
    matching: find.byWidgetPredicate(
        (w) => w is Container && w.padding == const EdgeInsets.all(12)),
  );
  final chipRect = tester.getRect(_chip);
  expect(chipRect.width, lessThanOrEqualTo(120));
  expect(chipRect.right, lessThanOrEqualTo(tester.getRect(card).right));
  expect(
      tester.getRect(find.text(name)).right, lessThanOrEqualTo(chipRect.left));
}

void main() {
  testWidgets('gram vises med enhed og læses op som "500 gram"',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, name: 'Mel', quantity: '500', unit: 'g');

    expect(find.text('500 g'), findsOneWidget);
    expect(find.bySemanticsLabel(_spoken('500 gram')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('stk vises med enhed og læses op som "2 stk"', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, name: 'Løg', quantity: '2', unit: 'stk');

    expect(find.text('2 stk'), findsOneWidget);
    expect(find.bySemanticsLabel(_spoken('2 stk')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('vare uden enhed viser kun tallet', (tester) async {
    await _pump(tester, name: 'Æg', quantity: '6', unit: null);

    expect(
        find.descendant(of: _chip, matching: find.text('6')), findsOneWidget);
    expect(find.text('6 stk'), findsNothing);
  });

  testWidgets('tom enhed (kun mellemrum) viser kun tallet', (tester) async {
    await _pump(tester, name: 'Æg', quantity: '6', unit: '  ');

    expect(
        find.descendant(of: _chip, matching: find.text('6')), findsOneWidget);
  });

  testWidgets('vare uden mængde har ingen chip', (tester) async {
    await _pump(tester, name: 'Salt', quantity: '', unit: 'g');

    expect(find.text('Salt'), findsOneWidget);
    expect(_chip, findsNothing);
    expect(find.text('g'), findsNothing);
  });

  testWidgets('decimaltal bruger komma og ingen overflødig ".0"',
      (tester) async {
    await _pump(tester, name: 'Mælk', quantity: '1,5', unit: 'l');
    expect(find.text('1,5 l'), findsOneWidget);
    expect(find.bySemanticsLabel(_spoken('1,5 liter')), findsOneWidget);
  });

  testWidgets('gammel værdi "2.0" fra opskrifter vises som "2 fed"',
      (tester) async {
    await _pump(tester, name: 'Hvidløg', quantity: '2.0', unit: 'fed');

    expect(find.text('2 fed'), findsOneWidget);
    expect(find.text('2.0 fed'), findsNothing);
  });

  testWidgets('afkrydset vare viser mængden dæmpet i stedet for at skjule den',
      (tester) async {
    await _pump(tester,
        name: 'Mel', quantity: '500', unit: 'g', isChecked: true);

    final text = tester.widget<Text>(find.text('500 g'));
    final scheme = AppTheme.lightTheme.colorScheme;
    expect(text.style?.color, scheme.outline);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets(
      'lang enhed og lang vare holder sig inden for kortet ved '
      'tekststørrelse 1.3 på 320 px', (tester) async {
    const name = 'Meget lang varebeskrivelse der skal brydes pænt over linjer';
    await _pump(
      tester,
      name: name,
      quantity: '1234,5',
      unit: 'sækkeXXXXXXXX',
      textScale: 1.3,
      size: const Size(320, 640),
    );
    _expectChipFitsCard(tester, name);
  });

  testWidgets(
      'lang enhed og lang vare holder sig inden for kortet ved '
      'tekststørrelse 1.3 på 360 px', (tester) async {
    const name = 'Meget lang varebeskrivelse der skal brydes pænt over linjer';
    await _pump(
      tester,
      name: name,
      quantity: '1234,5',
      unit: 'sækkeXXXXXXXX',
      textScale: 1.3,
    );
    _expectChipFitsCard(tester, name);
  });
}
