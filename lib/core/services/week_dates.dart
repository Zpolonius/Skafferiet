/// Ren datologik for madplanens uger. Ingen Flutter, ingen Firebase og ingen
/// `DateTime.now()` – "i dag" sendes altid ind, så alt kan testes med faste
/// datoer.
///
/// En uge går fra mandag til søndag. Alle datoer er lokale kalenderdatoer
/// (kl. 00:00). Dage lægges til via `DateTime(år, måned, dag + n)` og aldrig
/// via `Duration(days: n)`, fordi et døgn ved skift til/fra sommertid kun er
/// 23 eller 25 timer langt (#39).
library;

const _shortMonths = [
  'jan.', 'feb.', 'mar.', 'apr.', 'maj', 'jun.', //
  'jul.', 'aug.', 'sep.', 'okt.', 'nov.', 'dec.',
];

const _longMonths = [
  'januar', 'februar', 'marts', 'april', 'maj', 'juni', //
  'juli', 'august', 'september', 'oktober', 'november', 'december',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Mandag kl. 00:00 i den uge [date] hører til.
DateTime weekStartOf(DateTime date) => DateTime(
    date.year, date.month, date.day - (date.weekday - DateTime.monday));

/// Mandagen [weeks] uger efter (eller før, hvis negativ) [weekStart].
DateTime addWeeks(DateTime weekStart, int weeks) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + weeks * 7);

/// Ugens 7 datoer, mandag til søndag, for ugen der starter [weekStart].
List<DateTime> daysOfWeek(DateTime weekStart) => [
      for (var i = 0; i < 7; i++)
        DateTime(weekStart.year, weekStart.month, weekStart.day + i),
    ];

/// Hele uger fra ugen med [from] til ugen med [to] (negativ hvis [to] ligger før).
int weeksBetween(DateTime from, DateTime to) {
  final a = weekStartOf(from);
  final b = weekStartOf(to);
  // UTC, så sommertid ikke gør en uge til 6 dage og 23 timer.
  final days = DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
  return days ~/ 7;
}

/// Id på ugens madplan i Firestore: mandagens dato som `yyyy-MM-dd`. Må ikke
/// ændres – eksisterende madplaner ligger under de her id'er.
String weekIdOf(DateTime date) {
  final start = weekStartOf(date);
  return '${start.year}-${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';
}

/// ISO 8601-ugenummer (1-53): uge 1 er ugen med årets første torsdag.
int isoWeekNumber(DateTime date) {
  final thursday = _thursdayOf(date);
  // UTC, så ugens længde ikke påvirkes af sommertid.
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  final days = DateTime.utc(thursday.year, thursday.month, thursday.day)
      .difference(jan1)
      .inDays;
  return days ~/ 7 + 1;
}

/// Det år ugen med [date] hører til efter ISO 8601 (kan afvige fra kalenderåret
/// de første/sidste dage af året).
int isoWeekYear(DateTime date) => _thursdayOf(date).year;

DateTime _thursdayOf(DateTime date) {
  final start = weekStartOf(date);
  return DateTime(start.year, start.month, start.day + 3);
}

/// Datointervallet for ugen der starter [weekStart], fx "12.–18. okt.",
/// "28. sep.–4. okt." eller "29. dec. 2026–4. jan. 2027". Året tages med når
/// ugen krydser årsskiftet, eller når den ligger i et andet år end [today].
String weekRangeLabel(DateTime weekStart, {required DateTime today}) {
  final first = _dateOnly(weekStart);
  final last = DateTime(first.year, first.month, first.day + 6);
  final spansYears = first.year != last.year;
  final otherYear = last.year != today.year;

  String part(DateTime d, {required bool month, required bool year}) =>
      '${d.day}.${month ? ' ${_shortMonths[d.month - 1]}' : ''}'
      '${year ? ' ${d.year}' : ''}';

  if (spansYears) {
    return '${part(first, month: true, year: true)}–${part(last, month: true, year: true)}';
  }
  if (first.month != last.month) {
    return '${part(first, month: true, year: false)}–'
        '${part(last, month: true, year: otherYear)}';
  }
  return '${first.day}.–${part(last, month: true, year: otherYear)}';
}

/// Overskriften over madplanen, fx "Uge 42 · 12.–18. okt.".
String weekHeaderLabel(DateTime weekStart, {required DateTime today}) =>
    'Uge ${isoWeekNumber(weekStart)} · ${weekRangeLabel(weekStart, today: today)}';

/// Badge ved siden af overskriften: "Denne uge", "Næste uge", "Sidste uge" –
/// ellers null. [offset] er antal uger fra den aktuelle uge.
String? weekBadgeLabel(int offset) => switch (offset) {
      0 => 'Denne uge',
      1 => 'Næste uge',
      -1 => 'Sidste uge',
      _ => null,
    };

/// Oplæst overskrift, fx "Uge 42, 12. til 18. oktober, denne uge". Året er med
/// på samme betingelser som i [weekRangeLabel].
String weekSemanticsLabel(DateTime weekStart,
    {required int offset, required DateTime today}) {
  final first = _dateOnly(weekStart);
  final last = DateTime(first.year, first.month, first.day + 6);
  String full(DateTime d, {required bool month, required bool year}) =>
      '${d.day}.${month ? ' ${_longMonths[d.month - 1]}' : ''}${year ? ' ${d.year}' : ''}';
  final spansYears = first.year != last.year;
  final spansMonths = first.month != last.month;
  final showYear = spansYears || last.year != today.year;
  final from = full(first, month: spansMonths || spansYears, year: spansYears);
  final to = full(last, month: true, year: showYear);
  final badge = weekBadgeLabel(offset)?.toLowerCase();
  return 'Uge ${isoWeekNumber(weekStart)}, $from til $to${badge == null ? '' : ', $badge'}';
}
