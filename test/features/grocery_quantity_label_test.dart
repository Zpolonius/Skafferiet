import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe_units.dart';
import 'package:skafferiet/features/grocery/grocery_quantity_label.dart';

void main() {
  group('groceryQuantityLabel', () {
    test('tal med enhed', () {
      final label = groceryQuantityLabel('500', 'g')!;
      expect(label.text, '500 g');
      expect(label.spoken, '500 gram');
    });

    test('ental og flertal i oplæsning', () {
      expect(groceryQuantityLabel('1', 'l')!.spoken, '1 liter');
      expect(groceryQuantityLabel('1,5', 'l')!.spoken, '1,5 liter');
      expect(groceryQuantityLabel('2', 'tsk')!.spoken, '2 teskefulde');
      expect(groceryQuantityLabel('1', 'tsk')!.spoken, '1 teskefuld');
    });

    test('enheder uden oplæsningsnavn læses som de står', () {
      final label = groceryQuantityLabel('2', 'stk')!;
      expect(label.text, '2 stk');
      expect(label.spoken, '2 stk');
      expect(groceryQuantityLabel('3', 'fed')!.spoken, '3 fed');
    });

    test('opskriftsenheder vises med enheden', () {
      expect(groceryQuantityLabel('1', 'dåse')!.text, '1 dåse');
      expect(groceryQuantityLabel('2', 'spsk')!.text, '2 spsk');
    });

    test('gamle værdier med ".0" og enheder med store bogstaver', () {
      final label = groceryQuantityLabel('2.0', ' G ')!;
      expect(label.text, '2 g');
      expect(label.spoken, '2 gram');
    });

    test('decimaltal med komma eller punktum', () {
      expect(groceryQuantityLabel('1,5', 'kg')!.text, '1,5 kg');
      expect(groceryQuantityLabel('1.5', 'kg')!.text, '1,5 kg');
      expect(groceryQuantityLabel('0,125', 'kg')!.text, '0,125 kg');
    });

    test('ingen enhed (null, tom eller mellemrum) giver kun tallet', () {
      for (final unit in [null, '', '   ']) {
        final label = groceryQuantityLabel('6', unit)!;
        expect(label.text, '6');
        expect(label.spoken, '6');
      }
    });

    test('ingen mængde giver ingen chip', () {
      expect(groceryQuantityLabel('', 'g'), isNull);
      expect(groceryQuantityLabel('   ', null), isNull);
      expect(groceryQuantityLabel('0', 'g'), isNull);
      expect(groceryQuantityLabel('0.0', 'stk'), isNull);
    });

    test('tekst der ikke er et tal vises som den er skrevet', () {
      final label = groceryQuantityLabel('½', 'l')!;
      expect(label.text, '½ l');
      expect(label.spoken, '½ liter');
      expect(groceryQuantityLabel('en halv', null)!.text, 'en halv');
    });
  });

  group('canonicalUnit', () {
    test('kendte enheder får standardskrivemåden', () {
      expect(canonicalUnit('G'), 'g');
      expect(canonicalUnit(' Stk '), 'stk');
      expect(canonicalUnit('DÅSE'), 'dåse');
    });

    test('ukendte enheder beholder deres skrivemåde', () {
      expect(canonicalUnit(' Pose '), 'Pose');
    });
  });

  group('unitSpokenName', () {
    test('kendte forkortelser læses ud', () {
      expect(unitSpokenName('kg', plural: false), 'kilogram');
      expect(unitSpokenName('ml', plural: true), 'milliliter');
      expect(unitSpokenName('pk', plural: true), 'pakker');
    });

    test('ukendte enheder læses som de står', () {
      expect(unitSpokenName('Pose', plural: true), 'Pose');
    });
  });
}
