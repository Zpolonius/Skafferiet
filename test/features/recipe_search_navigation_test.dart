import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_screen.dart';

// Apple afviser knapper, der ikke gør noget (retningslinje 2.1). Opskrifter
// havde en filter-knap og et favorit-hjerte uden funktion, og madplanens
// søgefelt kunne man skrive i uden at der skete noget.

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Recipes extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value([
        Recipe(
            id: 'r1',
            title: 'Lasagne',
            calories: 500,
            time: '45 min',
            category: RecipeCategory.aftensmad),
      ]);
}

class _Household extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Plan extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async =>
      WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 9, 28), days: {});
}

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, String start) async {
    final user = _User();
    when(() => user.displayName).thenReturn('Mette');
    when(() => user.photoURL).thenReturn(null);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      recipesProvider.overrideWith(() => _Recipes()),
      mealPlanProvider.overrideWith(() => _Plan()),
      householdProvider.overrideWith((ref) => _Household()),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: start, routes: [
      GoRoute(path: '/meal-plan', builder: (_, __) => const MealPlanScreen()),
      GoRoute(path: '/recipes', builder: (_, __) => const RecipesScreen()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('opskrifter har ingen filter-knap og intet favorit-hjerte uden funktion',
      (tester) async {
    await pump(tester, '/recipes');

    expect(find.text('Lasagne'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('madplanens søgefelt åbner Opskrifter med markøren i søgefeltet', (tester) async {
    await pump(tester, '/meal-plan');

    final mealPlanField = tester.widget<TextField>(find.byType(TextField).first);
    expect(mealPlanField.readOnly, true, reason: 'man skal ikke kunne skrive forgæves');

    await tester.tap(find.text('Find opskrifter til din plan...'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipesScreen), findsOneWidget);
    final search = tester.widget<EditableText>(find.descendant(
      of: find.widgetWithText(TextField, 'Søg i opskrifter, ingredienser...'),
      matching: find.byType(EditableText),
    ));
    expect(search.focusNode.hasFocus, true);
    // Anmodningen er brugt, så næste besøg på Opskrifter ikke åbner tastaturet.
    expect(container.read(focusRecipeSearchProvider), false);
  });

  testWidgets('virker også, når Opskrifter-fanen allerede er åbnet (faner som i appen)',
      (tester) async {
    await pump(tester, '/recipes');
    final router = GoRouter(initialLocation: '/recipes', routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => shell,
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/meal-plan', builder: (_, __) => const MealPlanScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/recipes', builder: (_, __) => const RecipesScreen()),
          ]),
        ],
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Opskrifter er bygget; skift til madplanen og tryk på søgefeltet dér.
    router.go('/meal-plan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find opskrifter til din plan...'));
    await tester.pumpAndSettle();

    final search = tester.widget<EditableText>(find.descendant(
      of: find.widgetWithText(TextField, 'Søg i opskrifter, ingredienser...'),
      matching: find.byType(EditableText),
    ));
    expect(search.focusNode.hasFocus, true);
    expect(container.read(focusRecipeSearchProvider), false);
  });
}
