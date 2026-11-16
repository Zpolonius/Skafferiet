// Madplanens startdag (#37): ren datologik, ingen Firebase.
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/services/meal_plan_dates.dart';
import 'package:skafferiet/core/services/week_dates.dart';

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

void main() {
  group('locate', () {
    test('giver mandagens dato som dokument og dansk dagsnavn', () {
      expect(
          locate(_d(2026, 10, 12)), const PlanLocation('2026-10-12', 'Mandag'));
      expect(locate(_d(2026, 10, 15)),
          const PlanLocation('2026-10-12', 'Torsdag'));
      // Søndag hører til mandags-ugen før.
      expect(
          locate(_d(2026, 10, 18)), const PlanLocation('2026-10-12', 'Søndag'));
      expect(
          locate(_d(2026, 10, 11)), const PlanLocation('2026-10-05', 'Søndag'));
    });

    test('rundtur: dokumentets mandag + dagens placering giver datoen igen',
        () {
      // Dækker begge sommertidsskift og to årsskift.
      var date = _d(2025, 12, 1);
      for (var i = 0; i < 800; i++) {
        final loc = locate(date);
        final monday = DateTime.parse(loc.weekId);
        expect(monday.weekday, DateTime.monday);
        final idx = planDayNames.indexOf(loc.dayName);
        expect(DateTime(monday.year, monday.month, monday.day + idx), date);
        date = DateTime(date.year, date.month, date.day + 1);
      }
    });
  });

  group('plan-uge for hver startdag', () {
    // Torsdag 2026-10-15.
    final today = _d(2026, 10, 15);
    const expectedStart = {
      1: '2026-10-12',
      2: '2026-10-13',
      3: '2026-10-14',
      4: '2026-10-15',
      5: '2026-10-09',
      6: '2026-10-10',
      7: '2026-10-11',
    };
    for (final e in expectedStart.entries) {
      test('startdag ${e.key}: ugen begynder ${e.value} og har 7 dage', () {
        final start = planWeekStartOf(today, e.key);
        expect(dateKey(start), e.value);
        expect(start.weekday, e.key);
        final days = daysOfPlanWeek(start);
        expect(days, hasLength(7));
        expect(days.contains(today), isTrue);
        // 7 forskellige dagsnavne i ugens rækkefølge.
        final names = [for (final d in days) dayNameOf(d)];
        expect(names.toSet(), hasLength(7));
        expect(names, planWeekDayNames(e.key));
        expect(names.first, planDayNames[e.key - 1]);
      });
    }

    test('en startdag på selve dagen giver samme dag; offset flytter hele uger',
        () {
      expect(planWeekStartOf(_d(2026, 10, 11), 7), _d(2026, 10, 11));
      expect(planWeekStart(today, 7, 1), _d(2026, 10, 18));
      expect(planWeekStart(today, 7, -2), _d(2026, 9, 27));
    });

    test('mandagsstart er den almindelige mandags-uge', () {
      for (var i = 0; i < 14; i++) {
        final date = _d(2026, 10, 1 + i);
        expect(planWeekStartOf(date, 1), weekStartOf(date));
      }
    });

    test('planSources: ét dokument ved mandagsstart, to ellers', () {
      final monday = planSources(_d(2026, 10, 12));
      expect(monday, hasLength(1));
      expect(monday.single.weekId, '2026-10-12');
      expect(monday.single.dayNames, hasLength(7));

      final sunday = planSources(_d(2026, 10, 11));
      expect(sunday.map((s) => s.weekId), ['2026-10-05', '2026-10-12']);
      expect(sunday[0].dayNames, {'Søndag'});
      expect(sunday[1].dayNames,
          {'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag'});

      final wednesday = planSources(_d(2026, 10, 14));
      expect(wednesday[0].dayNames,
          {'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'});
      expect(wednesday[1].dayNames, {'Mandag', 'Tirsdag'});
    });

    test('planSources dækker alle 7 dage præcis én gang for alle startdage',
        () {
      for (var start = 1; start <= 7; start++) {
        final sources = planSources(planWeekStartOf(today, start));
        final all = [for (final s in sources) ...s.dayNames];
        expect(all, hasLength(7));
        expect(all.toSet(), hasLength(7));
      }
    });
  });

  group('årsskifte', () {
    test('søndagsstart over 2026-12-31 / 2027-01-01', () {
      final start = planWeekStartOf(_d(2026, 12, 31), 7);
      expect(start, _d(2026, 12, 27));
      final days = daysOfPlanWeek(start);
      expect(days.first, _d(2026, 12, 27));
      expect(days.last, _d(2027, 1, 2));
      expect(days.contains(_d(2027, 1, 1)), isTrue);
      // 1. jan. 2027 (fredag) ligger i mandags-dokumentet 2026-12-28.
      expect(
          locate(_d(2027, 1, 1)), const PlanLocation('2026-12-28', 'Fredag'));
      // Søndag 27. dec. ligger i dokumentet 2026-12-21.
      expect(planSources(start).map((s) => s.weekId),
          ['2026-12-21', '2026-12-28']);
      // Ugens 4. dag er onsdag 30. dec. → ISO-uge 53; ugen efter → uge 1.
      expect(planWeekNumber(start), 53);
      expect(planWeekNumber(planWeekStart(_d(2026, 12, 31), 7, 1)), 1);
    });

    test('ugenummer: mandagsstart er det almindelige ISO-ugenummer', () {
      for (var i = 0; i < 60; i++) {
        final monday = addWeeks(_d(2026, 1, 5), i);
        expect(planWeekNumber(monday), isoWeekNumber(monday));
      }
    });

    test('overskriften følger plan-ugens ugenummer', () {
      expect(weekHeaderLabel(_d(2026, 10, 11), today: _d(2026, 10, 15)),
          'Uge 42 · 11.–17. okt.');
      expect(weekHeaderLabel(_d(2026, 12, 27), today: _d(2026, 12, 31)),
          'Uge 53 · 27. dec. 2026–2. jan. 2027');
    });
  });

  group('sommertid', () {
    test('forårsskift 2026-03-29 (søndag): ugen er stadig 7 kalenderdage', () {
      final start = planWeekStartOf(_d(2026, 3, 29), 7);
      expect(start, _d(2026, 3, 29));
      final days = daysOfPlanWeek(start);
      expect([for (final d in days) d.day], [29, 30, 31, 1, 2, 3, 4]);
      expect(
          locate(_d(2026, 3, 29)), const PlanLocation('2026-03-23', 'Søndag'));
      expect(planWeeksBetween(_d(2026, 3, 28), _d(2026, 3, 29), 7), 1);
      expect(planWeeksBetween(_d(2026, 3, 22), _d(2026, 3, 29), 7), 1);
      expect(planWeeksBetween(_d(2026, 3, 29), _d(2026, 4, 4), 7), 0);
    });

    test('efterårsskift 2026-10-25 (søndag): ugen er stadig 7 kalenderdage',
        () {
      final start = planWeekStartOf(_d(2026, 10, 28), 7);
      expect(start, _d(2026, 10, 25));
      expect([for (final d in daysOfPlanWeek(start)) d.day],
          [25, 26, 27, 28, 29, 30, 31]);
      expect(planWeekStart(_d(2026, 10, 28), 7, -1), _d(2026, 10, 18));
      expect(
          locate(_d(2026, 10, 25)), const PlanLocation('2026-10-19', 'Søndag'));
      expect(planWeeksBetween(_d(2026, 10, 18), _d(2026, 10, 25), 7), 1);
      expect(planWeeksBetween(_d(2026, 10, 24), _d(2026, 10, 31), 7), 1);
    });

    test('planWeeksBetween er negativ bagud og 0 inden for samme uge', () {
      expect(planWeeksBetween(_d(2026, 10, 15), _d(2026, 10, 1), 7), -2);
      expect(planWeeksBetween(_d(2026, 10, 11), _d(2026, 10, 17), 7), 0);
    });
  });

  test('suggestedPlanStart: dagen efter indkøbsdagen, mandag uden', () {
    expect(suggestedPlanStart(null), DateTime.monday);
    expect(suggestedPlanStart(DateTime.saturday), DateTime.sunday);
    expect(suggestedPlanStart(DateTime.sunday), DateTime.monday);
    expect(suggestedPlanStart(DateTime.monday), DateTime.tuesday);
  });
}
