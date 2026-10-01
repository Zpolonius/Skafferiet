import '../services/recurring_schedule.dart';

/// Hvor ofte en fast vare skal købes.
///
/// Hver variant ved selv, hvordan dens datoer beregnes, så en ny type
/// interval (fx hvert kvartal) kan tilføjes som en ny underklasse uden at
/// ændre koden, der bruger [Recurrence].
sealed class Recurrence {
  const Recurrence();

  /// Første indkøbsdato for en ny fast vare – altid efter [today].
  ///
  /// [shoppingWeekday] er husstandens indkøbsdag (1 = mandag … 7 = søndag).
  DateTime firstDate(DateTime today, {int? shoppingWeekday});

  /// Indkøbsdatoen efter [date].
  DateTime following(DateTime date);

  /// Kort dansk beskrivelse, fx "Hver 2. uge".
  String get label;

  Map<String, dynamic> toMap();

  static Recurrence? fromMap(Map<String, dynamic> map) {
    switch (map['frequency']) {
      case 'weekly':
        final weeks = map['intervalWeeks'];
        if (weeks is int && weeks >= 1 && weeks <= WeeklyRecurrence.maxWeeks) {
          return WeeklyRecurrence(weeks);
        }
      case 'monthly':
        final day = map['dayOfMonth'];
        if (day is int && day >= 1 && day <= 31) return MonthlyRecurrence(day);
    }
    return null;
  }
}

/// Hver [intervalWeeks]. uge på husstandens indkøbsdag.
class WeeklyRecurrence extends Recurrence {
  static const maxWeeks = 4;

  final int intervalWeeks;

  const WeeklyRecurrence(this.intervalWeeks)
      : assert(intervalWeeks >= 1 && intervalWeeks <= maxWeeks);

  @override
  DateTime firstDate(DateTime today, {int? shoppingWeekday}) {
    if (shoppingWeekday == null) {
      throw StateError('Ugentlige varer kræver en indkøbsdag');
    }
    return nextWeekdayAfter(today, shoppingWeekday);
  }

  @override
  DateTime following(DateTime date) => addDays(date, 7 * intervalWeeks);

  @override
  String get label =>
      intervalWeeks == 1 ? 'Hver uge' : 'Hver $intervalWeeks. uge';

  @override
  Map<String, dynamic> toMap() =>
      {'frequency': 'weekly', 'intervalWeeks': intervalWeeks};

  @override
  bool operator ==(Object other) =>
      other is WeeklyRecurrence && other.intervalWeeks == intervalWeeks;

  @override
  int get hashCode => Object.hash('weekly', intervalWeeks);
}

/// Hver måned på en fast dato. Datoer der ikke findes i en måned (fx den
/// 31. i februar) rykkes til månedens sidste dag.
class MonthlyRecurrence extends Recurrence {
  final int dayOfMonth;

  const MonthlyRecurrence(this.dayOfMonth)
      : assert(dayOfMonth >= 1 && dayOfMonth <= 31);

  @override
  DateTime firstDate(DateTime today, {int? shoppingWeekday}) =>
      nextMonthlyAfter(today, dayOfMonth);

  @override
  DateTime following(DateTime date) =>
      monthlyDate(date.year, date.month + 1, dayOfMonth);

  @override
  String get label => 'Hver måned d. $dayOfMonth.';

  @override
  Map<String, dynamic> toMap() =>
      {'frequency': 'monthly', 'dayOfMonth': dayOfMonth};

  @override
  bool operator ==(Object other) =>
      other is MonthlyRecurrence && other.dayOfMonth == dayOfMonth;

  @override
  int get hashCode => Object.hash('monthly', dayOfMonth);
}
