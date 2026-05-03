import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';

class RecipesNotifier extends AsyncNotifier<List<Recipe>> {
  @override
  Future<List<Recipe>> build() async {
    // Simuler netværkskald
    await Future.delayed(const Duration(milliseconds: 800));
    return _mockRecipes;
  }

  Future<void> addRecipe(Recipe recipe) async {
    if (state.value == null) return;
    state = AsyncValue.data([...state.value!, recipe]);
  }

  Future<void> updateRecipe(Recipe updatedRecipe) async {
    if (state.value == null) return;
    final currentRecipes = List<Recipe>.from(state.value!);
    final index = currentRecipes.indexWhere((r) => r.id == updatedRecipe.id);
    if (index != -1) {
      currentRecipes[index] = updatedRecipe;
      state = AsyncValue.data(currentRecipes);
    }
  }
}

final recipesProvider = AsyncNotifierProvider<RecipesNotifier, List<Recipe>>(() {
  return RecipesNotifier();
});

final _mockRecipes = [
  Recipe(
    id: '1',
    title: 'Avocado Toast med Spejlæg',
    category: RecipeCategory.Morgenmad,
    imageUrl: 'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800',
    calories: 350,
    time: '15 min',
    ingredients: [
      Ingredient(name: 'Avocado', quantity: 1, unit: 'stk', category: 'Frugt & Grønt'),
      Ingredient(name: 'Rugbrød', quantity: 2, unit: 'skiver', category: 'Brød'),
      Ingredient(name: 'Æg', quantity: 1, unit: 'stk', category: 'Mejeri'),
    ],
  ),
  Recipe(
    id: '2',
    title: 'Grillet Kyllingesalat',
    category: RecipeCategory.Frokost,
    imageUrl: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800',
    calories: 450,
    time: '20 min',
    ingredients: [
      Ingredient(name: 'Kyllingebryst', quantity: 200, unit: 'g', category: 'Kød & Fisk'),
      Ingredient(name: 'Salat', quantity: 1, unit: 'hoved', category: 'Frugt & Grønt'),
      Ingredient(name: 'Tomat', quantity: 4, unit: 'stk', category: 'Frugt & Grønt'),
    ],
  ),
  Recipe(
    id: '3',
    title: 'Klassisk Lasagne',
    category: RecipeCategory.Aftensmad,
    imageUrl: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800',
    calories: 700,
    time: '60 min',
    ingredients: [
      Ingredient(name: 'Hakket oksekød', quantity: 500, unit: 'g', category: 'Kød & Fisk'),
      Ingredient(name: 'Lasagneplader', quantity: 12, unit: 'stk', category: 'Kolonial'),
    ],
  ),
  Recipe(
    id: '4',
    title: 'Grillet Laks med Urter',
    category: RecipeCategory.Aftensmad,
    imageUrl: 'https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=800',
    calories: 550,
    time: '25 min',
    ingredients: [
      Ingredient(name: 'Lakseside', quantity: 600, unit: 'g', category: 'Kød & Fisk'),
      Ingredient(name: 'Citron', quantity: 1, unit: 'stk', category: 'Frugt & Grønt'),
    ],
  ),
];
