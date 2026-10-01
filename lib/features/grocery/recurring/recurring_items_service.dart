import 'dart:developer' as developer;
import '../../../core/models/recurrence.dart';
import '../../../core/models/recurring_item.dart';
import '../../../core/services/recurring_schedule.dart';
import 'recurring_items_repository.dart';

/// De felter brugeren udfylder, når en fast vare oprettes eller redigeres.
class RecurringItemDraft {
  final String name;
  final String quantity;
  final String? unit;
  final String category;
  final String? imageUrl;
  final Recurrence recurrence;

  const RecurringItemDraft({
    required this.name,
    required this.quantity,
    this.unit,
    required this.category,
    this.imageUrl,
    required this.recurrence,
  });
}

/// Forretningslogikken for faste varer: beregner datoer og bestemmer hvad
/// der skal gemmes. Selve gemningen sker gennem [RecurringItemsRepository].
class RecurringItemsService {
  final RecurringItemsRepository _repository;
  final DateTime Function() _now;

  bool _isProcessing = false;
  List<RecurringItem>? _queued;

  RecurringItemsService(this._repository, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  DateTime get _today => dateOnly(_now());

  Future<void> create(
    String householdId,
    RecurringItemDraft draft, {
    required int? shoppingWeekday,
    required String createdBy,
    String? linkGroceryItemId,
  }) {
    final item = RecurringItem(
      id: '',
      name: draft.name,
      quantity: draft.quantity,
      unit: draft.unit,
      category: draft.category,
      imageUrl: draft.imageUrl,
      recurrence: draft.recurrence,
      nextDate:
          draft.recurrence.firstDate(_today, shoppingWeekday: shoppingWeekday),
      createdBy: createdBy,
      createdAt: _now(),
    );
    return _repository.create(householdId, item,
        linkGroceryItemId: linkGroceryItemId);
  }

  /// Ændres intervallet, starter varen forfra fra næste indkøbsdag. Ellers
  /// beholdes den planlagte dato.
  Future<void> update(
    String householdId,
    RecurringItem existing,
    RecurringItemDraft draft, {
    required int? shoppingWeekday,
  }) {
    final recurrenceChanged = existing.recurrence != draft.recurrence;
    final updated = RecurringItem(
      id: existing.id,
      name: draft.name,
      quantity: draft.quantity,
      unit: draft.unit,
      category: draft.category,
      imageUrl: draft.imageUrl,
      recurrence: draft.recurrence,
      nextDate: recurrenceChanged
          ? draft.recurrence.firstDate(_today, shoppingWeekday: shoppingWeekday)
          : existing.nextDate,
      lastGroceryItemId: existing.lastGroceryItemId,
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
    );
    return _repository.update(householdId, updated);
  }

  Future<void> delete(String householdId, String id) =>
      _repository.delete(householdId, id);

  /// Sikrer at husstanden har en indkøbsdag, før en ugentlig vare oprettes.
  /// Har husstanden ingen, gemmes [chosen]. Returnerer den gældende dag.
  Future<int?> ensureShoppingWeekday(
    String householdId, {
    required int? current,
    required int? chosen,
    required List<RecurringItem> items,
  }) async {
    if (current != null || chosen == null) return current;
    await changeShoppingWeekday(householdId, chosen, items);
    return chosen;
  }

  /// Skifter husstandens indkøbsdag og flytter alle ugentlige varer med.
  Future<void> changeShoppingWeekday(
    String householdId,
    int weekday,
    List<RecurringItem> items,
  ) {
    final today = _today;
    final newDates = <String, DateTime>{
      for (final item in items)
        if (item.recurrence is WeeklyRecurrence)
          item.id: realignToWeekday(item.nextDate, weekday, today),
    };
    return _repository.setShoppingWeekday(householdId, weekday, newDates);
  }

  /// Lægger alle forfaldne faste varer på indkøbslisten. Kaldes når appen
  /// åbnes, når listen af faste varer ændres, og ved midnat.
  ///
  /// Kaldes den igen mens den kører, køres den én gang mere bagefter med de
  /// nyeste data, i stedet for at to kørsler arbejder samtidig.
  Future<void> processDue(String householdId, List<RecurringItem> items) async {
    if (_isProcessing) {
      _queued = items;
      return;
    }
    _isProcessing = true;
    try {
      var pending = items;
      while (true) {
        final today = _today;
        final now = _now();
        for (final item in pending.where((i) => isDue(i.nextDate, today))) {
          try {
            await _repository.processOccurrence(householdId, item.id,
                today: today, now: now);
          } catch (e) {
            // Fx offline – transaktioner kræver forbindelse. Varen er stadig
            // forfalden og prøves igen næste gang.
            developer.log('Kunne ikke tilføje fast vare ${item.id}',
                error: e, name: 'recurring_items');
          }
        }
        final queued = _queued;
        if (queued == null) break;
        _queued = null;
        pending = queued;
      }
    } finally {
      _isProcessing = false;
    }
  }
}
