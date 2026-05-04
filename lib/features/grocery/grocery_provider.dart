import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';
import '../profile/household_provider.dart';

class GroceryListNotifier extends StreamNotifier<List<GroceryItem>> {
  final FirebaseFirestore _firestore;

  GroceryListNotifier({FirebaseFirestore? firestore}) 
      : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<GroceryItem>> build() {
    final household = ref.watch(householdProvider);
    final householdId = household.householdId;

    if (householdId == null) return Stream.value([]);

    return _firestore
        .collection('households')
        .doc(householdId)
        .collection('grocery_list')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroceryItem.fromMap(doc.data(), doc.id))
            .toList());
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

final groceryListProvider = StreamNotifierProvider<GroceryListNotifier, List<GroceryItem>>(() {
  return GroceryListNotifier();
});

