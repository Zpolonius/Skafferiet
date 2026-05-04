import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';

class RecipesNotifier extends StreamNotifier<List<Recipe>> {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  RecipesNotifier({FirebaseFirestore? firestore, FirebaseAuth? auth}) 
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  @override
  Stream<List<Recipe>> build() {
    final householdId = ref.watch(householdProvider.select((s) => s.householdId));

    // Vi henter både globale opskrifter og dem der tilhører husstanden
    // Da Firestore ikke understøtter 'OR' på tværs af værdier og null på en nem måde uden index,
    // kan vi enten lave to streams og merge dem, eller gemme 'global' som en værdi.
    // For simpelhedens skyld henter vi dem der matcher householdId eller har householdId == null.
    
    return _firestore
        .collection('recipes')
        .snapshots()
        .map((snapshot) {
          final allRecipes = snapshot.docs.map((doc) => _mapDocToRecipe(doc)).toList();
          // Manuel filtrering i koden for at sikre både globale og egne opskrifter
          return allRecipes.where((r) => r.householdId == null || r.householdId == householdId).toList();
        });
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
      householdId: data['householdId'],
      createdBy: data['createdBy'],
    );
  }

  Future<void> addRecipe(Recipe recipe) async {
    final user = _auth.currentUser;
    final householdId = ref.read(householdProvider).householdId;
    if (user == null) return;

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
      'householdId': householdId,
      'createdBy': user.uid,
    });
  }

  Future<void> updateRecipe(Recipe updatedRecipe) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // SIKKERHED: Tjek om brugeren har lov til at redigere
    final doc = await _firestore.collection('recipes').doc(updatedRecipe.id).get();
    if (!doc.exists) return;
    
    final data = doc.data()!;
    final ownerId = data['createdBy'];
    final hId = data['householdId'];
    final userHouseholdId = ref.read(householdProvider).householdId;

    // Kun skaberen eller medlemmer af samme husstand må redigere
    if (ownerId != user.uid && hId != userHouseholdId) {
      print('Sikkerhedsfejl: Bruger har ikke tilladelse til at redigere denne opskrift');
      return;
    }

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
  }

  Future<void> deleteRecipe(String id) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('recipes').doc(id).get();
    if (!doc.exists) return;
    
    if (doc.data()!['createdBy'] != user.uid) {
      print('Sikkerhedsfejl: Kun skaberen kan slette opskriften');
      return;
    }

    await _firestore.collection('recipes').doc(id).delete();
  }
}

final recipesProvider = StreamNotifierProvider<RecipesNotifier, List<Recipe>>(() {
  return RecipesNotifier();
});
