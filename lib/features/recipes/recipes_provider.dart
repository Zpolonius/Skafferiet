import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';

class RecipesNotifier extends AsyncNotifier<List<Recipe>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<Recipe>> build() async {
    // Vi henter alle opskrifter (kunne senere filtreres på husholdning)
    final snapshot = await _firestore.collection('recipes').get();
    
    if (snapshot.docs.isEmpty) {
      // Hvis databasen er helt tom, kan vi uploade vores mock data én gang
      // Men for nu returnerer vi bare en tom liste eller mock data hvis man vil
      return []; 
    }

    return snapshot.docs.map((doc) => _mapDocToRecipe(doc)).toList();
  }

  Recipe _mapDocToRecipe(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Recipe(
      id: doc.id,
      title: data['title'] ?? '',
      imageUrl: data['imageUrl'],
      calories: data['calories'] ?? 0,
      time: data['time'] ?? '',
      category: RecipeCategory.values.firstWhere(
        (e) => e.toString() == data['category'],
        orElse: () => RecipeCategory.Aftensmad,
      ),
      ingredients: (data['ingredients'] as List? ?? []).map((i) => Ingredient(
        name: i['name'],
        quantity: (i['quantity'] as num).toDouble(),
        unit: i['unit'],
        category: i['category'],
      )).toList(),
      instructions: List<String>.from(data['instructions'] ?? []),
    );
  }

  Future<void> addRecipe(Recipe recipe) async {
    await _firestore.collection('recipes').add({
      'title': recipe.title,
      'imageUrl': recipe.imageUrl,
      'calories': recipe.calories,
      'time': recipe.time,
      'category': recipe.category.toString(),
      'ingredients': recipe.ingredients.map((i) => {
        'name': i.name,
        'quantity': i.quantity,
        'unit': i.unit,
        'category': i.category,
      }).toList(),
      'instructions': recipe.instructions,
      'createdAt': FieldValue.serverTimestamp(),
    });
    ref.invalidateSelf();
  }

  Future<void> updateRecipe(Recipe updatedRecipe) async {
    await _firestore.collection('recipes').doc(updatedRecipe.id).update({
      'title': updatedRecipe.title,
      'imageUrl': updatedRecipe.imageUrl,
      'calories': updatedRecipe.calories,
      'time': updatedRecipe.time,
      'category': updatedRecipe.category.toString(),
      'ingredients': updatedRecipe.ingredients.map((i) => {
        'name': i.name,
        'quantity': i.quantity,
        'unit': i.unit,
        'category': i.category,
      }).toList(),
      'instructions': updatedRecipe.instructions,
    });
    ref.invalidateSelf();
  }
}

final recipesProvider = AsyncNotifierProvider<RecipesNotifier, List<Recipe>>(() {
  return RecipesNotifier();
});
