// #56 runde 2: ugen skifter mens appen står åben (midnat/genoptagelse), kopiér
// overskriver aldrig det serveren har, og skjulte måltider nævnes i tilbuddet.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/day_rollover.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household(List<MealType> types)
      : super(HouseholdState(householdId: 'h1', mealTypes: types));
}

class _NoRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, String id) =>
    fs.collection('households').doc('h1').collection('meal_plans').doc(id);

Map<String, dynamic> _plan(Map<String, Map<String, String>> days) => {
      'days': {
        for (final d in days.entries)
          d.key: {
            for (final s in d.value.entries)
              s.key: {'recipeId': null, 'directEntry': s.value}
          }
      }
    };

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Env {
  _Env(this.fs, this.container);
  final FakeFirebaseFirestore fs;
  final ProviderContainer container;
}

Future<_Env> _pump(
  WidgetTester tester, {
  required DateTime Function() clock,
  Map<String, Map<String, dynamic>> docs = const {},
  List<MealType> mealTypes = MealType.values,
  MealPlanNotifier Function(FirebaseFirestore fs)? plan,
}) async {
  final fs = FakeFirebaseFirestore();
  for (final e in docs.entries) {
    await _doc(fs, e.key).set(e.value);
  }
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(const Size(360, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const DayRollover(child: MealPlanScreen())),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(
          () => plan?.call(fs) ?? MealPlanNotifier(firestore: fs)),
      recipesProvider.overrideWith(() => _NoRecipes()),
      householdProvider.overrideWith((ref) => _Household(mealTypes)),
      clockProvider.overrideWithValue(clock),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await _settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
  return _Env(fs, container);
}

Future<void> _resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await _settle(tester);
}

/// Planen som den lokale cache ser den: tom, selv om serveren har indhold.
class _StalePlan extends MealPlanNotifier {
  _StalePlan(FirebaseFirestore fs) : super(firestore: fs);
  @override
  Stream<WeeklyMealPlan> build() {
    final id = currentWeekId();
    return Stream.value(
        WeeklyMealPlan(id: id, weekStart: DateTime.parse(id), days: const {}));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  group('ugeskift mens appen står åben', () {
    testWidgets(
        'genoptagelse søndag -> torsdag: overskrift, plan og skrivning følger',
        (tester) async {
      var now = DateTime(2026, 10, 11, 20, 0); // søndag
      final env = await _pump(tester, clock: () => now, docs: {
        '2026-10-05': _plan({
          'Søndag': {'dinner': 'Søndagsmad'}
        }),
      });
      expect(find.text('Uge 41 · 5.–11. okt.'), findsOneWidget);

      now = DateTime(2026, 10, 15, 9, 0); // torsdag
      await _resume(tester);

      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(find.text('Denne uge'), findsOneWidget);
      expect(env.container.read(mealPlanProvider).value?.id, '2026-10-12');
      expect(env.container.read(mealPlanProvider.notifier).currentWeekId(),
          '2026-10-12');
      // Ugen er tom, ugen før har et måltid: kopiering tilbydes.
      expect(find.text('Sidste uge havde 1 måltid – kopiér til denne uge?'),
          findsOneWidget);
      // Valgt dag er i dag (torsdag), ikke søndag fra den gamle uge.
      expect(env.container.read(selectedDayProvider), 'Torsdag');
      expect(find.text('Torsdagens madplan'), findsOneWidget);
    });

    testWidgets('ved midnat skifter ugen uden genoptagelse', (tester) async {
      var now = DateTime(2026, 10, 11, 23, 50); // søndag lige før midnat
      await _pump(tester, clock: () => now);
      expect(find.text('Uge 41 · 5.–11. okt.'), findsOneWidget);
      expect(find.text('Planlægger du næste uge?'), findsOneWidget);

      now = DateTime(2026, 10, 12, 0, 5);
      await tester.pump(const Duration(minutes: 20));
      await _settle(tester);
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
    });

    testWidgets('en uge man har bladret til (næste uge) bliver den samme uge',
        (tester) async {
      var now = DateTime(2026, 10, 11, 20, 0);
      final env = await _pump(tester, clock: () => now);
      env.container.read(weekOffsetProvider.notifier).state = 1; // 12.–18.
      await _settle(tester);
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);

      now = DateTime(2026, 10, 12, 8, 0);
      await _resume(tester);
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(find.text('Denne uge'), findsOneWidget);
      expect(env.container.read(weekOffsetProvider), 0);
    });

    testWidgets('samme dag: genoptagelse ændrer intet', (tester) async {
      var now = DateTime(2026, 10, 15, 9, 0);
      final env = await _pump(tester, clock: () => now);
      env.container.read(weekOffsetProvider.notifier).state = 2;
      env.container.read(selectedDayProvider.notifier).state = 'Fredag';
      now = DateTime(2026, 10, 15, 21, 0);
      await _resume(tester);
      expect(env.container.read(weekOffsetProvider), 2);
      expect(env.container.read(selectedDayProvider), 'Fredag');
    });
  });

  group('kopiér forrige uge', () {
    testWidgets(
        'overskriver ikke et måltid serveren har, selv om den lokale kopi er tom',
        (tester) async {
      final env = await _pump(
        tester,
        clock: () => DateTime(2026, 10, 15, 12),
        plan: _StalePlan.new,
        docs: {
          '2026-10-05': _plan({
            'Mandag': {'dinner': 'Pasta'},
            'Tirsdag': {'dinner': 'Suppe'},
          }),
          // Et andet medlem har fyldt Mandag på serveren.
          '2026-10-12': _plan({
            'Mandag': {'dinner': 'Burger'}
          }),
        },
      );
      expect(find.text('Sidste uge havde 2 måltider – kopiér til denne uge?'),
          findsOneWidget);
      await tester.tap(find.text('Kopiér'));
      await _settle(tester);

      final data = (await _doc(env.fs, '2026-10-12').get()).data()!;
      final days = data['days'] as Map;
      expect((days['Mandag'] as Map)['dinner'],
          {'recipeId': null, 'directEntry': 'Burger'});
      expect((days['Tirsdag'] as Map)['dinner'],
          {'recipeId': null, 'directEntry': 'Suppe'});
      expect(find.text('1 måltid kopieret'), findsOneWidget);
    });

    testWidgets(
        'Fortryd rører ikke et måltid et andet medlem har lagt til siden',
        (tester) async {
      final env = await _pump(
        tester,
        clock: () => DateTime(2026, 10, 15, 12),
        docs: {
          '2026-10-05': _plan({
            'Mandag': {'dinner': 'Pasta'}
          }),
        },
      );
      await tester.tap(find.text('Kopiér'));
      await _settle(tester);
      await _doc(env.fs, '2026-10-12').set(
          _plan({
            'Fredag': {'dinner': 'Taco'}
          }),
          SetOptions(merge: true));
      await _settle(tester);
      await tester.tap(find.text('Fortryd'));
      await _settle(tester);
      final days =
          (await _doc(env.fs, '2026-10-12').get()).data()!['days'] as Map;
      expect((days['Mandag'] as Map)['dinner'],
          {'recipeId': null, 'directEntry': null});
      expect((days['Fredag'] as Map)['dinner'],
          {'recipeId': null, 'directEntry': 'Taco'});
    });

    testWidgets('skjulte måltider nævnes i tilbuddet', (tester) async {
      await _pump(
        tester,
        clock: () => DateTime(2026, 10, 15, 12),
        mealTypes: [MealType.dinner],
        docs: {
          '2026-10-05': _plan({
            'Mandag': {'dinner': 'Pasta', 'lunch': 'Suppe'},
            'Tirsdag': {'snack': 'Æble', 'breakfast': 'Grød'},
          }),
        },
      );
      expect(
          find.text(
              'Sidste uge havde 4 måltider (heraf 3 skjulte) – kopiér til denne uge?'),
          findsOneWidget);
    });

    testWidgets('ét skjult måltid: "skjult"', (tester) async {
      await _pump(
        tester,
        clock: () => DateTime(2026, 10, 15, 12),
        mealTypes: [MealType.dinner],
        docs: {
          '2026-10-05': _plan({
            'Mandag': {'dinner': 'Pasta', 'lunch': 'Suppe'},
          }),
        },
      );
      expect(
          find.text(
              'Sidste uge havde 2 måltider (heraf 1 skjult) – kopiér til denne uge?'),
          findsOneWidget);
    });

    testWidgets('tilbuddet vises ikke mens planen genindlæses', (tester) async {
      // Ingen plan endnu (tom stream): intet tilbud.
      final env = await _pump(
        tester,
        clock: () => DateTime(2026, 10, 15, 12),
        docs: {
          '2026-10-05': _plan({
            'Mandag': {'dinner': 'Pasta'}
          }),
        },
      );
      expect(find.text('Kopiér'), findsOneWidget);
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await tester.pump(); // ugeskiftet er i gang, planen er ikke indlæst
      expect(find.text('Kopiér'), findsNothing);
    });
  });
}
