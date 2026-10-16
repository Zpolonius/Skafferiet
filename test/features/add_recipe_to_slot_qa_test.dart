// QA for #36 (runde 2): læg en opskrift på en tom plads via "Søg opskrifter"
// i Tilføj måltid — uge, dag, måltidstyper, dobbelttryk, FAB og tastatur.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/services/week_dates.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/add_custom_meal_sheet.dart';
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

final _lasagne = Recipe(
    id: 'r1',
    title: 'Lasagne',
    calories: 600,
    time: '45 min',
    category: RecipeCategory.aftensmad);
final _pasta = Recipe(
    id: 'r2',
    title: 'Pasta pesto',
    calories: 500,
    time: '20 min',
    category: RecipeCategory.aftensmad);

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _Recipes(this.list);
  final List<Recipe> list;
  @override
  Stream<List<Recipe>> build() => Stream.value(list);
}

class _Gated extends MealPlanNotifier {
  _Gated(FirebaseFirestore fs) : super(firestore: fs);
  Completer<void>? gate;
  int updates = 0;
  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry}) async {
    updates++;
    if (gate != null) await gate!.future;
    return super
        .updateSlot(day, slotType, recipe: recipe, directEntry: directEntry);
  }
}

String _weekId(int offset) {
  return weekIdOf(addWeeks(weekStartOf(DateTime.now()), offset));
}

DocumentReference<Map<String, dynamic>> _doc(FakeFirebaseFirestore fs, int o) =>
    fs
        .collection('households')
        .doc('h1')
        .collection('meal_plans')
        .doc(_weekId(o));

Future<Map<String, dynamic>?> _slot(FakeFirebaseFirestore fs, int o, String day,
    [String key = 'dinner']) async {
  final d = (await _doc(fs, o).get()).data();
  return ((d?['days'] as Map?)?[day] as Map?)?[key] as Map<String, dynamic>?;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<(FakeFirebaseFirestore, _Gated)> _pump(WidgetTester tester,
    {Map<String, dynamic> dinners = const {},
    int weekOffset = 0,
    String day = 'Tirsdag',
    List<Recipe>? recipes,
    List<MealType> types = MealType.values,
    Size size = const Size(390, 1400)}) async {
  final fs = FakeFirebaseFirestore();
  await _doc(fs, weekOffset).set({
    'days': {
      for (final e in dinners.entries) e.key: {'dinner': e.value}
    }
  });
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final plan = _Gated(fs);
  final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, __) => const MealPlanScreen())]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => plan),
      recipesProvider
          .overrideWith(() => _Recipes(recipes ?? [_lasagne, _pasta])),
      householdProvider.overrideWith((ref) => _Household(types)),
      selectedDayProvider.overrideWith((ref) => day),
      weekOffsetProvider.overrideWith((ref) => weekOffset),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await _settle(tester);
  return (fs, plan);
}

Finder _inAdd(Finder f) =>
    find.descendant(of: find.byType(AddCustomMealSheet), matching: f);

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  testWidgets(
      'R2 Søg opskrifter in week +1, other day via strip writes to week +1',
      (tester) async {
    final (fs, _) = await _pump(tester, weekOffset: 1, day: 'Torsdag');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    // vælg fredag i dagsstrimlen
    final fri = daysOfWeek(addWeeks(weekStartOf(DateTime.now()), 1))[4];
    await tester.tap(_inAdd(find.text('${fri.day}')).first);
    await _settle(tester);
    await tester.tap(_inAdd(find.text('Pasta pesto')));
    await _settle(tester);
    expect(
        await _slot(fs, 1, 'Fredag'), {'recipeId': 'r2', 'directEntry': null});
    expect(await _slot(fs, 0, 'Fredag'), isNull);
    expect(await _slot(fs, 1, 'Torsdag'), isNull);
  });

  testWidgets('R3 Søg opskrifter chips respect mealTypes', (tester) async {
    await _pump(tester,
        day: 'Torsdag', types: [MealType.breakfast, MealType.dinner]);
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    expect(_inAdd(find.byType(ChoiceChip)), findsNWidgets(2));
    expect(_inAdd(find.text('frokost')), findsNothing);
    expect(_inAdd(find.text('snack')), findsNothing);
  });

  testWidgets('R4 double tap on recipe in Søg opskrifter writes once',
      (tester) async {
    final (fs, plan) = await _pump(tester, day: 'Torsdag');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    plan.gate = Completer<void>();
    await tester.tap(_inAdd(find.text('Pasta pesto')));
    await tester.pump();
    await tester.tap(_inAdd(find.text('Lasagne')), warnIfMissed: false);
    await tester.pump();
    plan.gate!.complete();
    await _settle(tester);
    expect(plan.updates, 1);
    expect(
        await _slot(fs, 0, 'Torsdag'), {'recipeId': 'r2', 'directEntry': null});
  });

  testWidgets('R5 FAB in week +1 on Fredag preselects Fredag of week +1',
      (tester) async {
    final (fs, _) = await _pump(tester, weekOffset: 1, day: 'Fredag');
    await tester.tap(find.text('Tilføj måltid'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    await tester.tap(_inAdd(find.text('Pasta pesto')));
    await _settle(tester);
    expect(
        await _slot(fs, 1, 'Fredag'), {'recipeId': 'r2', 'directEntry': null});
  });

  testWidgets('R6 Søg opskrifter with no recipes', (tester) async {
    await _pump(tester, day: 'Torsdag', recipes: const []);
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    expect(_inAdd(find.text('Du har ingen opskrifter endnu')), findsOneWidget);
    expect(_inAdd(find.text('Gem måltid')), findsNothing);
  });

  testWidgets('R9 tastaturet dækker ikke filter og liste i Søg opskrifter',
      (tester) async {
    await _pump(tester, day: 'Torsdag', size: const Size(390, 844));
    await tester.tap(find.text('Tilføj måltid'));
    await _settle(tester);
    tester.takeException();
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.showKeyboard(_inAdd(find.byType(TextField)));
    await tester.enterText(_inAdd(find.byType(TextField)), 'pa');
    await _settle(tester);
    await tester.ensureVisible(_inAdd(find.text('Pasta pesto')));
    await _settle(tester);
    expect(tester.getRect(_inAdd(find.text('Pasta pesto'))).bottom <= 844 - 300,
        isTrue);
    expect(tester.getRect(_inAdd(find.byType(TextField))).bottom <= 844 - 300,
        isTrue);
  });
}
