enum RecipeCategory { breakfast, lunch, dinner, snack }

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

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
    };
  }

  factory Ingredient.fromMap(Map<String, dynamic> map) {
    return Ingredient(
      name: map['name'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? '',
      category: map['category'] ?? '',
    );
  }
}

class Recipe {
  final String id;
  final String title;
  final RecipeCategory category;
  final List<Ingredient> ingredients;
  final String? imageUrl;
  final String createdBy;

  Recipe({
    required this.id,
    required this.title,
    required this.category,
    required this.ingredients,
    this.imageUrl,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category.name,
      'ingredients': ingredients.map((x) => x.toMap()).toList(),
      'imageUrl': imageUrl,
      'createdBy': createdBy,
    };
  }

  factory Recipe.fromMap(Map<String, dynamic> map, String id) {
    return Recipe(
      id: id,
      title: map['title'] ?? '',
      category: RecipeCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => RecipeCategory.dinner,
      ),
      ingredients: List<Ingredient>.from(
        (map['ingredients'] ?? []).map((x) => Ingredient.fromMap(x)),
      ),
      imageUrl: map['imageUrl'],
      createdBy: map['createdBy'] ?? '',
    );
  }
}
