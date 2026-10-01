import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/recurrence.dart';
import 'package:skafferiet/core/models/recurring_item.dart';
import 'package:skafferiet/core/services/recurring_schedule.dart';

// Torsdag 1. oktober 2026.
final _thursday = DateTime(2026, 10, 1);

RecurringItem _item({
  Recurrence recurrence = const WeeklyRecurrence(1),
  required DateTime nextDate,
  String? lastGroceryItemId,
}) =>
    RecurringItem(
      id: 'r1',
      name: 'Mælk',
      quantity: '2',
      unit: 'l',
      category: 'Mejeri',
      recurrence: recurrence,
      nextDate: nextDate,
      lastGroceryItemId: lastGroceryItemId,
      createdBy: 'uid',
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  group('nextWeekdayAfter', () {
    test('finder næste lørdag fra en torsdag', () {
      expect(nextWeekdayAfter(_thursday, DateTime.saturday),
          DateTime(2026, 10, 3));
    });

    test('er i dag selv indkøbsdagen, tages næste uge', () {
      expect(nextWeekdayAfter(_thursday, DateTime.thursday),
          DateTime(2026, 10, 8));
    });

    test('går over månedsskifte og årsskifte', () {
      expect(nextWeekdayAfter(DateTime(2026, 12, 30), DateTime.monday),
          DateTime(2027, 1, 4));
    });

    test('ignorerer klokkeslæt', () {
      expect(nextWeekdayAfter(DateTime(2026, 10, 1, 23, 59), DateTime.friday),
          DateTime(2026, 10, 2));
    });
  });

  group('monthlyDate / nextMonthlyAfter', () {
    test('den 31. i februar bliver den 28.', () {
      expect(monthlyDate(2026, 2, 31), DateTime(2026, 2, 28));
    });

    test('den 31. i februar i skudår bliver den 29.', () {
      expect(monthlyDate(2028, 2, 31), DateTime(2028, 2, 29));
    });

    test('måned 13 ruller over til januar næste år', () {
      expect(monthlyDate(2026, 13, 15), DateTime(2027, 1, 15));
    });

    test('datoen senere i denne måned bruges', () {
      expect(nextMonthlyAfter(_thursday, 15), DateTime(2026, 10, 15));
    });

    test('er datoen i dag eller passeret, tages næste måned', () {
      expect(nextMonthlyAfter(_thursday, 1), DateTime(2026, 11, 1));
      expect(
          nextMonthlyAfter(DateTime(2026, 10, 20), 15), DateTime(2026, 11, 15));
    });

    test('den 31. i en 30-dages måned bliver sidste dag', () {
      expect(
          nextMonthlyAfter(DateTime(2026, 11, 2), 31), DateTime(2026, 11, 30));
    });
  });

  group('isDue (dagen før indkøb)', () {
    final saturday = DateTime(2026, 10, 3);

    test('ikke forfalden to dage før', () {
      expect(isDue(saturday, _thursday), isFalse);
    });

    test('forfalden dagen før', () {
      expect(isDue(saturday, DateTime(2026, 10, 2)), isTrue);
    });

    test('forfalden på selve dagen og efter', () {
      expect(isDue(saturday, saturday), isTrue);
      expect(isDue(saturday, DateTime(2026, 10, 10)), isTrue);
    });
  });

  group('advancePastToday', () {
    test('rykker én uge frem', () {
      final next = advancePastToday(DateTime(2026, 10, 3),
          DateTime(2026, 10, 2), const WeeklyRecurrence(1).following);
      expect(next, DateTime(2026, 10, 10));
    });

    test('springer overståede perioder over, når appen ikke er åbnet', () {
      // Indkøbsdag 3. okt., men appen åbnes først 22. okt.
      final next = advancePastToday(DateTime(2026, 10, 3),
          DateTime(2026, 10, 22), const WeeklyRecurrence(1).following);
      expect(next, DateTime(2026, 10, 24));
      expect(isDue(next, DateTime(2026, 10, 22)), isFalse);
    });

    test('hver 2. uge', () {
      final next = advancePastToday(DateTime(2026, 10, 3),
          DateTime(2026, 10, 2), const WeeklyRecurrence(2).following);
      expect(next, DateTime(2026, 10, 17));
    });

    test('månedlig den 31. driver ikke til den 28. efter februar', () {
      const monthly = MonthlyRecurrence(31);
      final feb = monthly.following(DateTime(2027, 1, 31));
      expect(feb, DateTime(2027, 2, 28));
      expect(monthly.following(feb), DateTime(2027, 3, 31));
    });
  });

  group('sommertid', () {
    // I Danmark skiftes til sommertid 29. marts 2026 – det døgn har 23
    // timer. Med Duration(days: 7) ville datoen kunne lande kl. 23 dagen før.
    test('en uge frem over sommertidsskiftet giver præcis næste lørdag', () {
      expect(const WeeklyRecurrence(1).following(DateTime(2026, 3, 28)),
          DateTime(2026, 4, 4));
    });

    test('en uge frem over vintertidsskiftet', () {
      expect(const WeeklyRecurrence(1).following(DateTime(2026, 10, 24)),
          DateTime(2026, 10, 31));
    });
  });

  group('realignToWeekday', () {
    test('flytter til ny dag i samme uge', () {
      // Lørdag 10. okt. → fredag 9. okt.
      expect(
          realignToWeekday(DateTime(2026, 10, 10), DateTime.friday, _thursday),
          DateTime(2026, 10, 9));
    });

    test('ligger den nye dag bag os, tages næste forekomst', () {
      // Lørdag 3. okt. → mandag 28. sep. (forbi) → mandag 5. okt.
      expect(
          realignToWeekday(DateTime(2026, 10, 3), DateTime.monday, _thursday),
          DateTime(2026, 10, 5));
    });

    test('bevarer afstanden for varer hver 4. uge', () {
      expect(
          realignToWeekday(DateTime(2026, 10, 24), DateTime.sunday, _thursday),
          DateTime(2026, 10, 25));
    });
  });

  group('datonøgler', () {
    test('toDateKey og parseDateKey går frem og tilbage', () {
      final d = DateTime(2026, 3, 5);
      expect(toDateKey(d), '2026-03-05');
      expect(parseDateKey('2026-03-05'), d);
    });

    test('afviser ugyldige værdier', () {
      expect(parseDateKey('2026-02-30'), isNull);
      expect(parseDateKey('2026-2-3'), isNull);
      expect(parseDateKey('hej'), isNull);
      expect(parseDateKey(12345), isNull);
      expect(parseDateKey(null), isNull);
    });
  });

  group('Recurrence', () {
    test('labels på dansk', () {
      expect(const WeeklyRecurrence(1).label, 'Hver uge');
      expect(const WeeklyRecurrence(3).label, 'Hver 3. uge');
      expect(const MonthlyRecurrence(15).label, 'Hver måned d. 15.');
    });

    test('fromMap læser gyldige og afviser ugyldige data', () {
      expect(Recurrence.fromMap({'frequency': 'weekly', 'intervalWeeks': 2}),
          const WeeklyRecurrence(2));
      expect(Recurrence.fromMap({'frequency': 'monthly', 'dayOfMonth': 31}),
          const MonthlyRecurrence(31));
      expect(Recurrence.fromMap({'frequency': 'weekly', 'intervalWeeks': 5}),
          isNull);
      expect(Recurrence.fromMap({'frequency': 'weekly', 'intervalWeeks': '1'}),
          isNull);
      expect(Recurrence.fromMap({'frequency': 'monthly', 'dayOfMonth': 0}),
          isNull);
      expect(Recurrence.fromMap({'frequency': 'daily'}), isNull);
    });

    test('ugentlig uden indkøbsdag fejler tydeligt', () {
      expect(() => const WeeklyRecurrence(1).firstDate(_thursday),
          throwsStateError);
    });
  });

  group('RecurringItem', () {
    test('toMap og fromMap går frem og tilbage', () {
      final item = _item(
        recurrence: const MonthlyRecurrence(15),
        nextDate: DateTime(2026, 10, 15),
        lastGroceryItemId: 'g1',
      );
      final copy = RecurringItem.fromMap(item.toMap(), 'r1')!;
      expect(copy.name, 'Mælk');
      expect(copy.unit, 'l');
      expect(copy.recurrence, const MonthlyRecurrence(15));
      expect(copy.nextDate, DateTime(2026, 10, 15));
      expect(copy.lastGroceryItemId, 'g1');
      expect(item.toMap()['nextDate'], '2026-10-15');
      expect(item.toMap().containsKey('intervalWeeks'), isFalse);
    });

    test('ødelagte dokumenter giver null i stedet for at crashe', () {
      expect(RecurringItem.fromMap({'name': 'Mælk'}, 'x'), isNull);
      expect(
          RecurringItem.fromMap({
            'name': 'Mælk',
            'frequency': 'weekly',
            'intervalWeeks': 1,
            'nextDate': 'i morgen',
          }, 'x'),
          isNull);
    });

    test('vare på listen får fast ID, kilde og reference', () {
      final item = _item(nextDate: DateTime(2026, 10, 3));
      final grocery = item.toGroceryItem(item.nextDate, _thursday);
      expect(grocery.id, 'rec_r1_2026-10-03');
      expect(grocery.source, GroceryItem.sourceRecurring);
      expect(grocery.recurringId, 'r1');
      expect(grocery.toMap()['recurringId'], 'r1');
    });
  });

  group('decideOccurrence', () {
    test('ikke forfalden → null', () {
      expect(
          decideOccurrence(_item(nextDate: DateTime(2026, 10, 10)), _thursday,
              previousStillOpen: false),
          isNull);
    });

    test('forfalden → tilføjes og næste dato rykkes frem', () {
      final d = decideOccurrence(
          _item(nextDate: DateTime(2026, 10, 2)), _thursday,
          previousStillOpen: false)!;
      expect(d.addToList, isTrue);
      expect(d.nextDate, DateTime(2026, 10, 9));
    });

    test('sidste gangs vare står stadig på listen → springes over', () {
      final d = decideOccurrence(
          _item(nextDate: DateTime(2026, 10, 2)), _thursday,
          previousStillOpen: true)!;
      expect(d.addToList, isFalse);
      expect(d.nextDate, DateTime(2026, 10, 9));
    });
  });

  group('GroceryItem.recurringId', () {
    test('udelades i toMap for almindelige varer', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Æbler',
        category: 'Grønt',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime(2026),
      );
      expect(item.toMap().containsKey('recurringId'), isFalse);
      expect(GroceryItem.fromMap(item.toMap(), 'a').recurringId, isNull);
    });

    test('læses fra databasen', () {
      final item = GroceryItem.fromMap({
        'name': 'Mælk',
        'source': 'recurring',
        'recurringId': 'r1',
      }, 'g1');
      expect(item.recurringId, 'r1');
    });
  });
}
