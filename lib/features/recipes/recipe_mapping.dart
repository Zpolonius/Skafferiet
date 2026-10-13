import '../../core/models/recipe.dart';

/// Opskrift ud fra et Firestore-dokument. Tåler ældre dokumenter, hvor
/// nyere felter (visibility, authorName, …) mangler.
Recipe recipeFromMap(String id, Map<String, dynamic> data) {
  return Recipe(
    id: id,
    title: data['title'] ?? '',
    imageUrl: data['imageUrl'],
    calories: (data['calories'] as num?)?.round() ?? 0,
    time: data['time'] ?? '',
    category: RecipeCategory.values.firstWhere(
      (e) => e.toString() == data['category'],
      orElse: () => RecipeCategory.aftensmad,
    ),
    ingredients: (data['ingredients'] as List? ?? [])
        .map((i) => Ingredient.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList(),
    instructions: List<String>.from(data['instructions'] ?? []),
    householdId: data['householdId'],
    createdBy: data['createdBy'],
    servings: (data['servings'] as num?)?.toInt(),
    protein: (data['protein'] as num?)?.toDouble(),
    carbs: (data['carbs'] as num?)?.toDouble(),
    fat: (data['fat'] as num?)?.toDouble(),
    nutritionFromIngredients: data['nutritionFromIngredients'] == true,
    visibility: RecipeVisibility.parse(data['visibility']),
    authorName: _nonEmpty(data['authorName']),
    copiedFrom: _nonEmpty(data['copiedFrom']),
  );
}

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Titlen med små bogstaver til præfiks-søgning. Udelades, hvis små bogstaver
/// ændrer antallet af tegn (fx tyrkisk İ), da reglerne kræver samme længde.
String? _titleLower(String title) {
  final lower = title.toLowerCase();
  return lower.runes.length == title.runes.length ? lower : null;
}

/// Felter der er fælles for oprettelse og opdatering. `titleLower` bruges til
/// præfiks-søgning i Fællesskab. `authorName` skrives kun på delte opskrifter.
Map<String, dynamic> recipeToFields(Recipe recipe) => {
      'title': recipe.title,
      if (_titleLower(recipe.title) case final lower?) 'titleLower': lower,
      'imageUrl': recipe.imageUrl,
      'calories': recipe.calories,
      'time': recipe.time,
      'category': recipe.category.toString(),
      'ingredients': recipe.ingredients.map((i) => i.toMap()).toList(),
      'instructions': recipe.instructions,
      'servings': recipe.servings,
      'protein': recipe.protein,
      'carbs': recipe.carbs,
      'fat': recipe.fat,
      'nutritionFromIngredients': recipe.nutritionFromIngredients,
      'visibility': recipe.visibility.key,
      if (recipe.isShared && recipe.authorName != null)
        'authorName': recipe.authorName,
      if (recipe.copiedFrom != null) 'copiedFrom': recipe.copiedFrom,
    };
