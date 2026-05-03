enum RecipeCategory { Morgenmad, Frokost, Aftensmad, Snack }

class Ingredient {
  final String name;
  final double quantity;
  final String unit;
  final String category;

  Ingredient({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
  });

  Ingredient copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? category,
  }) {
    return Ingredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
    );
  }
}

class Recipe {
  final String id;
  final String title;
  final String? imageUrl;
  final int calories;
  final String time;
  final RecipeCategory category;
  final List<Ingredient> ingredients;
  final List<String> instructions;

  Recipe({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.calories,
    required this.time,
    required this.category,
    this.ingredients = const [],
    this.instructions = const [],
  });

  Recipe copyWith({
    String? id,
    String? title,
    String? imageUrl,
    int? calories,
    String? time,
    RecipeCategory? category,
    List<Ingredient>? ingredients,
    List<String>? instructions,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      calories: calories ?? this.calories,
      time: time ?? this.time,
      category: category ?? this.category,
      ingredients: ingredients ?? this.ingredients,
      instructions: instructions ?? this.instructions,
    );
  }
}
