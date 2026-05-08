import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../profile/household_provider.dart';

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
        orElse: () => RecipeCategory.aftensmad,
      ),
      ingredients: (data['ingredients'] as List? ?? [])
          .map((i) => Ingredient(
                name: i['name'],
                quantity: (i['quantity'] as num).toDouble(),
                unit: i['unit'],
                category: i['category'],
              ))
          .toList(),
      instructions: List<String>.from(data['instructions'] ?? []),
      householdId: data['householdId'],
      createdBy: data['createdBy'],
    );
  }

  Future<void> addRecipe(Recipe recipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final householdId = ref.read(householdProvider).householdId;

    await _firestore.collection('recipes').add({
      'title': recipe.title,
      'imageUrl': recipe.imageUrl,
      'calories': recipe.calories,
      'time': recipe.time,
      'category': recipe.category.toString(),
      'ingredients': recipe.ingredients
          .map((i) => {
                'name': i.name,
                'quantity': i.quantity,
                'unit': i.unit,
                'category': i.category,
              })
          .toList(),
      'instructions': recipe.instructions,
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

    await _firestore.collection('recipes').doc(updatedRecipe.id).update({
      'title': updatedRecipe.title,
      'imageUrl': updatedRecipe.imageUrl,
      'calories': updatedRecipe.calories,
      'time': updatedRecipe.time,
      'category': updatedRecipe.category.toString(),
      'ingredients': updatedRecipe.ingredients
          .map((i) => {
                'name': i.name,
                'quantity': i.quantity,
                'unit': i.unit,
                'category': i.category,
              })
          .toList(),
      'instructions': updatedRecipe.instructions,
    });
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
