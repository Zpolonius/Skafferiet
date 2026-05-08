import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

class _MockMealPlanNotifier extends MealPlanNotifier {
  _MockMealPlanNotifier() : super(firestore: MockFirestore());

  String? capturedDay;
  String? capturedSlot;
  Recipe? capturedRecipe;

  @override
  Future<WeeklyMealPlan> build() async =>
      WeeklyMealPlan(id: 'test', weekStart: DateTime.now(), days: {});

  @override
  Future<void> updateSlot(
    String day,
    String slotType, {
    Recipe? recipe,
    String? directEntry,
  }) async {
    capturedDay = day;
    capturedSlot = slotType;
    capturedRecipe = recipe;
  }
}

final _testRecipe = Recipe(
  id: 'r1',
  title: 'Spaghetti Bolognese',
  category: RecipeCategory.aftensmad,
  calories: 650,
  time: '30 min',
  ingredients: [],
);

// Hjælpefunktion der bygger sheet'en med en route så Navigator.pop() virker
Widget _buildApp(_MockMealPlanNotifier notifier) {
  return ProviderScope(
    overrides: [mealPlanProvider.overrideWith(() => notifier)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProviderScope(
                    overrides: [mealPlanProvider.overrideWith(() => notifier)],
                    child: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
                  ),
                ),
              ),
              child: const Text('Åbn'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Sæt telefon-skærmstørrelse så overflow undgås
  const phoneSize = Size(390, 844);

  group('AddToMealPlanSheet', () {
    testWidgets('viser opskriftens navn og titel', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mealPlanProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spaghetti Bolognese'), findsOneWidget);
      expect(find.text('Tilføj til madplan'), findsOneWidget);
    });

    testWidgets('"Bekræft"-knap er deaktiveret uden valg', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mealPlanProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('"Bekræft"-knap aktiveres når dag og måltid er valgt', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mealPlanProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mandag'));
      await tester.pump();
      await tester.tap(find.text('Aftensmad'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('kalder updateSlot med korrekte værdier', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(_buildApp(notifier));

      // Naviger til sheet via route (så Navigator.pop() virker)
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onsdag'));
      await tester.pump();
      await tester.tap(find.text('Frokost'));
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pump(); // lad async-updateSlot køre
      await tester.pump(); // lad Navigator.pop animere

      expect(notifier.capturedDay, 'Onsdag');
      expect(notifier.capturedSlot, 'Frokost');
      expect(notifier.capturedRecipe?.id, _testRecipe.id);
    });
  });
}
