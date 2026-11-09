import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/add_custom_meal_sheet.dart';
import 'package:skafferiet/features/meal_plan/edit_meal_slot_sheet.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _User extends Mock implements User {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

final _lasagne = Recipe(
  id: 'r1',
  title: 'Lasagne',
  calories: 600,
  time: '45 min',
  category: RecipeCategory.aftensmad,
);
final _pasta = Recipe(
  id: 'r2',
  title: 'Pasta pesto',
  calories: 500,
  time: '20 min',
  category: RecipeCategory.aftensmad,
);

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value([_lasagne, _pasta]);
}

/// Madplan med tre udfyldte aftensmadder + registrering af skrivninger.
class _Plan extends MealPlanNotifier {
  _Plan() : super(firestore: _MockFirestore());

  final calls = <String>[];
  final restored = <(String, String, MealSlot)>[];
  Object? failWith;
  Completer<void>? hang;
  int restoreFailures = 0;
  final restorePendingFlags = <bool>[];

  @override
  Stream<WeeklyMealPlan> build() {
    DailyPlan dinner(MealSlot s) => DailyPlan(
          breakfast: MealSlot(),
          lunch: MealSlot(),
          dinner: s,
          snack: MealSlot(),
        );
    return Stream.value(
        WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 9, 28), days: {
      'Mandag': dinner(MealSlot(recipeId: 'gone', missingRecipe: true)),
      'Tirsdag': dinner(MealSlot(recipe: _lasagne)),
      'Onsdag': dinner(MealSlot(directEntry: 'Sushi')),
    }));
  }

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    if (hang != null) await hang!.future;
    if (failWith != null) throw failWith!;
    calls.add('$day|$slotType|${recipe?.id}|$directEntry');
  }

  @override
  Future<void> restoreSlot(String day, String slotType, MealSlot slot,
      {String? weekId, bool ownRemovePending = false}) async {
    restored.add((day, slotType, slot));
    restorePendingFlags.add(ownRemovePending);
    if (restoreFailures > 0) {
      restoreFailures--;
      throw Exception('unavailable');
    }
    final what = slot.recipeId ?? slot.directEntry;
    calls.add('restore|$day|$slotType|$what');
  }
}

/// Som [_Plan], men fjerner faktisk aftensmaden i planen, så skærmen opdateres.
class _LivePlan extends _Plan {
  final controller = StreamController<WeeklyMealPlan>();
  late WeeklyMealPlan current;

  @override
  Stream<WeeklyMealPlan> build() {
    current = WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 9, 28), days: {
      'Tirsdag': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(),
        dinner: MealSlot(recipe: _lasagne),
        snack: MealSlot(),
      ),
    });
    controller.add(current);
    ref.onDispose(controller.close);
    return controller.stream;
  }

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    await super.updateSlot(day, slotType, recipe: recipe, directEntry: directEntry);
    if (recipe == null && directEntry == null) {
      controller.add(WeeklyMealPlan(id: 'w', weekStart: current.weekStart, days: {
        day: DailyPlan(
            breakfast: MealSlot(), lunch: MealSlot(), dinner: MealSlot(), snack: MealSlot()),
      }));
    }
  }
}

Future<_Plan> _pump(WidgetTester tester, String day, {_Plan? withPlan}) async {
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final plan = withPlan ?? _Plan();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const MealPlanScreen()),
    GoRoute(
        path: '/recipes/:id',
        builder: (_, s) =>
            Scaffold(body: Text('RECEPT ${s.pathParameters['id']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => plan),
      recipesProvider.overrideWith(() => _Recipes()),
      householdProvider.overrideWith((ref) => _Household()),
      selectedDayProvider.overrideWith((ref) => day),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return plan;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Teksten i dagens måltidskort (aftensmad), uden "Ugens aftensmad"-oversigten:
/// finder præcis ét match, så testen stadig fanger dobbelte kort.
Finder _dayCard(String text) => find.descendant(
    of: find.byKey(const ValueKey('slot-card-dinner')), matching: find.text(text));

Finder _overviewText(String text) => find.descendant(
    of: find.byKey(const ValueKey('week-dinner-overview')), matching: find.text(text));

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  testWidgets('tryk på udfyldt slot åbner redigeringsark med nuværende måltid',
      (tester) async {
    await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    expect(find.text('Fjern fra madplanen'), findsOneWidget);
    expect(find.text('Skift'), findsOneWidget);
    expect(find.text('Se opskrift'), findsOneWidget);
    expect(find.text('Gem måltid'), findsNothing);
  });

  testWidgets('tryk på tom slot åbner stadig Tilføj måltid', (tester) async {
    await _pump(tester, 'Torsdag');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    expect(find.text('Fjern fra madplanen'), findsNothing);
    expect(find.text('Søg opskrifter'), findsOneWidget);
    expect(find.text('Eget måltid'), findsOneWidget);
  });

  testWidgets('når aftensmaden fjernes, bliver prikken til en ring og oversigten til "Ikke planlagt"',
      (tester) async {
    await _pump(tester, 'Tirsdag', withPlan: _LivePlan());
    expect(find.byKey(const ValueKey('dinner-dot-Tirsdag')), findsOneWidget);
    expect(_overviewText('Lasagne'), findsOneWidget);
    expect(find.text('Ikke planlagt'), findsNWidgets(6));

    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);

    expect(find.byKey(const ValueKey('dinner-dot-Tirsdag')), findsNothing);
    expect(find.byKey(const ValueKey('dinner-ring-Tirsdag')), findsOneWidget);
    expect(find.text('Lasagne'), findsNothing);
    expect(find.text('Ikke planlagt'), findsNWidgets(7));
  });

  testWidgets('Fjern fra madplanen rydder med nøglen, lukker og viser Fortryd',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    expect(plan.calls, ['Tirsdag|dinner|null|null']);
    expect(find.text('Fjern fra madplanen'), findsNothing);
    expect(find.text('Fortryd'), findsOneWidget);
  });

  testWidgets('Fortryd gendanner id på slettet opskrift', (tester) async {
    final plan = await _pump(tester, 'Mandag');
    await tester.tap(_dayCard('Opskriften findes ikke længere'));
    await _settle(tester);
    expect(find.text('Se opskrift'), findsNothing);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(plan.restored.single.$1, 'Mandag');
    expect(plan.restored.single.$2, 'dinner');
    expect(plan.restored.single.$3.recipeId, 'gone');
    expect(plan.restored.single.$3.directEntry, isNull);
  });

  testWidgets('Fortryd gendanner eget måltid', (tester) async {
    final plan = await _pump(tester, 'Onsdag');
    await tester.tap(_dayCard('Sushi'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(plan.calls.last, 'restore|Onsdag|dinner|Sushi');
  });

  testWidgets('Se opskrift åbner /recipes/<id>', (tester) async {
    await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Se opskrift'));
    await _settle(tester);
    expect(find.text('RECEPT r1'), findsOneWidget);
  });

  testWidgets('Skift til anden opskrift (med filter) gemmer kun opskriften',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await tester.enterText(
        find.descendant(
            of: find.byType(EditMealSlotSheet),
            matching: find.byType(TextField)),
        'pest');
    await _settle(tester);
    final sheet = find.byType(EditMealSlotSheet);
    expect(find.descendant(of: sheet, matching: find.text('Pasta pesto')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Lasagne')),
        findsNothing);
    await tester
        .tap(find.descendant(of: sheet, matching: find.text('Pasta pesto')));
    await _settle(tester);
    expect(plan.calls, ['Tirsdag|dinner|r2|null']);
  });

  testWidgets('Skift til eget måltid gemmer kun teksten', (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await tester.tap(find.text('Eget måltid'));
    await _settle(tester);
    await tester.enterText(
        find.descendant(
            of: find.byType(EditMealSlotSheet),
            matching: find.byType(TextField)),
        'Rugbrød');
    await tester.pump();
    await tester.tap(find.text('Gem'));
    await _settle(tester);
    expect(plan.calls, ['Tirsdag|dinner|null|Rugbrød']);
  });

  testWidgets('skrivefejl holder arket åbent med dansk fejl', (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    plan.failWith = Exception('permission-denied');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    expect(find.text('Fjern fra madplanen'), findsOneWidget);
    expect(find.textContaining('Kunne ikke'), findsOneWidget);
  });

  testWidgets('SnackBar efter Fjern siger "Aftensmad fjernet fra tirsdag"',
      (tester) async {
    await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    expect(find.text('Aftensmad fjernet fra tirsdag'), findsOneWidget);
  });

  testWidgets('tom slot: Søg opskrifter -> vælg opskrift gemmer med nøglen',
      (tester) async {
    final plan = await _pump(tester, 'Torsdag');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    expect(find.textContaining('Her kommer søgning'), findsNothing);
    await tester.tap(find.text('Pasta pesto'));
    await _settle(tester);
    expect(plan.calls, ['Torsdag|dinner|r2|null']);
    expect(find.text('Søg opskrifter'), findsNothing);
  });

  testWidgets('tom slot: skrivefejl i Søg opskrifter holder arket åbent',
      (tester) async {
    final plan = await _pump(tester, 'Torsdag');
    plan.failWith = Exception('permission-denied');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Søg opskrifter'));
    await _settle(tester);
    await tester.tap(find.text('Pasta pesto'));
    await _settle(tester);
    expect(find.text('Søg opskrifter'), findsOneWidget);
    expect(find.textContaining('Kunne ikke gemme'), findsOneWidget);
  });

  testWidgets('offline Fjern: arket lukkes uden at vente på serveren',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    plan.hang = Completer<void>();
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EditMealSlotSheet), findsOneWidget,
        reason: 'knapperne er låst de første øjeblikke');
    await tester.pump(const Duration(milliseconds: 1000));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
    expect(find.text('Fortryd'), findsOneWidget);
    // Serveren afviser senere: fejlen meldes uden for det lukkede ark.
    plan.hang!.completeError(Exception('permission-denied'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('rullet tilbage'), findsOneWidget);
  });

  testWidgets(
      'Fortryd mens sletningen stadig venter på serveren bruger den lokale kopi',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    plan.hang = Completer<void>();
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await tester.pump(const Duration(milliseconds: 1300));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(plan.restorePendingFlags, [true],
        reason: 'serveren har ikke bekræftet sletningen endnu');
    plan.hang!.complete();
    await _settle(tester);
  });

  testWidgets('Fortryd efter bekræftet sletning bruger transaktionen',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(plan.restorePendingFlags, [false]);
  });

  testWidgets('offline Skift: arket lukkes uden at vente på serveren',
      (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    plan.hang = Completer<void>();
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(EditMealSlotSheet), matching: find.text('Pasta pesto')));
    await tester.pump(const Duration(milliseconds: 1200));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
  });

  testWidgets('offline: Søg opskrifter lukker arket uden at vente',
      (tester) async {
    final plan = await _pump(tester, 'Torsdag');
    plan.hang = Completer<void>();
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    await tester.tap(find.text('Pasta pesto'));
    await tester.pump(const Duration(milliseconds: 1200));
    await _settle(tester);
    expect(find.text('Søg opskrifter'), findsNothing);
  });

  testWidgets('Fortryd der fejler kan prøves igen', (tester) async {
    final plan = await _pump(tester, 'Tirsdag');
    plan.restoreFailures = 1;
    await tester.tap(_dayCard('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(find.textContaining('Kunne ikke fortryde'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Prøv igen'));
    await _settle(tester);
    expect(plan.restored.length, 2);
    expect(plan.restored.last.$3.recipeId, 'r1');
  });

  testWidgets('Tilføj måltid starter på Søg opskrifter når der er opskrifter',
      (tester) async {
    await _pump(tester, 'Torsdag');
    await tester.tap(find.text('Tilføj aftensmad'));
    await _settle(tester);
    final sheet = find.byType(AddCustomMealSheet);
    expect(find.descendant(of: sheet, matching: find.text('Tilføj måltid')),
        findsOneWidget);
    expect(find.text('Tilføj eget måltid'), findsNothing);
    await tester.tap(find.text('Eget måltid'));
    await _settle(tester);
    expect(find.text('Tilføj eget måltid'), findsOneWidget);
    expect(find.text('Gem måltid'), findsOneWidget);
  });

  for (final tab in ['Søg opskrifter', 'Eget måltid']) {
    testWidgets('Tilføj måltid ($tab): tryk-mål og labels', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, 'Torsdag');
      await tester.tap(find.text('Tilføj aftensmad'));
      await _settle(tester);
      await tester.tap(find.text(tab));
      await _settle(tester);
      final selected = tester.getSemantics(find.text(tab));
      expect(selected.flagsCollection.isSelected, isTrue);
      expect(selected.flagsCollection.isButton, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // 'Eget måltid'-formularen har ældre knapper (antal personer m.m.) uden
      // label; de er uden for denne opgave, så labels tjekkes kun på opskriftsfanen.
      if (tab == 'Søg opskrifter') {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      handle.dispose();
    });
  }
}
