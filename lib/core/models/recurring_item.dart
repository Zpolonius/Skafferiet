import '../services/recurring_schedule.dart';
import 'grocery_item.dart';
import 'recurrence.dart';

/// En vare der automatisk lægges på indkøbslisten med et fast interval.
/// Gemmes i `households/{id}/recurring_items`.
class RecurringItem {
  static const maxNameLength = 80;
  static const maxQuantityLength = 10;
  static const maxCategoryLength = 40;

  // Samme grænser som firestore.rules. Tjekkes i UI'en, så brugeren får en
  // forklaring i stedet for en afvist skrivning (fx lange mængder fra en
  // opskrift som "0.3333333333").
  static String? validateName(String name) => name.isEmpty
      ? 'Navn må ikke være tomt'
      : name.length > maxNameLength
          ? 'Højst $maxNameLength tegn'
          : null;

  static String? validateQuantity(String quantity) => quantity.isEmpty
      ? 'Angiv en mængde'
      : quantity.length > maxQuantityLength
          ? 'Højst $maxQuantityLength tegn'
          : null;

  static String? validateCategory(String category) => category.isEmpty
      ? 'Angiv en kategori'
      : category.length > maxCategoryLength
          ? 'Kategorinavnet må højst være $maxCategoryLength tegn'
          : null;

  final String id;
  final String name;
  final String quantity;
  final String? unit;
  final String category;
  final String? imageUrl;
  final Recurrence recurrence;

  /// Næste indkøbsdato. Varen lægges på listen dagen før.
  final DateTime nextDate;

  /// Den vare på indkøbslisten der sidst blev oprettet herfra. Bruges til at
  /// springe over, hvis den endnu ikke er købt (krydset af).
  final String? lastGroceryItemId;
  final String createdBy;
  final DateTime createdAt;

  const RecurringItem({
    required this.id,
    required this.name,
    required this.quantity,
    this.unit,
    required this.category,
    this.imageUrl,
    required this.recurrence,
    required this.nextDate,
    this.lastGroceryItemId,
    required this.createdBy,
    required this.createdAt,
  });

  RecurringItem copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? category,
    String? imageUrl,
    Recurrence? recurrence,
    DateTime? nextDate,
    String? lastGroceryItemId,
  }) {
    return RecurringItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      recurrence: recurrence ?? this.recurrence,
      nextDate: nextDate ?? this.nextDate,
      lastGroceryItemId: lastGroceryItemId ?? this.lastGroceryItemId,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'imageUrl': imageUrl,
      ...recurrence.toMap(),
      'nextDate': toDateKey(nextDate),
      'lastGroceryItemId': lastGroceryItemId,
      'createdBy': createdBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  /// Returnerer `null` for dokumenter med ugyldige data, så én ødelagt vare
  /// ikke vælter hele listen.
  static RecurringItem? fromMap(Map<String, dynamic> map, String id) {
    final recurrence = Recurrence.fromMap(map);
    final nextDate = parseDateKey(map['nextDate']);
    final name = map['name'];
    if (recurrence == null || nextDate == null || name is! String) return null;

    final createdAt = map['createdAt'];
    return RecurringItem(
      id: id,
      name: name,
      quantity: map['quantity'] is String ? map['quantity'] : '1',
      unit: map['unit'] is String ? map['unit'] : null,
      category: map['category'] is String ? map['category'] : 'Andet',
      imageUrl: map['imageUrl'] is String ? map['imageUrl'] : null,
      recurrence: recurrence,
      nextDate: nextDate,
      lastGroceryItemId:
          map['lastGroceryItemId'] is String ? map['lastGroceryItemId'] : null,
      createdBy: map['createdBy'] is String ? map['createdBy'] : '',
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Fast ID for varen på indkøbslisten for én bestemt indkøbsdato. Kører to
  /// telefoner tilføjelsen samtidig, skriver de til samme dokument – så der
  /// aldrig opstår dubletter.
  String groceryItemIdFor(DateTime shoppingDate) =>
      'rec_${id}_${toDateKey(shoppingDate)}';

  GroceryItem toGroceryItem(DateTime shoppingDate, DateTime now) {
    return GroceryItem(
      id: groceryItemIdFor(shoppingDate),
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
      imageUrl: imageUrl,
      source: GroceryItem.sourceRecurring,
      recurringId: id,
      createdAt: now,
    );
  }
}

/// Resultatet af at behandle en forfalden fast vare.
class OccurrenceDecision {
  /// Skal varen lægges på listen? `false` hvis sidste gangs vare stadig står
  /// der uden at være krydset af.
  final bool addToList;

  /// Den nye indkøbsdato efter denne.
  final DateTime nextDate;

  const OccurrenceDecision({required this.addToList, required this.nextDate});
}

/// Afgør hvad der skal ske med [item] i dag. `null` betyder "ikke forfalden
/// endnu – gør ingenting".
OccurrenceDecision? decideOccurrence(
  RecurringItem item,
  DateTime today, {
  required bool previousStillOpen,
}) {
  if (!isDue(item.nextDate, today)) return null;
  return OccurrenceDecision(
    addToList: !previousStillOpen,
    nextDate: advancePastToday(item.nextDate, today, item.recurrence.following),
  );
}
