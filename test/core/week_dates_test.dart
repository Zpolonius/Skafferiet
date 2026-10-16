// Ren datologik for madplanens uger (#56, #39). Kør også med
// `TZ=Europe/Copenhagen flutter test test/core/week_dates_test.dart`, så
// sommertidsskiftene er med; testene er gyldige i alle tidszoner.
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/services/week_dates.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// De 7 datoer ugestriben viser for ugen med [now] (forskudt [offset] uger).
List<String> _strip(DateTime now, {int offset = 0}) =>
    daysOfWeek(addWeeks(weekStartOf(now), offset)).map(_ymd).toList();

void main() {
  group('weekStartOf', () {
    test('giver mandag kl. 00:00 for alle ugens dage', () {
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 10, 12 + i, 13, 45);
        expect(weekStartOf(d), DateTime(2026, 10, 12), reason: 'dag $i');
      }
    });

    test('krydser måneds- og årsskifte', () {
      expect(weekStartOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
      expect(weekStartOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
      expect(
          weekStartOf(DateTime(2024, 3, 1)), DateTime(2024, 2, 26)); // skudår
    });
  });

  group('weekIdOf', () {
    test('er mandagens dato som yyyy-MM-dd (samme id som før)', () {
      expect(weekIdOf(DateTime(2026, 10, 11, 23, 59)), '2026-10-05');
      expect(weekIdOf(DateTime(2026, 10, 12)), '2026-10-12');
      expect(weekIdOf(DateTime(2026, 10, 15)), '2026-10-12');
      expect(weekIdOf(DateTime(2027, 1, 1)), '2026-12-28');
      expect(weekIdOf(DateTime(2026, 3, 1)), '2026-02-23');
    });
  });

  group('sommertid (#39)', () {
    test('søndag 26. okt. 2025 kl. 23:30 (efter skift til vintertid)', () {
      expect(_strip(DateTime(2025, 10, 26, 23, 30)), [
        '2025-10-20', '2025-10-21', '2025-10-22', '2025-10-23',
        '2025-10-24', '2025-10-25', '2025-10-26', //
      ]);
    });

    test('søndag 25. okt. 2026 (skiftedagen) og ugen efter', () {
      expect(_strip(DateTime(2026, 10, 25, 23, 30)), [
        '2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22',
        '2026-10-23', '2026-10-24', '2026-10-25', //
      ]);
      expect(_strip(DateTime(2026, 10, 25, 23, 30), offset: 1).first,
          '2026-10-26');
    });

    test('mandag 23. marts 2026 kl. 23:30: næste uge er 30.-5., id uændret',
        () {
      final now = DateTime(2026, 3, 23, 23, 30);
      final next = addWeeks(weekStartOf(now), 1);
      expect(next, DateTime(2026, 3, 30));
      expect(weekIdOf(next), '2026-03-30');
      expect(_strip(now, offset: 1), [
        '2026-03-30', '2026-03-31', '2026-04-01', '2026-04-02',
        '2026-04-03', '2026-04-04', '2026-04-05', //
      ]);
    });

    test('søndag 29. marts 2026 (skift til sommertid): 7 forskellige datoer',
        () {
      final strip = _strip(DateTime(2026, 3, 29, 12));
      expect(strip, [
        '2026-03-23', '2026-03-24', '2026-03-25', '2026-03-26',
        '2026-03-27', '2026-03-28', '2026-03-29', //
      ]);
      expect(weekIdOf(DateTime(2026, 3, 29, 12)), '2026-03-23');
    });

    test('alle uger i to år: 7 forskellige datoer, kl. 00:00, id = mandag', () {
      for (final hour in [0, 1, 2, 3, 12, 23]) {
        var start = weekStartOf(DateTime(2025, 1, 1, hour, 30));
        for (var w = 0; w < 110; w++) {
          final days = daysOfWeek(start);
          expect(days.map(_ymd).toSet().length, 7,
              reason: '${_ymd(start)} kl. $hour');
          expect(days.first.weekday, DateTime.monday);
          expect(days.last.weekday, DateTime.sunday);
          for (final d in days) {
            expect(d, DateTime(d.year, d.month, d.day), reason: 'kl. 00:00');
            expect(weekIdOf(d.add(const Duration(hours: 13))), weekIdOf(start));
          }
          final next = addWeeks(start, 1);
          expect(next.difference(start).inDays >= 6, isTrue);
          expect(weekIdOf(next), _ymd(next));
          expect(next.weekday, DateTime.monday);
          start = next;
        }
      }
    });

    test('addWeeks går begge veje og ændrer ikke ugedagen', () {
      final base = weekStartOf(DateTime(2026, 3, 23, 23, 30));
      expect(addWeeks(base, -1), DateTime(2026, 3, 16));
      expect(addWeeks(base, 0), base);
      expect(addWeeks(base, 52), DateTime(2027, 3, 22));
      expect(addWeeks(base, -52), DateTime(2025, 3, 24));
    });
  });

  group('isoWeekNumber', () {
    test('mandag 12. okt. 2026 er uge 42 (ikke 41)', () {
      expect(isoWeekNumber(DateTime(2026, 10, 12)), 42);
      expect(isoWeekNumber(DateTime(2026, 10, 18)), 42);
      expect(isoWeekNumber(DateTime(2026, 10, 5)), 41);
    });

    test('årsskifter og uge 53', () {
      expect(isoWeekNumber(DateTime(2026, 12, 31)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 3)), 53);
      expect(isoWeekNumber(DateTime(2027, 1, 4)), 1);
      expect(isoWeekNumber(DateTime(2025, 12, 29)), 1); // hører til 2026
      expect(isoWeekNumber(DateTime(2025, 12, 31)), 1);
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
      expect(isoWeekNumber(DateTime(2026, 1, 4)), 1);
      expect(isoWeekNumber(DateTime(2026, 1, 5)), 2);
      expect(isoWeekNumber(DateTime(2021, 1, 1)), 53);
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1);
      expect(isoWeekNumber(DateTime(2020, 12, 31)), 53);
    });

    test('kendte uger', () {
      expect(isoWeekNumber(DateTime(2026, 3, 29)), 13);
      expect(isoWeekNumber(DateTime(2026, 3, 30)), 14);
      expect(isoWeekNumber(DateTime(2025, 10, 26)), 43);
    });
  });

  group('weeksBetween', () {
    test('hele uger, begge veje, uafhængigt af klokkeslæt og sommertid', () {
      expect(
          weeksBetween(
              DateTime(2026, 10, 11, 20), DateTime(2026, 10, 12, 0, 5)),
          1);
      expect(
          weeksBetween(DateTime(2026, 10, 11, 20), DateTime(2026, 10, 15, 9)),
          1);
      expect(
          weeksBetween(DateTime(2026, 10, 12), DateTime(2026, 10, 18, 23, 59)),
          0);
      expect(weeksBetween(DateTime(2026, 10, 15), DateTime(2026, 10, 5)), -1);
      expect(weeksBetween(DateTime(2026, 3, 23, 23, 30), DateTime(2026, 3, 30)),
          1);
      expect(
          weeksBetween(DateTime(2025, 10, 20), DateTime(2025, 10, 27, 0, 30)),
          1);
      expect(weeksBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 52);
    });
  });

  group('tekster', () {
    final today = DateTime(2026, 10, 15);

    test('weekRangeLabel: samme måned, to måneder og to år', () {
      expect(
          weekRangeLabel(DateTime(2026, 10, 12), today: today), '12.–18. okt.');
      expect(weekRangeLabel(DateTime(2026, 9, 28), today: today),
          '28. sep.–4. okt.');
      expect(weekRangeLabel(DateTime(2026, 5, 4), today: today), '4.–10. maj');
      expect(weekRangeLabel(DateTime(2026, 12, 28), today: today),
          '28. dec. 2026–3. jan. 2027');
      expect(weekRangeLabel(DateTime(2026, 10, 26), today: today),
          '26. okt.–1. nov.');
    });

    test('weekRangeLabel tager året med for en uge i et andet år end i dag',
        () {
      expect(weekRangeLabel(DateTime(2027, 1, 11), today: today),
          '11.–17. jan. 2027');
      expect(
          weekRangeLabel(DateTime(2027, 3, 29), today: DateTime(2026, 12, 30)),
          '29. mar.–4. apr. 2027');
    });

    test('weekHeaderLabel', () {
      expect(weekHeaderLabel(DateTime(2026, 10, 12), today: today),
          'Uge 42 · 12.–18. okt.');
      expect(weekHeaderLabel(DateTime(2026, 12, 28), today: today),
          'Uge 53 · 28. dec. 2026–3. jan. 2027');
    });

    test('weekBadgeLabel', () {
      expect(weekBadgeLabel(0), 'Denne uge');
      expect(weekBadgeLabel(1), 'Næste uge');
      expect(weekBadgeLabel(-1), 'Sidste uge');
      expect(weekBadgeLabel(2), isNull);
      expect(weekBadgeLabel(-5), isNull);
    });

    test('weekSemanticsLabel', () {
      expect(
          weekSemanticsLabel(DateTime(2026, 10, 12), offset: 0, today: today),
          'Uge 42, 12. til 18. oktober, denne uge');
      expect(
          weekSemanticsLabel(DateTime(2026, 9, 28), offset: -1, today: today),
          'Uge 40, 28. september til 4. oktober, sidste uge');
      expect(
          weekSemanticsLabel(DateTime(2026, 10, 19), offset: 3, today: today),
          'Uge 43, 19. til 25. oktober');
      expect(
          weekSemanticsLabel(DateTime(2026, 12, 28), offset: 11, today: today),
          'Uge 53, 28. december 2026 til 3. januar 2027');
      expect(
          weekSemanticsLabel(DateTime(2027, 1, 11), offset: 13, today: today),
          'Uge 2, 11. til 17. januar 2027');
    });
  });
}
