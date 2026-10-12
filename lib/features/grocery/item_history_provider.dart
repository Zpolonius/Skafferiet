import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/item_history.dart';
import '../profile/household_provider.dart';

/// Adgang til husstandens varehistorik. Er et interface, så widgets kan testes
/// uden Firebase.
abstract interface class ItemHistoryRepository {
  /// De senest brugte varer (højst [ItemHistoryLimits.maxEntries]), live: nye
  /// varer fra andre i husstanden kommer med, og ens egne ændringer ses med
  /// det samme (også offline).
  Stream<List<ItemHistoryEntry>> watch(String householdId);

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
  Stream<List<ItemHistoryEntry>> watch(String householdId) {
    return _col(householdId)
        .orderBy('lastUsed', descending: true)
        .limit(ItemHistoryLimits.maxEntries)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      final entries = <ItemHistoryEntry>[];
      for (final d in snap.docs) {
        final e = ItemHistoryEntry.fromMap(d.id, d.data());
        if (e == null) continue;
        // En ventende skrivning har endnu ingen servertid (feltet er null i
        // det lokale øjebliksbillede): regn den som "lige nu".
        entries.add(e.lastUsed == null && d.metadata.hasPendingWrites
            ? ItemHistoryEntry(
                key: e.key,
                name: e.name,
                category: e.category,
                unit: e.unit,
                quantity: e.quantity,
                useCount: e.useCount,
                lastUsed: now,
              )
            : e);
      }
      return entries;
    });
  }

  @override
  Future<void> remove(String householdId, String key) =>
      _col(householdId).doc(key).delete();
}

final itemHistoryRepositoryProvider = Provider<ItemHistoryRepository>(
  (ref) => FirestoreItemHistoryRepository(),
);

/// Husstandens varehistorik, live (autoDispose) og filtreret lokalt. Firestores
/// lokale cache giver ens egne ændringer med det samme; at fjerne et forslag
/// forsvinder også med det samme. En fejl (fx offline uden cache) giver bare en
/// tom liste – forslag er en hjælp, ikke en forudsætning for at tilføje varer.
class ItemHistoryNotifier
    extends AutoDisposeStreamNotifier<List<ItemHistoryEntry>> {
  @override
  Stream<List<ItemHistoryEntry>> build() async* {
    final householdId =
        ref.watch(householdProvider.select((h) => h.householdId));
    if (householdId == null) {
      yield const [];
      return;
    }
    // En fejl i strømmen (fx permission-denied efter at være fjernet fra
    // husstanden) giver en tom liste – forslag er en hjælp, ikke et krav.
    // (try/catch om `yield*` fanger ikke fejl fra selve strømmen.)
    yield* ref
        .watch(itemHistoryRepositoryProvider)
        .watch(householdId)
        .transform(
      StreamTransformer<List<ItemHistoryEntry>,
          List<ItemHistoryEntry>>.fromHandlers(
        handleError: (e, st, sink) {
          developer.log('Kunne ikke hente varehistorik',
              error: e, name: 'item_history');
          sink.add(const []);
        },
      ),
    );
  }

  Future<void> remove(String key) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    final current = state.valueOrNull ?? const <ItemHistoryEntry>[];
    // Væk fra skærmen med det samme; sletningen køres bagefter (offline-first).
    // Mislykkes den, sender strømmen den gamle liste igen.
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

final itemHistoryProvider = StreamNotifierProvider.autoDispose<
    ItemHistoryNotifier, List<ItemHistoryEntry>>(ItemHistoryNotifier.new);
