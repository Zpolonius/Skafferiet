// #35: søgning i opskrifter finder også på ingredienser og tåler mellemrum —
// både i vælgeren (Tilføj måltid / Skift) og i Opskrifter-fanen.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/recipe_picker.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_screen.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

Ingredient _ing(String name) =>
    Ingredient(name: name, quantity: 1, unit: 'stk', category: 'Andet');

Recipe _recipe(String id, String title, List<String> ingredients,
        {RecipeCategory category = RecipeCategory.aftensmad}) =>
    Recipe(
      id: id,
      title: title,
      calories: 500,
      time: '30 min',
      category: category,
      ingredients: [for (final i in ingredients) _ing(i)],
    );

final _all = [
  _recipe('r1', 'Thai karry', ['Kyllingebryst', 'Kokosmælk']),
  _recipe('r2', 'Kyllingesalat', ['Salat', 'Agurk']),
  _recipe('r3', 'Lasagne', ['Hakket oksekød', 'Pasta']),
  _recipe('r4', 'Æblegrød', ['Æbler', 'Sukker'],
      category: RecipeCategory.frokost),
  _recipe('r5', 'Risotto', ['Ris', 'Kylling']),
];

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _Recipes(this.list);
  final List<Recipe> list;
  @override
  Stream<List<Recipe>> build() => Stream.value(list);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPicker(WidgetTester tester,
    {List<Recipe>? recipes,
    void Function(Recipe)? onPick,
    Size size = const Size(360, 800)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      recipesProvider.overrideWith(() => _Recipes(recipes ?? _all)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: RecipePicker(onPick: onPick ?? (_) {}),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _pumpRecipes(WidgetTester tester, {List<Recipe>? recipes}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, __) => const RecipesScreen())]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      householdProvider.overrideWith((ref) => _Household()),
      recipesProvider.overrideWith(() => _Recipes(recipes ?? _all)),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await _settle(tester);
}

/// Titlerne i vælgerens liste, i rækkefølge.
List<String> _pickerTitles(WidgetTester tester) => [
      for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
        ((t.title as Text).data ?? '')
    ];

void main() {
  group('RecipePicker', () {
    testWidgets('finder opskrift på ingrediens og forklarer hvorfor',
        (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'kokos');

      expect(_pickerTitles(tester), ['Thai karry']);
      expect(find.text('Indeholder: Kokosmælk'), findsOneWidget);
    });

    testWidgets('efterstillet mellemrum fra tastaturet giver stadig resultater',
        (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'lasagne ');

      expect(_pickerTitles(tester), ['Lasagne']);
    });

    testWidgets('alle ord skal matche på tværs af titel og ingredienser',
        (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'karry  kokos');
      expect(_pickerTitles(tester), ['Thai karry']);

      await _type(tester, find.byType(TextField), 'karry pasta');
      expect(_pickerTitles(tester), isEmpty);
      expect(find.text('Ingen opskrifter matcher'), findsOneWidget);
    });

    testWidgets(
        'titel-match kommer før ingrediens-match, hver gruppe alfabetisk',
        (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'kylling');

      // Kyllingesalat (titel) først; så Risotto og Thai karry (ingredienser).
      expect(_pickerTitles(tester), ['Kyllingesalat', 'Risotto', 'Thai karry']);
      // Titel-match viser ingen "Indeholder"-linje.
      expect(find.textContaining('Indeholder:'), findsNWidgets(2));
      expect(find.text('Indeholder: Kylling'), findsOneWidget);
      expect(find.text('Indeholder: Kyllingebryst'), findsOneWidget);
    });

    testWidgets('æ/ø/å og store/små bogstaver', (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'ÆBLE');
      expect(_pickerTitles(tester), ['Æblegrød']);
    });

    testWidgets(
        'tom søgning viser alle opskrifter alfabetisk (æ/ø/å til sidst)',
        (tester) async {
      await _pumpPicker(tester);
      // Listen er lazy og scroller (maks. 320 dp), så de første vises her.
      expect(_pickerTitles(tester),
          ['Kyllingesalat', 'Lasagne', 'Risotto', 'Thai karry']);
      await tester.scrollUntilVisible(find.text('Æblegrød'), 100,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Æblegrød'), findsOneWidget);

      await _type(tester, find.byType(TextField), '   ');
      expect(find.textContaining('Indeholder:'), findsNothing);
    });

    testWidgets(
        'onNoMatch: knap ved nul resultater sender den trimmede søgning',
        (tester) async {
      String? got;
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [recipesProvider.overrideWith(() => _Recipes(_all))],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: RecipePicker(onPick: (_) {}, onNoMatch: (q) => got = q),
          ),
        ),
      ));
      await _settle(tester);

      // Der er resultater: ingen knap.
      expect(find.text('Skriv som eget måltid'), findsNothing);

      await _type(tester, find.byType(TextField), '  pizza  ');
      final button = find.ancestor(
          of: find.text('Skriv som eget måltid'),
          matching: find.bySubtype<ButtonStyleButton>());
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      expect(got, 'pizza');
    });

    testWidgets('uden onNoMatch ingen knap', (tester) async {
      await _pumpPicker(tester);
      await _type(tester, find.byType(TextField), 'pizza');
      expect(find.text('Ingen opskrifter matcher'), findsOneWidget);
      expect(find.text('Skriv som eget måltid'), findsNothing);
    });

    testWidgets('ingen opskrifter overhovedet: ingen knap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [recipesProvider.overrideWith(() => _Recipes(const []))],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: RecipePicker(onPick: (_) {}, onNoMatch: (_) {})),
        ),
      ));
      await _settle(tester);
      await _type(tester, find.byType(TextField), 'pizza');
      expect(find.text('Du har ingen opskrifter endnu'), findsOneWidget);
      expect(find.text('Skriv som eget måltid'), findsNothing);
    });
  });

  group('Opskrifter-fanen', () {
    Finder search() =>
        find.widgetWithText(TextField, 'Søg i opskrifter, ingredienser...');

    testWidgets('finder på ingrediens', (tester) async {
      await _pumpRecipes(tester);
      await _type(tester, search(), 'kokos');

      expect(find.text('Thai karry'), findsOneWidget);
      expect(find.text('Lasagne'), findsNothing);
    });

    testWidgets('efterstillet mellemrum giver ikke nul resultater',
        (tester) async {
      await _pumpRecipes(tester);
      await _type(tester, search(), 'lasagne ');

      expect(find.text('Lasagne'), findsOneWidget);
      expect(find.text('Ingen opskrifter fundet'), findsNothing);
    });

    testWidgets('kombineres med kategorifilteret, og Nulstil virker',
        (tester) async {
      await _pumpRecipes(tester);
      // "sukker" findes kun i Æblegrød (frokost).
      final chip = find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('Aftensmad'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await _settle(tester);
      await _type(tester, search(), 'sukker ');
      expect(find.text('Ingen opskrifter fundet'), findsOneWidget);

      await tester.tap(find.text('Nulstil søgning og filter'));
      await _settle(tester);
      expect(find.text('Ingen opskrifter fundet'), findsNothing);
      expect(find.text('Lasagne'), findsOneWidget);
      expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
    });
  });
}
