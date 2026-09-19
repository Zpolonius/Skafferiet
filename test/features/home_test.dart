import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/home/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  MockAuthNotifier(super.state);
}

class MockHouseholdNotifier extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  MockHouseholdNotifier(super.state);
}

class MockRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => const Stream.empty();
}

class MockMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async => WeeklyMealPlan(id: 'test', weekStart: DateTime.now(), days: {});
}

class _MockUser extends Mock implements User {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('da_DK', null);
  });

  testWidgets('HomeScreen displays correct greeting and user name', (WidgetTester tester) async {
    final mockUser = _MockUser();
    when(() => mockUser.displayName).thenReturn('Mette');
    
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(AuthState(user: mockUser))),
          householdProvider.overrideWith((ref) => MockHouseholdNotifier(HouseholdState())),
          recipesProvider.overrideWith(() => MockRecipesNotifier()),
          mealPlanProvider.overrideWith(() => MockMealPlanNotifier()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Mette!'), findsOneWidget);
    expect(find.text('Her er dit overblik for i dag.'), findsOneWidget);
  });

  testWidgets('HomeScreen shows quick action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(AuthState())),
          householdProvider.overrideWith((ref) => MockHouseholdNotifier(HouseholdState())),
          recipesProvider.overrideWith(() => MockRecipesNotifier()),
          mealPlanProvider.overrideWith(() => MockMealPlanNotifier()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tilføj måltid'), findsOneWidget);
    expect(find.text('Tilføj vare'), findsOneWidget);
  });
}
