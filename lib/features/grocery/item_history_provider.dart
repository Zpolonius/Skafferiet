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

  /// Genskaber en fjernet post (Fortryd) med de samme felter, også den
  /// oprindelige `lastUsed`, så den sorterer som før. Har nogen tilføjet varen
  /// igen i mellemtiden, lægges brugen oveni i stedet for at overskrive den.
  /// Må ikke vente på serveren for at kunne køre offline.
  Future<void> restore(String householdId, ItemHistoryEntry entry);
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

  /// Fortryd uden transaktion (de fejler offline). Opslaget i den lokale cache
  /// er øjeblikkeligt og viser også ens egen ventende sletning og det andre i
  /// husstanden har skrevet siden (forslagslisten lytter live):
  ///  - Findes posten ikke, skrives den helt som den var (med `set`, så
  ///    gamle ekstra felter ikke genopstår; reglerne tillader kun de seks
  ///    felter). Mangler `lastUsed`, bruges "nu" – reglerne kræver et tidsstempel.
  ///  - Findes den igen (varen er tilføjet siden), røres navn/kategori/
  ///    `lastUsed` ikke, og `useCount` tælles op med den fortrudte brug. Så
  ///    sænkes tælleren aldrig og `lastUsed` flyttes aldrig bagud.
  /// Uden for cachen kan en samtidig skrivning fra en anden telefon, der slet
  /// ikke er set endnu, blive overskrevet – et bevidst, meget snævert vindue.
  @override
  Future<void> restore(String householdId, ItemHistoryEntry entry) async {
    final ref = _col(householdId).doc(entry.key);
    Map<String, dynamic>? existing;
    try {
      final snap = await ref.get(const GetOptions(source: Source.cache));
      if (snap.exists) existing = snap.data();
    } catch (_) {
      // Ingen cache at slå op i: behandles som "findes ikke".
    }
    final lastUsed = entry.lastUsed;
    if (existing != null) {
      final current = existing['lastUsed'];
      await ref.update({
        'useCount': FieldValue.increment(entry.useCount),
        // Kun hvis den eksisterende har en ældre tid (en ventende
        // serverTimestamp er null og er altid nyere).
        if (lastUsed != null &&
            current is Timestamp &&
            current.toDate().isBefore(lastUsed))
          'lastUsed': Timestamp.fromDate(lastUsed),
      });
      return;
    }
    await ref.set({
      'name': entry.name,
      'category': entry.category,
      'unit': entry.unit,
      'quantity': entry.quantity,
      'useCount': entry.useCount,
      'lastUsed': Timestamp.fromDate(lastUsed ?? DateTime.now()),
    });
  }
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

  /// Fjerner forslaget. Giver `true` når sletningen lykkedes og `false` når
  /// den fejlede (så er listen allerede sat tilbage).
  Future<bool> remove(String key) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return false;
    final current = state.valueOrNull ?? const <ItemHistoryEntry>[];
    // Væk fra skærmen med det samme; sletningen køres bagefter (offline-first).
    // Mislykkes den, sender strømmen den gamle liste igen.
    state = AsyncData(current.where((e) => e.key != key).toList());
    try {
      await ref.read(itemHistoryRepositoryProvider).remove(householdId, key);
      return true;
    } catch (e) {
      developer.log('Kunne ikke fjerne forslag',
          error: e, name: 'item_history');
      state = AsyncData(current);
      return false;
    }
  }

  /// Fortryd en fjernelse: forslaget er tilbage på skærmen med det samme (på
  /// sin gamle plads: senest brugt først, som strømmen), og skrivningen køres
  /// bagefter. Kaster ved fejl, efter at forslaget igen er fjernet fra listen.
  Future<void> restore(ItemHistoryEntry entry) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    final current = state.valueOrNull ?? const <ItemHistoryEntry>[];
    // Kun hvis forslaget ikke allerede er på listen (en anden kan have tilføjet
    // varen igen i mellemtiden): så er det kun det vi selv lagde ind, der
    // rulles tilbage ved en fejl.
    final added = !current.any((e) => e.key == entry.key);
    if (added) {
      state = AsyncData([...current, entry]..sort(_byRecency));
    }
    try {
      await ref.read(itemHistoryRepositoryProvider).restore(householdId, entry);
    } catch (e) {
      developer.log('Kunne ikke fortryde fjernelse af forslag',
          error: e, name: 'item_history');
      if (added) {
        state = AsyncData((state.valueOrNull ?? current)
            .where((x) => x.key != entry.key)
            .toList());
      }
      rethrow;
    }
  }
}

/// Senest brugt først (som strømmen); uden tidspunkt til sidst, derefter på
/// navn og nøgle, så rækkefølgen er total og stabil.
int _byRecency(ItemHistoryEntry a, ItemHistoryEntry b) {
  final al = a.lastUsed, bl = b.lastUsed;
  if (al != null && bl != null) {
    final c = bl.compareTo(al);
    if (c != 0) return c;
  } else if (al != null) {
    return -1;
  } else if (bl != null) {
    return 1;
  }
  final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return n != 0 ? n : a.key.compareTo(b.key);
}

final itemHistoryProvider = StreamNotifierProvider.autoDispose<
    ItemHistoryNotifier, List<ItemHistoryEntry>>(ItemHistoryNotifier.new);
