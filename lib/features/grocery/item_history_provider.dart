import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/item_history.dart';
import '../profile/household_provider.dart';

/// Adgang til husstandens varehistorik. Er et interface, så widgets kan testes
/// uden Firebase.
abstract interface class ItemHistoryRepository {
  /// De senest brugte varer (højst [ItemHistoryLimits.maxEntries]).
  Future<List<ItemHistoryEntry>> fetch(String householdId);

  Future<void> remove(String householdId, String key);
}

class FirestoreItemHistoryRepository implements ItemHistoryRepository {
  final FirebaseFirestore? _firestore;

  FirestoreItemHistoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore;

  // Slås først op ved brug, så en skærm uden Firebase (fx i tests) ikke fejler
  // ved oprettelsen.
  CollectionReference<Map<String, dynamic>> _col(String householdId) =>
      (_firestore ?? FirebaseFirestore.instance)
          .collection('households')
          .doc(householdId)
          .collection('item_history');

  @override
  Future<List<ItemHistoryEntry>> fetch(String householdId) async {
    final snap = await _col(householdId)
        .orderBy('lastUsed', descending: true)
        .limit(ItemHistoryLimits.maxEntries)
        .get();
    return snap.docs
        .map((d) => ItemHistoryEntry.fromMap(d.id, d.data()))
        .whereType<ItemHistoryEntry>()
        .toList();
  }

  @override
  Future<void> remove(String householdId, String key) =>
      _col(householdId).doc(key).delete();
}

final itemHistoryRepositoryProvider = Provider<ItemHistoryRepository>(
  (ref) => FirestoreItemHistoryRepository(),
);

/// Husstandens varehistorik. Hentes én gang når et ark åbnes (autoDispose) og
/// filtreres lokalt; at fjerne et forslag opdaterer listen med det samme.
/// En fejl (fx offline uden cache) giver bare en tom liste – forslag er en
/// hjælp, ikke en forudsætning for at tilføje varer.
class ItemHistoryNotifier
    extends AutoDisposeAsyncNotifier<List<ItemHistoryEntry>> {
  @override
  Future<List<ItemHistoryEntry>> build() async {
    final householdId =
        ref.watch(householdProvider.select((h) => h.householdId));
    if (householdId == null) return const [];
    try {
      return await ref.watch(itemHistoryRepositoryProvider).fetch(householdId);
    } catch (e) {
      developer.log('Kunne ikke hente varehistorik',
          error: e, name: 'item_history');
      return const [];
    }
  }

  Future<void> remove(String key) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    final current = state.valueOrNull ?? const <ItemHistoryEntry>[];
    // Væk fra skærmen med det samme; sletningen køres bagefter (offline-first).
    state = AsyncData(current.where((e) => e.key != key).toList());
    try {
      await ref.read(itemHistoryRepositoryProvider).remove(householdId, key);
    } catch (e) {
      developer.log('Kunne ikke fjerne forslag',
          error: e, name: 'item_history');
      state = AsyncData(current);
    }
  }
}

final itemHistoryProvider = AsyncNotifierProvider.autoDispose<
    ItemHistoryNotifier, List<ItemHistoryEntry>>(ItemHistoryNotifier.new);
