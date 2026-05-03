import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';

final recipesProvider = Provider<List<Recipe>>((ref) {
  return _mockRecipes;
});

final _mockRecipes = [
  Recipe(
    id: '1',
    title: 'Avocado Toast with Poached Egg',
    category: RecipeCategory.breakfast,
    createdBy: 'user1',
    imageUrl: 'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800',
    ingredients: [
      Ingredient(name: 'Avocado', quantity: 1, unit: 'stk', category: 'Grønt'),
      Ingredient(name: 'Rugbrød', quantity: 2, unit: 'skiver', category: 'Brød'),
      Ingredient(name: 'Æg', quantity: 1, unit: 'stk', category: 'Mejeri'),
    ],
  ),
  Recipe(
    id: '2',
    title: 'Grilled Chicken Garden Salad',
    category: RecipeCategory.lunch,
    createdBy: 'user1',
    imageUrl: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800',
    ingredients: [
      Ingredient(name: 'Kyllingebryst', quantity: 200, unit: 'g', category: 'Kød'),
      Ingredient(name: 'Salat', quantity: 1, unit: 'hoved', category: 'Grønt'),
      Ingredient(name: 'Tomat', quantity: 4, unit: 'stk', category: 'Grønt'),
    ],
  ),
  Recipe(
    id: '3',
    title: 'Hearty Minestrone Soup',
    category: RecipeCategory.dinner,
    createdBy: 'user1',
    imageUrl: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800',
    ingredients: [],
  ),
  Recipe(
    id: '4',
    title: 'Lemon Herb Grilled Salmon',
    category: RecipeCategory.dinner,
    createdBy: 'user1',
    imageUrl: 'https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=800',
    ingredients: [],
  ),
];
