import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/recipes/recipe_search.dart';

Recipe _r(String title, [List<String> ingredients = const []]) => Recipe(
      id: title,
      title: title,
      calories: 400,
      time: '30 min',
      category: RecipeCategory.aftensmad,
      ingredients: [
        for (final i in ingredients)
          Ingredient(name: i, quantity: 1, unit: 'stk', category: 'Andet')
      ],
    );

void main() {
  group('recipeSearchWords', () {
    test('trimmer, samler mellemrum og gør små', () {
      expect(recipeSearchWords('  Kylling   RIS \t'), ['kylling', 'ris']);
      expect(recipeSearchWords('ÆBLE Ørred Åle'), ['æble', 'ørred', 'åle']);
      expect(recipeSearchWords('   '), isEmpty);
      expect(recipeSearchWords('kylling, ris.'), ['kylling', 'ris']);
      expect(recipeSearchWords('(chili/lime)'), ['chili', 'lime']);
      expect(recipeSearchWords(''), isEmpty);
    });
  });

  group('matchesRecipeSearch', () {
    final karry = _r('Thai karry', ['Kyllingebryst', 'Kokosmælk']);

    test('tom eller blank søgning matcher alt', () {
      expect(matchesRecipeSearch(karry, ''), isTrue);
      expect(matchesRecipeSearch(karry, '   '), isTrue);
      expect(matchesRecipeSearch(_r('Uden ingredienser'), ' '), isTrue);
    });

    test('matcher titel, uanset store/små bogstaver', () {
      expect(matchesRecipeSearch(karry, 'KARRY'), isTrue);
      expect(matchesRecipeSearch(karry, 'thai'), isTrue);
    });

    test('matcher kun på ingrediens', () {
      expect(matchesRecipeSearch(karry, 'kylling'), isTrue);
      expect(matchesRecipeSearch(karry, 'kokos'), isTrue);
    });

    test('efterstillet og foranstillet mellemrum fra tastaturet', () {
      expect(matchesRecipeSearch(karry, 'kylling '), isTrue);
      expect(matchesRecipeSearch(karry, '  karry'), isTrue);
      expect(matchesRecipeSearch(karry, 'karry '), isTrue);
    });

    test('æ/ø/å', () {
      final r = _r('Æbleskiver', ['Rødspætte', 'Grønkål', 'Smør']);
      expect(matchesRecipeSearch(r, 'æble'), isTrue);
      expect(matchesRecipeSearch(r, 'ÆBLE'), isTrue);
      expect(matchesRecipeSearch(r, 'rødspætte'), isTrue);
      expect(matchesRecipeSearch(r, 'GRØN'), isTrue);
      expect(matchesRecipeSearch(r, 'kål'), isTrue);
      expect(matchesRecipeSearch(r, 'smor'), isFalse, reason: 'ø er ikke o');
    });

    test('alle ord skal matche, på tværs af titel og ingredienser', () {
      final r = _r('Kyllingesalat', ['Ris', 'Agurk']);
      expect(matchesRecipeSearch(r, 'kylling ris'), isTrue);
      expect(matchesRecipeSearch(r, 'ris kylling'), isTrue);
      expect(matchesRecipeSearch(r, 'kylling   agurk'), isTrue);
      expect(matchesRecipeSearch(r, 'kylling pasta'), isFalse);
    });

    test('ingen træf', () {
      expect(matchesRecipeSearch(karry, 'pizza'), isFalse);
      expect(matchesRecipeSearch(_r('Lasagne'), 'kylling'), isFalse);
    });

    test('et ord kan ikke bruges to gange på tværs: begge ord skal findes', () {
      expect(matchesRecipeSearch(_r('Ris', ['Ris']), 'ris pasta'), isFalse);
    });
  });

  group('titleMatchesRecipeSearch', () {
    test('kun titlen tæller', () {
      final r = _r('Thai karry', ['Kylling']);
      expect(titleMatchesRecipeSearch(r, 'thai karry'), isTrue);
      expect(titleMatchesRecipeSearch(r, 'kylling'), isFalse);
      expect(titleMatchesRecipeSearch(r, 'thai kylling'), isFalse);
      expect(titleMatchesRecipeSearch(r, ' '), isTrue);
    });
  });

  group('matchingIngredientNames', () {
    final r = _r('Mad', ['Kyllingebryst', 'kylling', 'Ris', 'Kyllingebryst']);

    test('ingredienser der indeholder et søgeord, uden dubletter', () {
      expect(
          matchingIngredientNames(r, 'kylling '), ['Kyllingebryst', 'kylling']);
      expect(matchingIngredientNames(r, 'ris kylling'),
          ['Kyllingebryst', 'kylling', 'Ris']);
    });

    test('tom søgning og ingen træf giver tom liste', () {
      expect(matchingIngredientNames(r, '  '), isEmpty);
      expect(matchingIngredientNames(r, 'pasta'), isEmpty);
    });

    test('æ/ø/å', () {
      expect(matchingIngredientNames(_r('X', ['Ørred', 'Ål']), 'ØRRED'),
          ['Ørred']);
    });
  });

  group('searchRecipes', () {
    test('titel-træffere før ingrediens-træffere, hver gruppe alfabetisk', () {
      final all = [
        _r('Thai karry', ['Kylling']),
        _r('Risotto', ['Kylling']),
        _r('Kyllingesalat'),
        _r('Kylling i karry'),
        _r('Lasagne', ['Oksekød']),
      ];
      expect(searchRecipes(all, ' kylling ').map((r) => r.title), [
        'Kylling i karry',
        'Kyllingesalat',
        'Risotto',
        'Thai karry',
      ]);
    });

    test('tom søgning giver alle, alfabetisk med æ, ø, å til sidst', () {
      final all = [
        _r('Ålesuppe'),
        _r('Æggekage'),
        _r('Øllebrød'),
        _r('Bøf'),
        _r('Zucchini'),
        _r('Aspargessuppe'),
        _r('Bagt laks'),
      ];
      expect(searchRecipes(all, '').map((r) => r.title), [
        'Aspargessuppe',
        'Bagt laks',
        'Bøf',
        'Zucchini',
        'Æggekage',
        'Øllebrød',
        'Ålesuppe',
      ]);
    });
  });

  test('tegnsætning i søgningen giver stadig træffere', () {
    final r = _r('Kylling i karry', ['Ris', 'Kokosmælk']);
    expect(matchesRecipeSearch(r, 'kylling,'), isTrue);
    expect(matchesRecipeSearch(r, 'kylling, ris.'), isTrue);
    expect(matchingIngredientNames(r, 'ris.'), ['Ris']);
  });
}
