/// Ren logik for "kopiér forrige uge" i madplanen (#56). Ingen Firebase.
///
/// En [PlannedSlot] er ét udfyldt måltid i en uge: dag (dansk navn, som i
/// `meal_plans`-dokumentet), måltidsnøgle (`MealType.key`) og enten et
/// opskrifts-id eller en tekst. Alle måltider tælles og kopieres, også dem
/// brugeren har fravalgt i sit personlige måltidsfilter – madplanen er fælles.
library;

import '../models/meal_plan.dart';
import '../models/meal_type.dart';

const planDayNames = [
  'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag', //
];

class PlannedSlot {
  final String day;
  final String key;
  final String? recipeId;
  final String? directEntry;

  const PlannedSlot(this.day, this.key, {this.recipeId, this.directEntry});

  /// Samme plads uanset indhold.
  String get position => '$day/$key';

  Map<String, dynamic> toMap() =>
      {'recipeId': recipeId, 'directEntry': directEntry};

  @override
  bool operator ==(Object other) =>
      other is PlannedSlot &&
      other.day == day &&
      other.key == key &&
      other.recipeId == recipeId &&
      other.directEntry == directEntry;

  @override
  int get hashCode => Object.hash(day, key, recipeId, directEntry);

  @override
  String toString() => 'PlannedSlot($position, $recipeId, $directEntry)';
}

bool _filled(String? recipeId, String? directEntry) =>
    recipeId != null || directEntry != null;

/// De udfyldte måltider i et `meal_plans`-dokument (rå Firestore-data). Ukendte
/// dage og måltidsnøgler springes over, ligesom tomme/ryddede pladser.
List<PlannedSlot> slotsOfData(Map<String, dynamic>? data) {
  final days = data?['days'];
  if (days is! Map) return const [];
  final result = <PlannedSlot>[];
  for (final day in planDayNames) {
    final slots = days[day];
    if (slots is! Map) continue;
    for (final type in MealType.values) {
      final slot = slots[type.key];
      if (slot is! Map) continue;
      final recipeId = slot['recipeId'];
      final directEntry = slot['directEntry'];
      if (recipeId is! String? || directEntry is! String?) continue;
      if (_filled(recipeId, directEntry)) {
        result.add(PlannedSlot(day, type.key,
            recipeId: recipeId, directEntry: directEntry));
      }
    }
  }
  return result;
}

/// De udfyldte måltider i en indlæst uge. Et måltid med [MealSlot.recipeId]
/// tæller som udfyldt, også før opskriften er indlæst eller hvis den er slettet.
List<PlannedSlot> slotsOfPlan(WeeklyMealPlan plan) {
  final result = <PlannedSlot>[];
  for (final day in planDayNames) {
    final daily = plan.days[day];
    if (daily == null) continue;
    for (final type in MealType.values) {
      final slot = daily.slot(type);
      if (_filled(slot.recipeId, slot.directEntry)) {
        result.add(PlannedSlot(day, type.key,
            recipeId: slot.recipeId, directEntry: slot.directEntry));
      }
    }
  }
  return result;
}

/// Hvilke af [previous]s måltider der skal kopieres til en uge med [current]:
/// kun dem hvis plads er tom. Udfyldte pladser overskrives aldrig.
List<PlannedSlot> slotsToCopy({
  required List<PlannedSlot> previous,
  required List<PlannedSlot> current,
}) {
  final taken = {for (final s in current) s.position};
  return [
    for (final s in previous)
      if (!taken.contains(s.position)) s
  ];
}

/// Hvilke af de [copied] måltider der kan fortrydes: dem der i [current] stadig
/// er præcis som kopieret. Et måltid der er ændret eller fjernet røres ikke.
List<PlannedSlot> slotsToUndo({
  required List<PlannedSlot> copied,
  required List<PlannedSlot> current,
}) {
  final now = current.toSet();
  return [
    for (final s in copied)
      if (now.contains(s)) s
  ];
}

/// Indholdet til én `set(..., merge: true)` af [slots]; med [clear] ryddes
/// pladserne i stedet (samme form som "Fjern fra madplanen").
Map<String, dynamic> slotsPayload(List<PlannedSlot> slots,
    {bool clear = false}) {
  final days = <String, Map<String, dynamic>>{};
  for (final s in slots) {
    days.putIfAbsent(s.day, () => {})[s.key] =
        clear ? {'recipeId': null, 'directEntry': null} : s.toMap();
  }
  return {'days': days};
}

/// Hele dokumentet [data] med [slots] sat og alt andet urørt (til en
/// transaktion, hvor hele dokumentet skrives tilbage).
Map<String, dynamic> withSlotsSet(
    Map<String, dynamic>? data, List<PlannedSlot> slots) {
  final rawDays = data?['days'];
  final days = <String, dynamic>{
    if (rawDays is Map)
      for (final e in rawDays.entries) '${e.key}': e.value,
  };
  for (final s in slots) {
    final rawDay = days[s.day];
    final day = <String, dynamic>{
      if (rawDay is Map)
        for (final e in rawDay.entries) '${e.key}': e.value,
    };
    day[s.key] = s.toMap();
    days[s.day] = day;
  }
  return {...?data, 'days': days};
}

/// "1 måltid" / "3 måltider".
String mealCountLabel(int count) => count == 1 ? '1 måltid' : '$count måltider';

/// Hvor mange af [slots] der er skjult af brugerens personlige måltidsfilter.
int hiddenCount(List<PlannedSlot> slots, Iterable<MealType> visible) {
  final keys = {for (final t in visible) t.key};
  return slots.where((s) => !keys.contains(s.key)).length;
}

/// "3 måltider" eller "3 måltider (heraf 1 skjult)". Alle måltider tælles,
/// også dem filteret skjuler, for madplanen er fælles.
String mealCountWithHidden(int count, int hidden) => hidden == 0
    ? mealCountLabel(count)
    : '${mealCountLabel(count)} (heraf $hidden ${hidden == 1 ? 'skjult' : 'skjulte'})';

/// Teksten i tilbuddet om at kopiere en uge til den viste (tomme) uge.
/// [offset] er den viste uge i forhold til den aktuelle; [fromWeek] og
/// [toWeek] er ISO-ugenumre.
String copyOfferLabel({
  required int offset,
  required int fromWeek,
  required int toWeek,
  required int count,
  int hidden = 0,
}) {
  final meals = mealCountWithHidden(count, hidden);
  if (offset == 0) return 'Sidste uge havde $meals – kopiér til denne uge?';
  final verb = offset > 0 ? 'har' : 'havde';
  return 'Uge $fromWeek $verb $meals – kopiér til uge $toWeek?';
}
