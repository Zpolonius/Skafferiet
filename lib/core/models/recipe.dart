enum RecipeCategory { morgenmad, frokost, aftensmad, snack }

/// Næringsværdier. Bruges både pr. 100 g/ml på en ingrediens og som
/// beregnet total for en hel opskrift.
class Nutrition {
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  const Nutrition({
    this.kcal = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  static const zero = Nutrition();

  Nutrition operator +(Nutrition other) => Nutrition(
        kcal: kcal + other.kcal,
        protein: protein + other.protein,
        carbs: carbs + other.carbs,
        fat: fat + other.fat,
      );

  Nutrition scale(double factor) => Nutrition(
        kcal: kcal * factor,
        protein: protein * factor,
        carbs: carbs * factor,
        fat: fat * factor,
      );

  Map<String, dynamic> toMap() => {
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };

  /// Returnerer null hvis data mangler eller er ugyldige (fx negative tal),
  /// så en ødelagt værdi i databasen aldrig indgår i en beregning.
  static Nutrition? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? read(String key) {
      final v = raw[key];
      if (v == null) return 0;
      if (v is! num || !v.isFinite || v < 0) return null;
      return v.toDouble();
    }

    final kcal = read('kcal');
    final protein = read('protein');
    final carbs = read('carbs');
    final fat = read('fat');
    if (kcal == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    return Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat);
  }
}

class Ingredient {
  final String name;
  final double quantity;
  final String unit;
  final String category;

  /// Valgfri næring pr. 100 g (eller 100 ml for flydende enheder).
  final Nutrition? nutritionPer100;

  Ingredient({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.nutritionPer100,
  });

  Ingredient copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? category,
    Nutrition? nutritionPer100,
  }) {
    return Ingredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      nutritionPer100: nutritionPer100 ?? this.nutritionPer100,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'category': category,
        if (nutritionPer100 != null) 'nutrition': nutritionPer100!.toMap(),
      };

  factory Ingredient.fromMap(Map<String, dynamic> map) {
    return Ingredient(
      name: map['name'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: map['unit'] ?? '',
      category: map['category'] ?? 'Andet',
      nutritionPer100: Nutrition.fromMap(map['nutrition']),
    );
  }
}

class Recipe {
  final String id;
  final String title;
  final String? imageUrl;

  /// Kalorier pr. portion. Madplanen lægger disse sammen pr. dag.
  final int calories;
  final String time;
  final RecipeCategory category;
  final List<Ingredient> ingredients;
  final List<String> instructions;
  final String? householdId; // Null hvis det er en global opskrift
  final String? createdBy;

  /// Antal portioner opskriften giver. Null for ældre opskrifter.
  final int? servings;

  /// Makronæringsstoffer i gram pr. portion. Null = ikke angivet.
  final double? protein;
  final double? carbs;
  final double? fat;

  /// True når næringen pr. portion er beregnet ud fra ingredienserne
  /// (brugeren har ikke selv skrevet tallene).
  final bool nutritionFromIngredients;

  Recipe({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.calories,
    required this.time,
    required this.category,
    this.ingredients = const [],
    this.instructions = const [],
    this.householdId,
    this.createdBy,
    this.servings,
    this.protein,
    this.carbs,
    this.fat,
    this.nutritionFromIngredients = false,
  });

  bool get hasNutrition => calories > 0 || protein != null || carbs != null || fat != null;

  Recipe copyWith({
    String? id,
    String? title,
    String? imageUrl,
    int? calories,
    String? time,
    RecipeCategory? category,
    List<Ingredient>? ingredients,
    List<String>? instructions,
    String? householdId,
    String? createdBy,
    int? servings,
    double? protein,
    double? carbs,
    double? fat,
    bool? nutritionFromIngredients,
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
      householdId: householdId ?? this.householdId,
      createdBy: createdBy ?? this.createdBy,
      servings: servings ?? this.servings,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      nutritionFromIngredients: nutritionFromIngredients ?? this.nutritionFromIngredients,
    );
  }
}
