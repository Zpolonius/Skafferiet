import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/item_history.dart';

/// Den ene fælles måde at skrive varehistorik på
/// (`households/{id}/item_history/{nøgle}`). Alle veje der lægger en vare på
/// indkøbslisten eller redigerer den bruger denne, så ingen glemmes.
///
/// Historikken skrives i samme batch/transaktion som varen, så det ene ikke
/// kan lykkes uden det andet. Ugyldige data (tomt navn, for lange felter)
/// springes over i stedet for at fejle – historikken må aldrig forhindre at
/// en vare kommer på listen. Sletning fra indkøbslisten rører ikke historikken.
class ItemHistoryWriter {
  ItemHistoryWriter._();

  static DocumentReference<Map<String, dynamic>> ref(
    FirebaseFirestore firestore,
    String householdId,
    String key,
  ) =>
      firestore
          .collection('households')
          .doc(householdId)
          .collection('item_history')
          .doc(key);

  /// Dokumentet der skal skrives (med `set` + merge), eller `null` hvis varen
  /// ikke skal i historikken. `useCount` tælles op af serveren, så to
  /// telefoner der bruger varen samtidig ikke overskriver hinanden.
  static ({String key, Map<String, dynamic> data})? entry({
    required String name,
    required String category,
    String? unit,
    String? quantity,
  }) {
    final trimmedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final key = itemHistoryKey(trimmedName);
    final trimmedCategory = category.trim();
    if (key == null ||
        trimmedName.length > ItemHistoryLimits.maxName ||
        trimmedCategory.isEmpty ||
        trimmedCategory.length > ItemHistoryLimits.maxCategory) {
      return null;
    }
    String? optional(String? v, int max) {
      final t = v?.trim();
      return t == null || t.isEmpty || t.length > max ? null : t;
    }

    return (
      key: key,
      data: {
        'name': trimmedName,
        'category': trimmedCategory,
        'unit': optional(unit, ItemHistoryLimits.maxUnit),
        'quantity': optional(quantity, ItemHistoryLimits.maxQuantity),
        'useCount': FieldValue.increment(1),
        'lastUsed': FieldValue.serverTimestamp(),
      },
    );
  }

  static void addToBatch(
    WriteBatch batch,
    FirebaseFirestore firestore,
    String householdId, {
    required String name,
    required String category,
    String? unit,
    String? quantity,
  }) {
    try {
      final e =
          entry(name: name, category: category, unit: unit, quantity: quantity);
      if (e == null) return;
      batch.set(
          ref(firestore, householdId, e.key), e.data, SetOptions(merge: true));
    } catch (err) {
      developer.log('Kunne ikke gemme varehistorik',
          error: err, name: 'item_history');
    }
  }

  static void addToTransaction(
    Transaction tx,
    FirebaseFirestore firestore,
    String householdId, {
    required String name,
    required String category,
    String? unit,
    String? quantity,
  }) {
    try {
      final e =
          entry(name: name, category: category, unit: unit, quantity: quantity);
      if (e == null) return;
      tx.set(
          ref(firestore, householdId, e.key), e.data, SetOptions(merge: true));
    } catch (err) {
      developer.log('Kunne ikke gemme varehistorik',
          error: err, name: 'item_history');
    }
  }
}
