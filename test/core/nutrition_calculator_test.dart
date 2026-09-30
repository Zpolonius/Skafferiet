import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/recipe_units.dart';
import 'package:skafferiet/core/services/nutrition_calculator.dart';

Ingredient ing(String name, double qty, String unit, [Nutrition? n]) =>
    Ingredient(name: name, quantity: qty, unit: unit, category: 'Andet', nutritionPer100: n);

void main() {
  group('toGramsOrMl', () {
    test('omregner vægt og rumfang', () {
      expect(toGramsOrMl(400, 'g'), 400);
      expect(toGramsOrMl(1.5, 'kg'), 1500);
      expect(toGramsOrMl(2, 'dl'), 200);
      expect(toGramsOrMl(1, 'l'), 1000);
      expect(toGramsOrMl(2, 'spsk'), 30);
      expect(toGramsOrMl(1, 'tsk'), 5);
      expect(toGramsOrMl(100, ' G '), 100, reason: 'ignorerer mellemrum og store bogstaver');
    });

    test('returnerer null for enheder uden fast vægt', () {
      expect(toGramsOrMl(2, 'stk'), isNull);
      expect(toGramsOrMl(2, 'fed'), isNull);
      expect(toGramsOrMl(1, ''), isNull);
    });

    test('isVolumeUnit skelner rumfang fra vægt', () {
      expect(isVolumeUnit('dl'), isTrue);
      expect(isVolumeUnit('g'), isFalse);
    });
  });

  group('calculateNutrition', () {
    const pasta = Nutrition(kcal: 350, protein: 12, carbs: 70, fat: 1.5);
    const oil = Nutrition(kcal: 900, fat: 100);

    test('ganger næring pr. 100 med mængden og lægger sammen', () {
      final calc = calculateNutrition([
        ing('Spaghetti', 400, 'g', pasta),
        ing('Olivenolie', 2, 'spsk', oil), // 30 ml
      ]);
      expect(calc.countedIngredients, 2);
      expect(calc.total.kcal, closeTo(1400 + 270, 0.001));
      expect(calc.total.protein, closeTo(48, 0.001));
      expect(calc.total.fat, closeTo(6 + 30, 0.001));
    });

    test('springer ingredienser over uden data, uden mængde eller med stk', () {
      final calc = calculateNutrition([
        ing('Spaghetti', 400, 'g', pasta),
        ing('Løg', 1, 'stk', const Nutrition(kcal: 40)),
        ing('Salt', 0, 'g', const Nutrition(kcal: 0)),
        ing('Hvidløg', 2, 'fed'),
        ing('', 100, 'g', pasta), // tom række tæller ikke
      ]);
      expect(calc.countedIngredients, 1);
      expect(calc.totalIngredients, 4);
      expect(calc.total.kcal, closeTo(1400, 0.001));
    });

    test('perServing deler med antal portioner og kræver portioner', () {
      final calc = calculateNutrition([ing('Spaghetti', 400, 'g', pasta)]);
      expect(calc.perServing(null), isNull);
      expect(calc.perServing(0), isNull);
      expect(calc.perServing(4)!.kcal, closeTo(350, 0.001));
    });

    test('ingen data giver hasData false', () {
      final calc = calculateNutrition([ing('Løg', 1, 'stk')]);
      expect(calc.hasData, isFalse);
      expect(calc.perServing(4), isNull);
    });
  });
}
