/// Danske datoformater uden afhængighed af `intl`-lokaledata, så de også
/// virker i tests uden `initializeDateFormatting`.
library;

const danishWeekdays = [
  'mandag',
  'tirsdag',
  'onsdag',
  'torsdag',
  'fredag',
  'lørdag',
  'søndag',
];

const danishWeekdaysShort = ['man', 'tir', 'ons', 'tor', 'fre', 'lør', 'søn'];

const _monthsShort = [
  'jan.',
  'feb.',
  'mar.',
  'apr.',
  'maj',
  'jun.',
  'jul.',
  'aug.',
  'sep.',
  'okt.',
  'nov.',
  'dec.',
];

/// 1 = mandag … 7 = søndag → "Mandag".
String weekdayName(int weekday) {
  final name = danishWeekdays[weekday - 1];
  return name[0].toUpperCase() + name.substring(1);
}

/// "fre. 9. okt.", eller "i dag" / "i morgen" når det passer.
String formatShortDate(DateTime date, {DateTime? today}) {
  if (today != null) {
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == t) return 'i dag';
    if (d == DateTime(t.year, t.month, t.day + 1)) return 'i morgen';
  }
  return '${danishWeekdaysShort[date.weekday - 1]}. '
      '${date.day}. ${_monthsShort[date.month - 1]}';
}
