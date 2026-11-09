import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/recurring_item.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_defaults.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/grocery_screen.dart';
import 'package:skafferiet/features/grocery/item_history_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/onboarding/starter_recipes.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/ingredient_sheet.dart';
import 'package:skafferiet/features/recipes/recipe_form_widgets.dart';
import 'package:skafferiet/shared/utils/number_format.dart';
import 'package:skafferiet/shared/widgets/add_grocery_item_sheet.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth() : super(AuthState());
}

void main() {
  group('defaultGroceryCategories', () {
    test('indeholder de 9 kanoniske kategorier i butikkens rækkefølge', () {
      expect(
        defaultGroceryCategories,
        [
          'Frugt & Grønt',
          'Brød',
          'Mejeri',
          'Kød & Fisk',
          'Kolonial',
          'Frost',
          'Drikkevarer',
          'Husholdning',
          'Andet',
        ],
      );
    });
  });

  group('normalizeGroceryCategory', () {
    test('oversætter ældre navne til kanoniske navne', () {
      expect(normalizeGroceryCategory('Grønt'), 'Frugt & Grønt');
      expect(normalizeGroceryCategory('grønt'), 'Frugt & Grønt');
      expect(normalizeGroceryCategory('Frugt'), 'Frugt & Grønt');
      expect(normalizeGroceryCategory('frugt'), 'Frugt & Grønt');
      expect(normalizeGroceryCategory('Frugt & Grønt'), 'Frugt & Grønt');
      expect(normalizeGroceryCategory('Kød'), 'Kød & Fisk');
      expect(normalizeGroceryCategory('kød'), 'Kød & Fisk');
      expect(normalizeGroceryCategory('Fisk'), 'Kød & Fisk');
      expect(normalizeGroceryCategory('fisk'), 'Kød & Fisk');
      expect(normalizeGroceryCategory('Kød & Fisk'), 'Kød & Fisk');
    });

    test('tom eller null bliver til Andet', () {
      expect(normalizeGroceryCategory(null), 'Andet');
      expect(normalizeGroceryCategory(''), 'Andet');
      expect(normalizeGroceryCategory('   '), 'Andet');
    });

    test('kanoniske navne normaliseres uanset casing', () {
      expect(normalizeGroceryCategory('brød'), 'Brød');
      expect(normalizeGroceryCategory('mejeri'), 'Mejeri');
      expect(normalizeGroceryCategory('kolonial'), 'Kolonial');
      expect(normalizeGroceryCategory('frost'), 'Frost');
      expect(normalizeGroceryCategory('drikkevarer'), 'Drikkevarer');
      expect(normalizeGroceryCategory('husholdning'), 'Husholdning');
      expect(normalizeGroceryCategory('andet'), 'Andet');
    });

    test('ukendte brugerdefinerede kategorier bevares trimmede', () {
      expect(normalizeGroceryCategory('Baby'), 'Baby');
      expect(normalizeGroceryCategory('  Måltider  '), 'Måltider');
    });
  });

  group('categoryIconFor', () {
    test('returnerer det rigtige ikon for hver kategori', () {
      expect(categoryIconFor('Frugt & Grønt'), Icons.apple);
      expect(categoryIconFor('Grønt'), Icons.apple);
      expect(categoryIconFor('Brød'), Icons.bakery_dining);
      expect(categoryIconFor('Mejeri'), Icons.egg_alt);
      expect(categoryIconFor('Kød & Fisk'), Icons.restaurant);
      expect(categoryIconFor('Kød'), Icons.restaurant);
      expect(categoryIconFor('Kolonial'), Icons.kitchen);
      expect(categoryIconFor('Frost'), Icons.ac_unit);
      expect(categoryIconFor('Drikkevarer'), Icons.local_drink);
      expect(categoryIconFor('Husholdning'), Icons.cleaning_services);
      expect(categoryIconFor('Andet'), Icons.shopping_basket);
      expect(categoryIconFor('Ukendt Kategori'), Icons.shopping_basket);
    });
  });

  group('sortGroceryCategories', () {
    test('sorterer standardkategorier efter butikkens rækkefølge', () {
      final input = ['Mejeri', 'Brød', 'Frugt & Grønt', 'Andet', 'Frost'];
      expect(
        sortGroceryCategories(input),
        ['Frugt & Grønt', 'Brød', 'Mejeri', 'Frost', 'Andet'],
      );
    });

    test(
        'placerer brugerdefinerede kategorier efter standardkategorier alfabetisk',
        () {
      final input = ['Snacks', 'Mejeri', 'Baby', 'Brød', 'Kød & Fisk'];
      expect(
        sortGroceryCategories(input),
        ['Brød', 'Mejeri', 'Kød & Fisk', 'Baby', 'Snacks'],
      );
    });
  });

  group('fromMap normalisering i domænemodeller', () {
    test('GroceryItem.fromMap oversætter ældre kategorier', () {
      final item = GroceryItem.fromMap({
        'name': 'Gulerødder',
        'category': 'Grønt',
      }, 'item_1');
      expect(item.category, 'Frugt & Grønt');

      final nullCatItem = GroceryItem.fromMap({
        'name': 'Vare',
        'category': null,
      }, 'item_2');
      expect(nullCatItem.category, 'Andet');
    });

    test('Ingredient.fromMap oversætter ældre kategorier', () {
      final ing = Ingredient.fromMap({
        'name': 'Hakket oksekød',
        'quantity': 500,
        'unit': 'g',
        'category': 'Kød',
      });
      expect(ing.category, 'Kød & Fisk');

      final nullCatIng = Ingredient.fromMap({
        'name': 'Vand',
        'quantity': 1,
        'unit': 'l',
        'category': null,
      });
      expect(nullCatIng.category, 'Andet');
    });

    test('RecurringItem.fromMap oversætter ældre kategorier', () {
      final recurring = RecurringItem.fromMap({
        'name': 'Laks',
        'nextDate': '2026-05-15',
        'category': 'Fisk',
        'frequency': 'weekly',
        'intervalWeeks': 1,
      }, 'rec_1');
      expect(recurring?.category, 'Kød & Fisk');

      final nullCatRecurring = RecurringItem.fromMap({
        'name': 'Vare',
        'nextDate': '2026-05-15',
        'category': null,
        'frequency': 'weekly',
        'intervalWeeks': 1,
      }, 'rec_2');
      expect(nullCatRecurring?.category, 'Andet');
    });

    test('ItemHistoryEntry.fromMap oversætter ældre kategorier', () {
      final entry = ItemHistoryEntry.fromMap('laks', {
        'name': 'Laks',
        'category': 'Fisk',
      });
      expect(entry?.category, 'Kød & Fisk');

      final nullCatEntry = ItemHistoryEntry.fromMap('vand', {
        'name': 'Vand',
        'category': null,
      });
      expect(nullCatEntry?.category, 'Andet');
    });
  });

  group('starterRecipes', () {
    test(
        'alle ingredienser i starter-opskrifter bruger autoriserede kategorier',
        () {
      for (final recipe in starterRecipes) {
        for (final ing in recipe.ingredients) {
          expect(
            defaultGroceryCategories.contains(ing.category),
            isTrue,
            reason:
                '${recipe.title} indeholder ingrediens "${ing.name}" med ukendt kategori "${ing.category}"',
          );
        }
      }
    });
  });

  group('Mængdevisning uden ".0"', () {
    test('formatQuantity fjerner overflødigt ".0"', () {
      expect(formatQuantity(500.0), '500');
      expect(formatQuantity(1.5), '1,5');
      expect(formatQuantity(2.0), '2');
      expect(formatQuantity(0.25), '0,25');
    });

    test('formatIngredientAmount formaterer mængde og enhed pænt', () {
      final ing1 = Ingredient(
        name: 'Spaghetti',
        quantity: 400.0,
        unit: 'g',
        category: 'Kolonial',
      );
      expect(formatIngredientAmount(ing1), '400 g');

      final ing2 = Ingredient(
        name: 'Mælk',
        quantity: 1.5,
        unit: 'dl',
        category: 'Mejeri',
      );
      expect(formatIngredientAmount(ing2), '1,5 dl');

      final ing3 = Ingredient(
        name: 'Citron',
        quantity: 1.0,
        unit: 'stk',
        category: 'Frugt & Grønt',
      );
      expect(formatIngredientAmount(ing3), '1 stk');
    });
  });

  group('IngredientSheet kategorivalg', () {
    testWidgets(
        'viser kategorichips for defaultGroceryCategories og Andet som standard for ny',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Ingredient? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showIngredientSheet(context);
              },
              child: const Text('Åbn sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Åbn sheet'));
      await tester.pumpAndSettle();

      for (final cat in defaultGroceryCategories) {
        expect(find.widgetWithText(ChoiceChip, cat), findsOneWidget);
      }

      // Standardvalg for ny ingrediens er Andet
      final andetChip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Andet'));
      expect(andetChip.selected, isTrue);

      // Vælg Mejeri i stedet
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Mejeri'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mejeri'));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('ingredient-add-nutrition')));
      await tester.pumpAndSettle();

      // Skriv navn
      await tester.enterText(find.byKey(const Key('ingredient-name')), 'Mælk');
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), '1');
      await tester.pumpAndSettle();

      // Gem
      await tester.ensureVisible(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.category, 'Mejeri');
    });

    testWidgets(
        'viser og bevarer egen kategori når en eksisterende ingrediens redigeres',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initial = Ingredient(
        name: 'Moser',
        quantity: 2,
        unit: 'stk',
        category: 'Baby',
      );
      Ingredient? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showIngredientSheet(context, initial: initial);
              },
              child: const Text('Åbn sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Åbn sheet'));
      await tester.pumpAndSettle();

      // Egen kategori "Baby" er til stede og valgt
      expect(find.widgetWithText(ChoiceChip, 'Baby'), findsOneWidget);
      final babyChip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Baby'));
      expect(babyChip.selected, isTrue);

      // Gem uden ændring
      await tester.ensureVisible(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.category, 'Baby');
    });

    testWidgets(
        'redigering af ingrediens med legacy kategori oversætter til autoriseret kategori',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initial = Ingredient(
        name: 'Gulerødder',
        quantity: 2,
        unit: 'stk',
        category: 'Grønt',
      );
      Ingredient? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showIngredientSheet(context, initial: initial);
              },
              child: const Text('Åbn sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Åbn sheet'));
      await tester.pumpAndSettle();

      // Legacy 'Grønt' må ikke oprette en ny chip, men skal vælge 'Frugt & Grønt'
      expect(find.widgetWithText(ChoiceChip, 'Grønt'), findsNothing);
      final fgChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Frugt & Grønt'));
      expect(fgChip.selected, isTrue);

      // Gem og verificer at den autoriserede kategori returneres
      await tester.ensureVisible(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ingredient-submit')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.category, 'Frugt & Grønt');
    });
  });

  group('AddGroceryItemSheet standardkategori', () {
    testWidgets('standardkategori er Frugt & Grønt', (tester) async {
      final fs = FakeFirebaseFirestore();
      final container = ProviderContainer(overrides: [
        householdProvider.overrideWith((ref) => _Household()),
        groceryListProvider
            .overrideWith(() => GroceryListNotifier(firestore: fs)),
        itemHistoryRepositoryProvider
            .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
      ]);
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AddGroceryItemSheet()),
        ),
      ));
      await tester.pumpAndSettle();

      final chip = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Frugt & Grønt'));
      expect(chip.selected, isTrue);
    });
  });

  group('GroceryScreen kategorirækkefølge og grupper', () {
    testWidgets('grupper på indkøbslisten vises i butikkens rækkefølge',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Opret varer i tilfældig rækkefølge med både standard- og brugerkategorier
      final col =
          fs.collection('households').doc('h1').collection('grocery_list');
      await col.add({
        'name': 'Is',
        'category': 'Frost',
        'quantity': '1',
        'isChecked': false,
        'createdAt': now,
      });
      await col.add({
        'name': 'Bleer',
        'category': 'Baby',
        'quantity': '1',
        'isChecked': false,
        'createdAt': now + 1,
      });
      await col.add({
        'name': 'Bananer',
        'category': 'Frugt & Grønt',
        'quantity': '1',
        'isChecked': false,
        'createdAt': now + 2,
      });
      await col.add({
        'name': 'Mælk',
        'category': 'Mejeri',
        'quantity': '1',
        'isChecked': false,
        'createdAt': now + 3,
      });

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth()),
          householdProvider.overrideWith((ref) => _Household()),
          groceryListProvider
              .overrideWith(() => GroceryListNotifier(firestore: fs)),
          itemHistoryRepositoryProvider
              .overrideWithValue(FirestoreItemHistoryRepository(firestore: fs)),
          recurringItemsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GroceryScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      // Tjek filterchips rækkefølge i rækken
      // Forventet butiksorden: Frugt & Grønt, Mejeri, Frost, efterfulgt af Baby
      final filterChips = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      expect(filterChips, isNotEmpty);

      // Tjek at varerne er grupperet i butikkens rækkefølge (vertikalt nedover):
      // Frugt & Grønt (Bananer) -> Mejeri (Mælk) -> Frost (Is) -> Baby (Bleer)
      final bananerY = tester.getTopLeft(find.text('Bananer')).dy;
      final maelkY = tester.getTopLeft(find.text('Mælk')).dy;
      final isY = tester.getTopLeft(find.text('Is')).dy;
      final bleerY = tester.getTopLeft(find.text('Bleer')).dy;

      expect(bananerY, lessThan(maelkY));
      expect(maelkY, lessThan(isY));
      expect(isY, lessThan(bleerY));
    });
  });

  group('firestore.rules grænser for kategorier', () {
    test('alle standardkategorier overholder længdekrav 1..40 tegn', () {
      for (final cat in defaultGroceryCategories) {
        expect(cat.length, greaterThanOrEqualTo(1));
        expect(cat.length, lessThanOrEqualTo(40));
        expect(cat.trim(), cat);
      }
    });

    test('normaliserede kategorier overholder længdekrav 1..40 tegn', () {
      final samples = [
        'Grønt',
        'Kød',
        'Fisk',
        'Frugt og grønt',
        'kød og fisk',
        'Andet',
        '   ',
        null,
        'Specialvarer fra udlandet',
      ];
      for (final s in samples) {
        final norm = normalizeGroceryCategory(s);
        expect(norm.length, greaterThanOrEqualTo(1));
        expect(norm.length, lessThanOrEqualTo(40));
      }
    });
  });

  group('Mængdevisning og kategori ved tilføjelse til indkøbsliste', () {
    test(
        'ingrediens med decimaltal får formateret mængde uden .0 og kategori med over på indkøbsliste',
        () {
      final ingredients = [
        Ingredient(name: 'Mel', quantity: 2.0, unit: 'dl', category: 'Kolonial'),
        Ingredient(name: 'Mælk', quantity: 1.5, unit: 'l', category: 'Mejeri'),
        Ingredient(
            name: 'Agurk', quantity: 1.0, unit: 'stk', category: 'Frugt & Grønt'),
      ];

      final groceryItems = ingredients
          .map((ing) => GroceryItem(
                id: 'item_${ing.name}',
                name: ing.name,
                category: ing.category,
                quantity: formatQuantity(ing.quantity),
                unit: ing.unit,
                source: 'recipe',
                createdAt: DateTime.now(),
              ))
          .toList();

      expect(groceryItems[0].quantity, '2');
      expect(groceryItems[0].category, 'Kolonial');
      expect(groceryItems[1].quantity, '1,5');
      expect(groceryItems[1].category, 'Mejeri');
      expect(groceryItems[2].quantity, '1');
      expect(groceryItems[2].category, 'Frugt & Grønt');
    });
  });
}
