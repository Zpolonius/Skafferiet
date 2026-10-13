import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/services/recipe_sharing.dart';
import '../auth/auth_provider.dart';
import '../profile/household_provider.dart';
import 'recipe_mapping.dart';

class RecipesNotifier extends StreamNotifier<List<Recipe>> {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  RecipesNotifier({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  @override
  Stream<List<Recipe>> build() {
    final householdId = ref.watch(householdProvider.select((s) => s.householdId));

    if (householdId == null) return Stream.value([]);

    // Server-side filtrering: globale opskrifter (householdId == null) + hustandens egne
    return _firestore
        .collection('recipes')
        .where(Filter.or(
          Filter('householdId', isEqualTo: householdId),
          Filter('householdId', isNull: true),
        ))
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_mapDocToRecipe).toList());
  }

  Recipe _mapDocToRecipe(DocumentSnapshot doc) =>
      recipeFromMap(doc.id, doc.data() as Map<String, dynamic>);

  /// Brugerens eget fornavn til visning på en delt opskrift. Kun skaberen kan
  /// dele en opskrift (firestore.rules), så navnet er altid deres eget.
  String _ownAuthorName() => authorFirstName(_auth.currentUser?.displayName);

  Future<void> addRecipe(Recipe recipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final householdId = ref.read(householdProvider).householdId;

    await _firestore.collection('recipes').add({
      ...recipeToFields(recipe.isShared && recipe.authorName == null
          ? recipe.copyWith(authorName: _ownAuthorName())
          : recipe),
      'createdAt': FieldValue.serverTimestamp(),
      'householdId': householdId,
      'createdBy': user.uid,
    });
  }

  Future<void> updateRecipe(Recipe updatedRecipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('recipes').doc(updatedRecipe.id).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final userHouseholdId = ref.read(householdProvider).householdId;

    if (data['createdBy'] != user.uid && data['householdId'] != userHouseholdId) {
      throw Exception('Sikkerhedsfejl: Bruger har ikke tilladelse til at redigere denne opskrift');
    }

    // Fornavnet gemmes kun, mens opskriften er delt, og er skaberens (ikke
    // nødvendigvis den der redigerer). Slås deling fra, fjernes det igen.
    final fields = recipeToFields(updatedRecipe);
    if (updatedRecipe.isShared) {
      fields['authorName'] = updatedRecipe.authorName ??
          _nonEmptyString(data['authorName']) ??
          _ownAuthorName();
    } else {
      fields['authorName'] = FieldValue.delete();
    }

    await _firestore.collection('recipes').doc(updatedRecipe.id).update(fields);
  }

  /// Holder op med at dele en opskrift: den bliver kun synlig for husstanden,
  /// og fornavnet fjernes. Reglerne tillader det også for skaberen, der har
  /// forladt husstanden (kun de to felter ændres).
  Future<void> stopSharing(String recipeId) async {
    await _firestore.collection('recipes').doc(recipeId).update({
      'visibility': RecipeVisibility.household.key,
      'authorName': FieldValue.delete(),
    });
  }

  static String? _nonEmptyString(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// Gemmer en kopi af en anden husstands delte opskrift i brugerens egen
  /// husstand, og returnerer kopien. Findes der allerede en kopi af den samme
  /// opskrift i husstanden, genbruges den (ingen dubletter). Kopien er privat
  /// (`household`), har brugeren som skaber og bevarer billedets URL, så intet
  /// billede dubleres i Storage. Madplanen skal altid bruge kopien, så den ikke
  /// går i stykker, hvis originalen slettes eller gøres privat igen.
  Future<Recipe> copyToHousehold(Recipe source) async {
    final user = _auth.currentUser;
    final householdId = ref.read(householdProvider).householdId;
    if (user == null || householdId == null) {
      throw StateError('Du skal være logget ind med en husstand for at gemme opskriften');
    }

    final existing = await _firestore
        .collection('recipes')
        .where('householdId', isEqualTo: householdId)
        .where('copiedFrom', isEqualTo: source.id)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return _mapDocToRecipe(existing.docs.first);

    final copy = Recipe(
      id: '',
      title: source.title,
      imageUrl: source.imageUrl,
      calories: source.calories,
      time: source.time,
      category: source.category,
      ingredients: source.ingredients,
      instructions: source.instructions,
      servings: source.servings,
      protein: source.protein,
      carbs: source.carbs,
      fat: source.fat,
      nutritionFromIngredients: source.nutritionFromIngredients,
      copiedFrom: source.id,
    );
    final created = await _firestore.collection('recipes').add({
      ...recipeToFields(copy),
      'createdAt': FieldValue.serverTimestamp(),
      'householdId': householdId,
      'createdBy': user.uid,
    });
    return copy.copyWith(id: created.id, householdId: householdId, createdBy: user.uid);
  }

  Future<void> deleteRecipe(String id) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('recipes').doc(id).get();
    if (!doc.exists) return;

    if (doc.data()!['createdBy'] != user.uid) {
      throw Exception('Sikkerhedsfejl: Kun skaberen kan slette opskriften');
    }

    await _firestore.collection('recipes').doc(id).delete();
  }
}

final recipesProvider = StreamNotifierProvider<RecipesNotifier, List<Recipe>>(() {
  return RecipesNotifier();
});

/// Sættes af andre skærme (fx madplanens søgefelt) for at åbne Opskrifter med
/// markøren i søgefeltet. Opskrifter nulstiller den, når søgefeltet har fået fokus.
final focusRecipeSearchProvider = StateProvider<bool>((ref) => false);

/// Id på den indloggede bruger (null hvis ingen). Følger [authProvider], så
/// den skifter med, når en anden bruger logger ind uden at appen genstartes.
/// Bruges til at afgøre, om man er skaber af en opskrift. Er Firebase ikke
/// startet (fx i widget-tests uden login), er der ingen bruger.
final currentUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(authProvider).user?.uid;
  } catch (_) {
    return null;
  }
});
