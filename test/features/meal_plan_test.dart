// ignore_for_file: subtype_of_sealed_class

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}
class MockWriteBatch extends Mock implements WriteBatch {}

class _TestRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  final List<Recipe> recipes;
  _TestRecipesNotifier([this.recipes = const []]);

  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);
}

class _TestHouseholdNotifier extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _TestHouseholdNotifier(super.state);
}

void main() {
  setUpAll(() {
    registerFallbackValue(MockDocumentReference());
    registerFallbackValue(SetOptions(merge: true));
  });

  group('MealPlanNotifier Tests', () {
    late MockFirestore mockFirestore;
    late MockCollectionReference mockHouseholdsCollection;
    late MockDocumentReference mockHouseholdDoc;
    late MockCollectionReference mockMealPlansCollection;
    late MockDocumentReference mockMealPlanDoc;
    late MockDocumentSnapshot mockMealPlanSnapshot;
    late MockCollectionReference mockGroceryCollection;
    late MockDocumentReference mockGroceryDoc;
    late MockWriteBatch mockBatch;

    setUp(() {
      mockFirestore = MockFirestore();
      mockHouseholdsCollection = MockCollectionReference();
      mockHouseholdDoc = MockDocumentReference();
      mockMealPlansCollection = MockCollectionReference();
      mockMealPlanDoc = MockDocumentReference();
      mockMealPlanSnapshot = MockDocumentSnapshot();
      mockGroceryCollection = MockCollectionReference();
      mockGroceryDoc = MockDocumentReference();
      mockBatch = MockWriteBatch();

      when(() => mockFirestore.collection('households')).thenReturn(mockHouseholdsCollection);
      when(() => mockHouseholdsCollection.doc(any())).thenReturn(mockHouseholdDoc);
      when(() => mockHouseholdDoc.collection('meal_plans')).thenReturn(mockMealPlansCollection);
      when(() => mockMealPlansCollection.doc(any())).thenReturn(mockMealPlanDoc);
      when(() => mockMealPlanDoc.get()).thenAnswer((_) async => mockMealPlanSnapshot);
      when(() => mockMealPlanSnapshot.exists).thenReturn(false);

      when(() => mockMealPlanDoc.set(any(), any())).thenAnswer((_) async {});

      when(() => mockHouseholdDoc.collection('grocery_list')).thenReturn(mockGroceryCollection);
      when(() => mockGroceryCollection.doc(any())).thenReturn(mockGroceryDoc);
      when(() => mockGroceryCollection.doc()).thenReturn(mockGroceryDoc);

      when(() => mockFirestore.batch()).thenReturn(mockBatch);
      when(() => mockBatch.set(any(), any())).thenReturn(null);
      when(() => mockBatch.commit()).thenAnswer((_) async {});
    });

    test('updateSlot should call set on Firestore with correct data', () async {
      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith(
            (ref) => _TestHouseholdNotifier(HouseholdState(householdId: 'hh-123')),
          ),
          recipesProvider.overrideWith(() => _TestRecipesNotifier()),
          mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: mockFirestore)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(mealPlanProvider.future);

      final notifier = container.read(mealPlanProvider.notifier);
      await notifier.updateSlot('Mandag', 'Aftensmad', directEntry: 'Sushi');

      verify(() => mockMealPlanDoc.set({
        'days': {
          'Mandag': {
            'aftensmad': {
              'recipeId': null,
              'directEntry': 'Sushi',
            },
          },
        },
      }, any())).called(1);
    });

    test('transferToShoppingList should add recipe ingredients to grocery list', () async {
      final testRecipe = Recipe(
        id: 'r1',
        title: 'Pasta Bolognese',
        category: RecipeCategory.aftensmad,
        calories: 600,
        time: '30 min',
        ingredients: [
          Ingredient(name: 'Pasta', quantity: 200, unit: 'g', category: 'Kolonial'),
          Ingredient(name: 'Hakket oksekød', quantity: 400, unit: 'g', category: 'Kød'),
        ],
      );

      when(() => mockMealPlanSnapshot.exists).thenReturn(true);
      when(() => mockMealPlanSnapshot.id).thenReturn('2026-09-14');
      when(() => mockMealPlanSnapshot.data()).thenReturn({
        'days': {
          'Mandag': {
            'dinner': {
              'recipeId': 'r1',
            },
          },
        },
      });

      final container = ProviderContainer(
        overrides: [
          householdProvider.overrideWith(
            (ref) => _TestHouseholdNotifier(HouseholdState(householdId: 'hh-123')),
          ),
          recipesProvider.overrideWith(() => _TestRecipesNotifier([testRecipe])),
          mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: mockFirestore)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(recipesProvider.future);
      await container.read(mealPlanProvider.future);

      final mealNotifier = container.read(mealPlanProvider.notifier);
      final count = await mealNotifier.transferToShoppingList();

      expect(count, 2);
      verify(() => mockBatch.set<Map<String, dynamic>>(any(), any())).called(2);
      verify(() => mockBatch.commit()).called(1);
    });
  });
}
