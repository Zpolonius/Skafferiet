import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/grocery_item.dart';
import '../../../core/models/recurring_item.dart';
import '../../../core/services/recurring_schedule.dart';

/// Al adgang til databasen for faste varer. Logikken i
/// `RecurringItemsService` kender kun dette interface, så den kan testes
/// med en falsk udgave uden Firebase.
abstract interface class RecurringItemsRepository {
  Stream<List<RecurringItem>> watch(String householdId);

  /// Opretter [item]. Er [linkGroceryItemId] sat, er det en vare der allerede
  /// står på listen og nu gøres fast – den markeres som fast vare, og der
  /// tilføjes ikke en ny, så længe den ikke er krydset af.
  Future<void> create(
    String householdId,
    RecurringItem item, {
    String? linkGroceryItemId,
  });

  /// Gemmer de felter brugeren kan redigere. `nextDate` gemmes også, da den
  /// ændres når intervallet ændres.
  Future<void> update(String householdId, RecurringItem item);

  Future<void> delete(String householdId, String id);

  /// Gemmer husstandens indkøbsdag og flytter de ugentlige varer til den nye
  /// dag – i én samlet skrivning, så de ikke kan komme ud af trit.
  Future<void> setShoppingWeekday(
    String householdId,
    int weekday,
    Map<String, DateTime> newNextDates,
  );

  /// Behandler én forfalden fast vare atomisk (en transaktion): læser den
  /// friske version, lader `decideOccurrence` afgøre hvad der skal ske,
  /// lægger evt. varen på listen og rykker næste dato frem. Har en anden
  /// telefon gjort det imens, sker der ingenting.
  Future<void> processOccurrence(
    String householdId,
    String recurringId, {
    required DateTime today,
    required DateTime now,
  });
}

class FirestoreRecurringItemsRepository implements RecurringItemsRepository {
  final FirebaseFirestore _firestore;

  FirestoreRecurringItemsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _household(String householdId) =>
      _firestore.collection('households').doc(householdId);

  CollectionReference<Map<String, dynamic>> _items(String householdId) =>
      _household(householdId).collection('recurring_items');

  CollectionReference<Map<String, dynamic>> _groceries(String householdId) =>
      _household(householdId).collection('grocery_list');

  @override
  Stream<List<RecurringItem>> watch(String householdId) {
    return _items(householdId).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => RecurringItem.fromMap(doc.data(), doc.id))
          .whereType<RecurringItem>()
          .toList();
      items.sort((a, b) {
        final byDate = a.nextDate.compareTo(b.nextDate);
        return byDate != 0
            ? byDate
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return items;
    });
  }

  @override
  Future<void> create(
    String householdId,
    RecurringItem item, {
    String? linkGroceryItemId,
  }) async {
    final ref = _items(householdId).doc();
    final batch = _firestore.batch();
    batch.set(ref, {
      ...item.toMap(),
      'lastGroceryItemId': linkGroceryItemId,
    });
    if (linkGroceryItemId != null) {
      batch.update(_groceries(householdId).doc(linkGroceryItemId), {
        'source': GroceryItem.sourceRecurring,
        'recurringId': ref.id,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> update(String householdId, RecurringItem item) {
    final map = item.toMap();
    // Kun redigerbare felter – lastGroceryItemId, createdBy og createdAt
    // røres ikke, så samtidige ændringer ikke overskrives. Feltet for den
    // anden interval-type slettes, så dokumentet ikke har begge.
    return _items(householdId).doc(item.id).update({
      'name': map['name'],
      'quantity': map['quantity'],
      'unit': map['unit'],
      'category': map['category'],
      'imageUrl': map['imageUrl'],
      'frequency': map['frequency'],
      'intervalWeeks': map['intervalWeeks'] ?? FieldValue.delete(),
      'dayOfMonth': map['dayOfMonth'] ?? FieldValue.delete(),
      'nextDate': map['nextDate'],
    });
  }

  @override
  Future<void> delete(String householdId, String id) =>
      _items(householdId).doc(id).delete();

  @override
  Future<void> setShoppingWeekday(
    String householdId,
    int weekday,
    Map<String, DateTime> newNextDates,
  ) async {
    final batch = _firestore.batch();
    batch.update(_household(householdId), {'shoppingWeekday': weekday});
    newNextDates.forEach((id, date) {
      batch.update(_items(householdId).doc(id), {'nextDate': toDateKey(date)});
    });
    await batch.commit();
  }

  @override
  Future<void> processOccurrence(
    String householdId,
    String recurringId, {
    required DateTime today,
    required DateTime now,
  }) {
    final ref = _items(householdId).doc(recurringId);
    return _firestore.runTransaction((tx) async {
      // I en transaktion skal alle læsninger ske før skrivningerne.
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;
      final item = RecurringItem.fromMap(data, snap.id);
      if (item == null) return;

      var previousStillOpen = false;
      final lastId = item.lastGroceryItemId;
      if (lastId != null) {
        final last = await tx.get(_groceries(householdId).doc(lastId));
        previousStillOpen = last.exists && last.data()?['isChecked'] != true;
      }

      final decision =
          decideOccurrence(item, today, previousStillOpen: previousStillOpen);
      if (decision == null) return; // En anden telefon har allerede gjort det.

      final updates = <String, dynamic>{
        'nextDate': toDateKey(decision.nextDate),
      };
      if (decision.addToList) {
        final grocery = item.toGroceryItem(item.nextDate, now);
        tx.set(_groceries(householdId).doc(grocery.id), grocery.toMap());
        updates['lastGroceryItemId'] = grocery.id;
      }
      tx.update(ref, updates);
    });
  }
}
