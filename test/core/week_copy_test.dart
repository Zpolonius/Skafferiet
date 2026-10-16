// Ren logik for "kopiér forrige uge" (#56).
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/services/week_copy.dart';

Map<String, dynamic> _slot({String? recipeId, String? text}) =>
    {'recipeId': recipeId, 'directEntry': text};

void main() {
  group('slotsOfData', () {
    test('tom eller manglende data giver ingen måltider', () {
      expect(slotsOfData(null), isEmpty);
      expect(slotsOfData({}), isEmpty);
      expect(slotsOfData({'days': 'x'}), isEmpty);
    });

    test('læser opskrifter og tekster, springer ryddede og ukendte over', () {
      final slots = slotsOfData({
        'days': {
          'Mandag': {
            'dinner': _slot(recipeId: 'r1'),
            'lunch': _slot(), // ryddet med "Fjern fra madplanen"
            'brunch': _slot(text: 'ukendt måltid'),
          },
          'Søndag': {'breakfast': _slot(text: 'Rundstykker')},
          'Funday': {'dinner': _slot(text: 'ukendt dag')},
          'Tirsdag': 'ødelagt',
        },
      });
      expect(slots, [
        const PlannedSlot('Mandag', 'dinner', recipeId: 'r1'),
        const PlannedSlot('Søndag', 'breakfast', directEntry: 'Rundstykker'),
      ]);
    });

    test('en opskrift der er slettet tæller stadig (id bevares)', () {
      expect(
          slotsOfData({
            'days': {
              'Fredag': {'snack': _slot(recipeId: 'gone')}
            }
          }),
          [const PlannedSlot('Fredag', 'snack', recipeId: 'gone')]);
    });
  });

  group('slotsOfPlan', () {
    test('tæller også opskrifter der ikke er indlæst endnu', () {
      final plan =
          WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 10, 12), days: {
        'Onsdag': DailyPlan(
          breakfast: MealSlot(),
          lunch: MealSlot(recipeId: 'r9'),
          dinner: MealSlot(directEntry: 'Pizza'),
          snack: MealSlot(),
        ),
      });
      expect(slotsOfPlan(plan), [
        const PlannedSlot('Onsdag', 'lunch', recipeId: 'r9'),
        const PlannedSlot('Onsdag', 'dinner', directEntry: 'Pizza'),
      ]);
    });
  });

  group('slotsToCopy', () {
    const a = PlannedSlot('Mandag', 'dinner', directEntry: 'Pasta');
    const b = PlannedSlot('Tirsdag', 'lunch', recipeId: 'r1');
    const c = PlannedSlot('Tirsdag', 'dinner', directEntry: 'Suppe');

    test('tom uge: alt kopieres', () {
      expect(slotsToCopy(previous: [a, b, c], current: []), [a, b, c]);
    });

    test('udfyldte pladser overskrives aldrig, uanset indhold', () {
      const taken = PlannedSlot('Mandag', 'dinner', directEntry: 'Burger');
      expect(slotsToCopy(previous: [a, b, c], current: [taken]), [b, c]);
      const sameDayOtherMeal =
          PlannedSlot('Tirsdag', 'breakfast', directEntry: 'Grød');
      expect(slotsToCopy(previous: [a, b, c], current: [sameDayOtherMeal]),
          [a, b, c]);
    });

    test('intet at kopiere når alt er optaget eller forrige uge er tom', () {
      expect(slotsToCopy(previous: [a], current: [a]), isEmpty);
      expect(slotsToCopy(previous: [], current: [a]), isEmpty);
    });
  });

  group('slotsToUndo', () {
    const a = PlannedSlot('Mandag', 'dinner', directEntry: 'Pasta');
    const b = PlannedSlot('Tirsdag', 'lunch', recipeId: 'r1');

    test('fortryder kun måltider der stadig er som kopieret', () {
      const changed = PlannedSlot('Mandag', 'dinner', directEntry: 'Ændret');
      expect(slotsToUndo(copied: [a, b], current: [a, b]), [a, b]);
      expect(slotsToUndo(copied: [a, b], current: [changed, b]), [b]);
      expect(slotsToUndo(copied: [a, b], current: [b]), [b]);
      expect(slotsToUndo(copied: [a, b], current: []), isEmpty);
    });

    test('rører ikke måltider der ikke blev kopieret', () {
      const other = PlannedSlot('Fredag', 'dinner', directEntry: 'Taco');
      expect(slotsToUndo(copied: [a], current: [a, other]), [a]);
    });
  });

  group('payloads', () {
    test('slotsPayload samler alt i ét dokument med dage og måltidsnøgler', () {
      expect(
        slotsPayload(const [
          PlannedSlot('Mandag', 'dinner', directEntry: 'Pasta'),
          PlannedSlot('Mandag', 'lunch', recipeId: 'r1'),
          PlannedSlot('Søndag', 'snack', directEntry: 'Æble'),
        ]),
        {
          'days': {
            'Mandag': {
              'dinner': {'recipeId': null, 'directEntry': 'Pasta'},
              'lunch': {'recipeId': 'r1', 'directEntry': null},
            },
            'Søndag': {
              'snack': {'recipeId': null, 'directEntry': 'Æble'},
            },
          }
        },
      );
    });

    test('slotsPayload med clear rydder pladserne', () {
      expect(
        slotsPayload(
            const [PlannedSlot('Mandag', 'dinner', directEntry: 'Pasta')],
            clear: true),
        {
          'days': {
            'Mandag': {
              'dinner': {'recipeId': null, 'directEntry': null}
            }
          }
        },
      );
    });

    test('withSlotsSet bevarer alt andet i dokumentet', () {
      final data = {
        'extra': 1,
        'days': {
          'Mandag': {'lunch': _slot(text: 'Suppe')},
          'Tirsdag': {'dinner': _slot(text: 'Fisk')},
        },
      };
      expect(
        withSlotsSet(data, const [
          PlannedSlot('Mandag', 'dinner', directEntry: 'Pasta'),
          PlannedSlot('Søndag', 'snack', recipeId: 'r1'),
        ]),
        {
          'extra': 1,
          'days': {
            'Mandag': {
              'lunch': _slot(text: 'Suppe'),
              'dinner': _slot(text: 'Pasta'),
            },
            'Tirsdag': {'dinner': _slot(text: 'Fisk')},
            'Søndag': {'snack': _slot(recipeId: 'r1')},
          },
        },
      );
      // Inddata er urørt.
      expect(((data['days'] as Map)['Mandag'] as Map).containsKey('dinner'),
          isFalse);
      expect(withSlotsSet(null, const []), {'days': <String, dynamic>{}});
    });
  });

  group('tekster', () {
    test('hiddenCount og mealCountWithHidden', () {
      const slots = [
        PlannedSlot('Mandag', 'dinner', directEntry: 'a'),
        PlannedSlot('Mandag', 'lunch', directEntry: 'b'),
        PlannedSlot('Tirsdag', 'snack', directEntry: 'c'),
      ];
      expect(hiddenCount(slots, MealType.values), 0);
      expect(hiddenCount(slots, [MealType.dinner]), 2);
      expect(hiddenCount(slots, const []), 3);
      expect(mealCountWithHidden(3, 0), '3 måltider');
      expect(mealCountWithHidden(3, 1), '3 måltider (heraf 1 skjult)');
      expect(mealCountWithHidden(3, 2), '3 måltider (heraf 2 skjulte)');
      expect(
          copyOfferLabel(
              offset: 0, fromWeek: 41, toWeek: 42, count: 2, hidden: 1),
          'Sidste uge havde 2 måltider (heraf 1 skjult) – kopiér til denne uge?');
    });

    test('mealCountLabel bruger ental og flertal', () {
      expect(mealCountLabel(1), '1 måltid');
      expect(mealCountLabel(2), '2 måltider');
      expect(mealCountLabel(7), '7 måltider');
    });

    test('copyOfferLabel', () {
      expect(copyOfferLabel(offset: 0, fromWeek: 41, toWeek: 42, count: 1),
          'Sidste uge havde 1 måltid – kopiér til denne uge?');
      expect(copyOfferLabel(offset: 0, fromWeek: 41, toWeek: 42, count: 3),
          'Sidste uge havde 3 måltider – kopiér til denne uge?');
      expect(copyOfferLabel(offset: 1, fromWeek: 42, toWeek: 43, count: 2),
          'Uge 42 har 2 måltider – kopiér til uge 43?');
      expect(copyOfferLabel(offset: -1, fromWeek: 40, toWeek: 41, count: 2),
          'Uge 40 havde 2 måltider – kopiér til uge 41?');
    });
  });
}
