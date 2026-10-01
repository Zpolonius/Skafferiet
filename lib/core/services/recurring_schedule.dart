/// Ren datologik for faste varer. Ingen Firebase og ingen `DateTime.now()`
/// her – "i dag" sendes altid ind, så alt kan testes med faste datoer.
///
/// Alle datoer er lokale kalenderdatoer (kl. 00:00). Dage lægges til via
/// `DateTime(år, måned, dag + n)` og ikke `Duration(days: n)`, fordi et døgn
/// ved skift til/fra sommertid kun er 23 eller 25 timer langt.
library;

/// Hvor mange dage før indkøbsdagen varen skal på listen.
const daysBeforeShopping = 1;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Første dato *efter* [today], der falder på [weekday] (1 = mandag).
DateTime nextWeekdayAfter(DateTime today, int weekday) {
  assert(weekday >= DateTime.monday && weekday <= DateTime.sunday);
  final diff = (weekday - today.weekday + 7) % 7;
  return addDays(today, diff == 0 ? 7 : diff);
}

/// Den [day]. i måneden, eller månedens sidste dag hvis den er kortere.
/// [month] må gerne være 13+ – DateTime ruller over til næste år.
DateTime monthlyDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// Første forekomst af den [day]. i måneden *efter* [today].
DateTime nextMonthlyAfter(DateTime today, int day) {
  final thisMonth = monthlyDate(today.year, today.month, day);
  if (thisMonth.isAfter(dateOnly(today))) return thisMonth;
  return monthlyDate(today.year, today.month + 1, day);
}

/// Datoen hvor en vare med indkøbsdato [shoppingDate] lægges på listen.
DateTime addToListDate(DateTime shoppingDate) =>
    addDays(shoppingDate, -daysBeforeShopping);

/// Skal varen med indkøbsdato [shoppingDate] på listen i dag?
bool isDue(DateTime shoppingDate, DateTime today) =>
    !addToListDate(shoppingDate).isAfter(dateOnly(today));

/// Rykker [shoppingDate] frem med [following], indtil den ikke længere er
/// forfalden. Har appen ikke været åbnet i flere perioder, springes de
/// overståede over, så varen kun tilføjes én gang.
DateTime advancePastToday(
  DateTime shoppingDate,
  DateTime today,
  DateTime Function(DateTime) following,
) {
  var next = following(shoppingDate);
  while (isDue(next, today)) {
    next = following(next);
  }
  return next;
}

/// Når husstanden skifter indkøbsdag, flyttes en ugentlig vare til den nye
/// ugedag i samme uge. Ligger den dato allerede bag os, tages næste
/// forekomst af den nye ugedag.
DateTime realignToWeekday(DateTime shoppingDate, int weekday, DateTime today) {
  final sameWeek = addDays(shoppingDate, weekday - shoppingDate.weekday);
  if (sameWeek.isAfter(dateOnly(today))) return sameWeek;
  return nextWeekdayAfter(today, weekday);
}

/// Datoer gemmes som tekst ("2026-10-09"), så de betyder den samme
/// kalenderdag uanset telefonens tidszone.
String toDateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseDateKey(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final y = int.parse(match[1]!);
  final m = int.parse(match[2]!);
  final d = int.parse(match[3]!);
  final date = DateTime(y, m, d);
  // Afvis datoer der ikke findes, fx 2026-02-30.
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}
