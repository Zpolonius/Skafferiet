import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/recurring_item.dart';
import '../../profile/household_provider.dart';
import 'recurring_items_repository.dart';
import 'recurring_items_service.dart';

/// Udskiftes med en falsk udgave i tests.
final recurringItemsRepositoryProvider = Provider<RecurringItemsRepository>(
  (ref) => FirestoreRecurringItemsRepository(),
);

/// "Nu" – udskiftes i tests, så datoer kan styres.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final recurringItemsServiceProvider = Provider<RecurringItemsService>((ref) {
  return RecurringItemsService(
    ref.watch(recurringItemsRepositoryProvider),
    now: ref.watch(clockProvider),
  );
});

/// Husstandens faste varer, sorteret efter næste indkøbsdato.
final recurringItemsProvider = StreamProvider<List<RecurringItem>>((ref) {
  final householdId = ref.watch(householdProvider.select((h) => h.householdId));
  if (householdId == null) return Stream.value(const []);
  return ref.watch(recurringItemsRepositoryProvider).watch(householdId);
});
