// Madplanens startdag (#37): skærmen, "Tilføj"-arkene og indstillingen i
// Præferencer med søndag som startdag.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/add_custom_meal_sheet.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/preferences_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household(super.state);
}

class _NoRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

// Torsdag 2026-10-15. Søndagsstart: planen er søn 11. okt. – lør 17. okt.
final _thursday = DateTime(2026, 10, 15, 12);

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, String id) =>
    fs.collection('households').doc('h1').collection('meal_plans').doc(id);

Map<String, dynamic> _dinner(String text) => {
      'dinner': {'recipeId': null, 'directEntry': text}
    };

Future<FakeFirebaseFirestore> _seed() async {
  final fs = FakeFirebaseFirestore();
  await _doc(fs, '2026-10-05').set({
    'days': {
      'Mandag': _dinner('Gammel mandag'),
      'Søndag': _dinner('Søndagssteg')
    }
  });
  await _doc(fs, '2026-10-12').set({
    'days': {
      'Mandag': _dinner('Mandagsgryde'),
      'Lørdag': _dinner('Lørdagspizza')
    }
  });
  return fs;
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester,
  FakeFirebaseFirestore fs, {
  int? start,
  Widget? home,
}) async {
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(const Size(360, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home ?? const MealPlanScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
      recipesProvider.overrideWith(() => _NoRecipes()),
      householdProvider.overrideWith((ref) => _Household(
          HouseholdState(householdId: 'h1', mealPlanStartWeekday: start))),
      clockProvider.overrideWithValue(() => _thursday),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  group('madplanen med søndag som startdag', () {
    testWidgets('åbner på i dag; overskrift og strip følger plan-ugen',
        (tester) async {
      await _pumpScreen(tester, await _seed(), start: 7);
      expect(find.text('Uge 42 · 11.–17. okt.'), findsOneWidget);
      expect(find.text('Denne uge'), findsOneWidget);
      // Striben begynder med søndag og slutter med lørdag.
      final sun = tester.getTopLeft(find.text('SØN')).dx;
      final mon = tester.getTopLeft(find.text('MAN')).dx;
      final sat = tester.getTopLeft(find.text('LØR')).dx;
      expect(sun, lessThan(mon));
      expect(mon, lessThan(sat));
      expect(find.text('11'), findsOneWidget); // søndagens dato først i ugen
      // Torsdag (i dag) er valgt.
      expect(find.bySemanticsLabel(RegExp(r'^Torsdag 15\. oktober')),
          findsOneWidget);
    });

    testWidgets(
        'søndagen viser måltidet fra forrige mandags-dokument; mandag det fra næste',
        (tester) async {
      await _pumpScreen(tester, await _seed(), start: 7);
      await tester.tap(find.text('SØN'));
      await tester.pumpAndSettle();
      expect(find.text('Søndagssteg'), findsWidgets);
      await tester.tap(find.text('MAN'));
      await tester.pumpAndSettle();
      expect(find.text('Mandagsgryde'), findsWidgets);
      expect(find.text('Gammel mandag'), findsNothing);
    });

    testWidgets(
        'ingen indstilling (eksisterende husstand): uge 12.–18. okt., mandag først',
        (tester) async {
      await _pumpScreen(tester, await _seed());
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(tester.getTopLeft(find.text('MAN')).dx,
          lessThan(tester.getTopLeft(find.text('SØN')).dx));
      await tester.tap(find.text('MAN'));
      await tester.pumpAndSettle();
      expect(find.text('Mandagsgryde'), findsWidgets);
    });
  });

  group('tilføj-arkene lægger måltidet i dokumentet for datoen', () {
    testWidgets(
        'Tilføj måltid: søndag (11. okt.) lander i mandagen før, ikke i den viste uges dokument',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await _pumpScreen(tester, fs,
          start: 7,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showAppBottomSheet(
                  context: context,
                  builder: (_) =>
                      const AddCustomMealSheet(initialDay: 'Søndag'),
                ),
                child: const Text('open'),
              ),
            ),
          ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Søndagsbrunch');
      await tester.pump();
      final save = find.textContaining(RegExp(r'^(Gem|Tilføj) måltid|^Gem$'));
      expect(save, findsWidgets);
      await tester.tap(save.last);
      await tester.pumpAndSettle();
      final d05 = (await _doc(fs, '2026-10-05').get()).data();
      expect(
          d05?['days']?['Søndag']?['dinner']?['directEntry'], 'Søndagsbrunch');
      expect((await _doc(fs, '2026-10-12').get()).exists, isFalse);
    });

    testWidgets(
        'Tilføj til madplan: dagene begynder med søndag og søndag skrives i forrige dokument',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      final recipe = Recipe(
        id: 'r1',
        title: 'Lasagne',
        category: RecipeCategory.aftensmad,
        calories: 1,
        time: '1 min',
        ingredients: [],
      );
      await _pumpScreen(tester, fs,
          start: 7,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppBottomSheet(
                  context: context,
                  builder: (_) => AddToMealPlanSheet(recipe: recipe),
                ),
                child: const Text('open'),
              ),
            ),
          ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Søndag')).dx,
          lessThan(tester.getTopLeft(find.text('Mandag')).dx));
      await tester.tap(find.text('Søndag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aftensmad').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bekræft'));
      await tester.pumpAndSettle();
      final d05 = (await _doc(fs, '2026-10-05').get()).data();
      expect(d05?['days']?['Søndag']?['dinner']?['recipeId'], 'r1');
      expect((await _doc(fs, '2026-10-12').get()).exists, isFalse);
    });
  });

  group('Præferencer: Madplanen starter', () {
    Future<_Household> pump(WidgetTester tester, HouseholdState state) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final household = _Household(state);
      await tester.pumpWidget(ProviderScope(
        overrides: [householdProvider.overrideWith((ref) => household)],
        child: MaterialApp(
            theme: AppTheme.lightTheme, home: const PreferencesScreen()),
      ));
      await tester.pumpAndSettle();
      return household;
    }

    HouseholdState base({int? shopping, int? start}) => HouseholdState(
          householdId: 'HH',
          householdName: 'Familien',
          adultsCount: 2,
          childrenCount: 1,
          shoppingWeekday: shopping,
          mealPlanStartWeekday: start,
          isLoading: false,
        );

    testWidgets(
        'uden valg: forslag er dagen efter indkøbsdagen, og intet gemmes før et valg',
        (tester) async {
      await pump(tester, base(shopping: DateTime.saturday));
      expect(find.text('Madplanen starter'), findsOneWidget);
      expect(find.textContaining('Søndag'), findsOneWidget);
      expect(find.textContaining('Forslag'), findsOneWidget);
      final save =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gem'));
      expect(save.onPressed, isNull);
    });

    testWidgets('uden valg og uden indkøbsdag: mandag', (tester) async {
      await pump(tester, base());
      expect(find.textContaining('Mandag'), findsOneWidget);
    });

    testWidgets('vælg Søndag og Gem: sender mealPlanStartWeekday 7',
        (tester) async {
      final household = await pump(tester, base());
      when(() => household.updatePreferences(
            adultsCount: any(named: 'adultsCount'),
            childrenCount: any(named: 'childrenCount'),
            preferences: any(named: 'preferences'),
            mealPlanStartWeekday: any(named: 'mealPlanStartWeekday'),
          )).thenAnswer((_) async => null);
      await tester.tap(find.byKey(const Key('meal-plan-start-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Søndag').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Gem'));
      await tester.pumpAndSettle();
      verify(() => household.updatePreferences(
            adultsCount: 2,
            childrenCount: 1,
            preferences: const [],
            mealPlanStartWeekday: 7,
          )).called(1);
    });

    testWidgets('husstandens gemte valg vises', (tester) async {
      await pump(
          tester, base(shopping: DateTime.saturday, start: DateTime.wednesday));
      expect(find.textContaining('Onsdag'), findsOneWidget);
      expect(find.textContaining('Forslag'), findsNothing);
    });
  });
}
