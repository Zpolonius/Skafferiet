import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Plan extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async {
    final lasagne = Recipe(
      id: 'r1',
      title: 'Lasagne',
      calories: 1850,
      time: '45 min',
      category: RecipeCategory.aftensmad,
    );
    return WeeklyMealPlan(
      id: 'w',
      weekStart: DateTime(2026, 9, 28),
      days: {
        for (final day in ['Mandag', 'Lørdag'])
          day: DailyPlan(
            breakfast: MealSlot(),
            lunch: MealSlot(),
            dinner: MealSlot(recipe: lasagne),
            snack: MealSlot(),
          ),
      },
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  // En overskrift, der løber ud over kanten, får testen til at fejle af sig selv
  // (Flutter melder "RenderFlex overflowed").
  for (final (width, day) in [(390.0, 'Mandag'), (320.0, 'Lørdag')]) {
    testWidgets('madplanen løber ikke ud over kanten i $width pt ($day, med kalorier)',
        (tester) async {
      final user = _User();
      when(() => user.displayName).thenReturn('Mette');
      when(() => user.photoURL).thenReturn(null);
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
          mealPlanProvider.overrideWith(() => _Plan()),
          householdProvider.overrideWith((ref) => _Household()),
          selectedDayProvider.overrideWith((ref) => day),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const MealPlanScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('${day}ens madplan'), findsOneWidget);
      expect(find.text('Overfør til indkøb'), findsOneWidget);
      expect(find.textContaining('kcal'), findsWidgets);
    });
  }
}
