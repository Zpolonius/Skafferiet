/// Ren datologik for madplanens startdag (#37). Ingen Flutter, ingen Firebase
/// og ingen `DateTime.now()`.
///
/// Lagringen er uændret: ét dokument pr. mandags-uge (`meal_plans/{mandag}`),
/// og dagene ligger under danske navne ("Mandag" …). Begynder madplanen på en
/// anden dag end mandag, spænder en plan-uge over to dokumenter. Al adgang går
/// derfor gennem [locate], som oversætter en dato til (dokument, dagsnavn).
///
/// Dage lægges til via `DateTime(år, måned, dag + n)` og aldrig via
/// `Duration(days: n)` (sommertid, #39).
library;

import 'week_dates.dart';

/// Danske dagsnavne som nøgler i `meal_plans`-dokumenter, mandag først.
/// Index = `DateTime.weekday - 1`.
const planDayNames = [
  'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag', //
];

/// Dagsnavnet (nøgle i dokumentet) for [date].
String dayNameOf(DateTime date) => planDayNames[date.weekday - 1];

/// Hvor en dato ligger i Firestore: dokumentets id (mandagens dato) og
/// dagsnavnet i dokumentet.
class PlanLocation {
  final String weekId;
  final String dayName;
  const PlanLocation(this.weekId, this.dayName);

  @override
  bool operator ==(Object other) =>
      other is PlanLocation &&
      other.weekId == weekId &&
      other.dayName == dayName;

  @override
  int get hashCode => Object.hash(weekId, dayName);

  @override
  String toString() => 'PlanLocation($weekId, $dayName)';
}

/// Den ene hjælper al læsning og skrivning af madplanen går igennem.
PlanLocation locate(DateTime date) =>
    PlanLocation(weekIdOf(date), dayNameOf(date));

/// Datoen (kl. 00:00) som `yyyy-MM-dd`.
String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Den seneste [startWeekday] (1 = mandag … 7 = søndag) på eller før [date]:
/// første dag i den plan-uge [date] hører til.
DateTime planWeekStartOf(DateTime date, int startWeekday) {
  final back = (date.weekday - startWeekday + 7) % 7;
  return DateTime(date.year, date.month, date.day - back);
}

/// Plan-ugen [offset] uger fra den der indeholder [today].
DateTime planWeekStart(DateTime today, int startWeekday, [int offset = 0]) =>
    addWeeks(planWeekStartOf(today, startWeekday), offset);

/// Plan-ugens 7 datoer fra [start] og 7 dage frem.
List<DateTime> daysOfPlanWeek(DateTime start) => daysOfWeek(start);

/// Dagsnavnene i plan-ugens rækkefølge, fx søndag først ved [startWeekday] 7.
List<String> planWeekDayNames(int startWeekday) =>
    [for (var i = 0; i < 7; i++) planDayNames[(startWeekday - 1 + i) % 7]];

/// Hele plan-uger fra ugen med [from] til ugen med [to] (negativ hvis [to] ligger før).
int planWeeksBetween(DateTime from, DateTime to, int startWeekday) {
  final a = planWeekStartOf(from, startWeekday);
  final b = planWeekStartOf(to, startWeekday);
  // UTC, så sommertid ikke gør en uge til 6 dage og 23 timer.
  return DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays ~/
      7;
}

/// Ugenummeret for plan-ugen fra [start]: ISO-ugen med flest af ugens dage,
/// dvs. ugen der indeholder plan-ugens 4. dag. For mandagsstart er det det
/// almindelige ISO-ugenummer.
int planWeekNumber(DateTime start) =>
    isoWeekNumber(DateTime(start.year, start.month, start.day + 3));

/// Et dokument og de dagsnavne i det, der hører til en plan-uge.
class PlanSource {
  final String weekId;
  final Set<String> dayNames;
  const PlanSource(this.weekId, this.dayNames);
}

/// De dokumenter plan-ugen fra [start] består af, i rækkefølge (1 ved
/// mandagsstart, ellers 2), og hvilke dage i hver der er med.
List<PlanSource> planSources(DateTime start) {
  final result = <PlanSource>[];
  for (final date in daysOfPlanWeek(start)) {
    final loc = locate(date);
    if (result.isNotEmpty && result.last.weekId == loc.weekId) {
      result.last.dayNames.add(loc.dayName);
    } else {
      result.add(PlanSource(loc.weekId, {loc.dayName}));
    }
  }
  return result;
}

/// Forslag til madplanens startdag: dagen efter indkøbsdagen (mange planlægger
/// ugen fra indkøbsdagen). Mandag, når indkøbsdagen ikke er valgt.
int suggestedPlanStart(int? shoppingWeekday) =>
    shoppingWeekday == null ? DateTime.monday : shoppingWeekday % 7 + 1;
