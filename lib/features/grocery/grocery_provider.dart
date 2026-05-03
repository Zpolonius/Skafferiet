import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';
import '../profile/household_provider.dart';

class GroceryListNotifier extends AsyncNotifier<List<GroceryItem>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<List<GroceryItem>> build() async {
    final household = ref.watch(householdProvider);
    final householdId = household.householdId;

    if (householdId == null) return [];

    // Stream fra Firestore
    final stream = _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .orderBy('createdAt', descending: true)
        .snapshots();

    // Vi konverterer streamen til AsyncValue
    // Da build() returnerer en Future, bruger vi stream.first for den initiale værdi,
    // men vi vil gerne have den til at opdatere løbende.
    // I Riverpod 2.0 AsyncNotifier, kan vi bruge 'ref.listen' eller 'state = ' i en stream listen.
    
    _listenToStream(householdId);
    
    final firstSnapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .orderBy('createdAt', descending: true)
        .get();

    return firstSnapshot.docs
        .map((doc) => GroceryItem.fromMap(doc.data(), doc.id))
        .toList();
  }

  void _listenToStream(String householdId) {
    _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      state = AsyncValue.data(
        snapshot.docs.map((doc) => GroceryItem.fromMap(doc.data(), doc.id)).toList(),
      );
    });
  }

  Future<void> toggleItem(String id) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;

    final itemDoc = _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .doc(id);
    
    final doc = await itemDoc.get();
    if (doc.exists) {
      final current = doc.data()?['isChecked'] ?? false;
      await itemDoc.update({'isChecked': !current});
    }
  }

  Future<void> removeItem(String id) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;

    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .doc(id)
        .delete();
  }

  Future<void> addItem(GroceryItem item) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;

    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .add(item.toMap());
  }

  Future<void> updateQuantity(String id, String newQuantity) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;

    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .doc(id)
        .update({'quantity': newQuantity});
  }
}

final groceryListProvider = AsyncNotifierProvider<GroceryListNotifier, List<GroceryItem>>(() {
  return GroceryListNotifier();
});
