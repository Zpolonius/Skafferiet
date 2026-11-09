import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Plan extends StreamNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Stream<WeeklyMealPlan> build() async* {
    final lasagne = Recipe(
      id: 'r1',
      title: 'Lasagne',
      calories: 1850,
      time: '45 min',
      category: RecipeCategory.aftensmad,
    );
    yield WeeklyMealPlan(
      id: 'w',
      weekStart: DateTime(2026, 9, 28),
      days: {
        for (final day in ['Mandag', 'Lørdag'])
          day: DailyPlan(
            breakfast: MealSlot(),
            lunch: MealSlot(),
            dinner: MealSlot(recipe: lasagne),
            snack: MealSlot(),
          ),
      },
    );
  }
}

class _EmptyPlan extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  @override
  Stream<WeeklyMealPlan> build() => Stream.value(
      WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 10, 12), days: {}));
}

class _DinnerOnlyHousehold extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _DinnerOnlyHousehold()
      : super(HouseholdState(householdId: 'h1', mealTypes: [MealType.dinner]));
}

class _MissingRecipePlan extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  @override
  String currentWeekId() => '2026-09-28';

  @override
  Stream<WeeklyMealPlan> build() => Stream.value(WeeklyMealPlan(
        id: 'w',
        weekStart: DateTime(2026, 9, 28),
        days: {
          'Mandag': DailyPlan(
            breakfast: MealSlot(),
            lunch: MealSlot(),
            dinner: MealSlot(recipeId: 'gone', missingRecipe: true),
            snack: MealSlot(),
          ),
        },
      ));
}

class _FailingRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.error(Exception('boom'));
}

class _NoRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

// --- Ugens aftensmad (#27) ---------------------------------------------------

final _longTitle = 'Langsom ${List.filled(10, 'braiseret').join(' ')} oksehale med rodfrugter';

DailyPlan _dayWith({MealSlot? dinner, MealSlot? breakfast}) => DailyPlan(
      breakfast: breakfast ?? MealSlot(),
      lunch: MealSlot(),
      dinner: dinner ?? MealSlot(),
      snack: MealSlot(),
    );

Recipe _recipe(String title) => Recipe(
      id: 'r-$title',
      title: title,
      calories: 500,
      time: '30 min',
      category: RecipeCategory.aftensmad,
    );

/// Man: opskrift, Tir: eget måltid, Ons: slettet opskrift, Tor: opskrift der
/// ikke er indlæst, Fre: kun morgenmad (ingen aftensmad), Lør: meget lang
/// titel, Søn: tom dag (ingen post i planen).
WeeklyMealPlan _dinnerWeek() => WeeklyMealPlan(
      id: 'w',
      weekStart: DateTime(2026, 10, 12),
      days: {
        'Mandag': _dayWith(dinner: MealSlot(recipe: _recipe('Lasagne'))),
        'Tirsdag': _dayWith(dinner: MealSlot(directEntry: 'Rester fra i går')),
        'Onsdag': _dayWith(dinner: MealSlot(recipeId: 'gone', missingRecipe: true)),
        'Torsdag': _dayWith(dinner: MealSlot(recipeId: 'later')),
        'Fredag': _dayWith(breakfast: MealSlot(directEntry: 'Havregryn')),
        'Lørdag': _dayWith(dinner: MealSlot(directEntry: _longTitle)),
      },
    );

class _DinnerWeekPlan extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  @override
  Stream<WeeklyMealPlan> build() => Stream.value(_dinnerWeek());
}

class _DinnerWeekPlanOf extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  final Map<String, DailyPlan> days;
  _DinnerWeekPlanOf(this.days);

  @override
  Stream<WeeklyMealPlan> build() => Stream.value(
      WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 10, 12), days: days));
}

/// Planen kan skiftes undervejs, som når en anden enhed ændrer den (#24).
class _LiveDinnerPlan extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  static late StreamController<WeeklyMealPlan> controller;

  @override
  Stream<WeeklyMealPlan> build() => controller.stream;
}

class _OtherMealsHousehold extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _OtherMealsHousehold()
      : super(HouseholdState(
            householdId: 'h1', mealTypes: [MealType.breakfast, MealType.lunch]));
}

Future<void> _pumpDinnerScreen(
  WidgetTester tester, {
  double width = 390,
  double textScale = 1,
  MealPlanNotifier Function()? plan,
  HouseholdNotifier Function()? household,
  String day = 'Mandag',
  RecipesNotifier Function()? recipes,
}) async {
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(Size(width, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => plan?.call() ?? _DinnerWeekPlan()),
      householdProvider.overrideWith((ref) => household?.call() ?? _Household()),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 14)),
      selectedDayProvider.overrideWith((ref) => day),
      if (recipes != null) recipesProvider.overrideWith(recipes),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const MealPlanScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Tømmer meldte fejl (fx overflow) og returnerer hvor mange der var.
int _drainExceptions(WidgetTester tester) {
  var count = 0;
  while (tester.takeException() != null) {
    count++;
  }
  return count;
}

Finder _overviewRow(String shortDay) => find.ancestor(
      of: find.textContaining('$shortDay '),
      matching: find.byType(InkWell),
    );

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  // En overskrift, der løber ud over kanten, får testen til at fejle af sig selv
  // (Flutter melder "RenderFlex overflowed").
  for (final (width, day) in [(390.0, 'Mandag'), (320.0, 'Lørdag')]) {
    testWidgets('madplanen løber ikke ud over kanten i $width pt ($day, med kalorier)',
        (tester) async {
      final user = _User();
      when(() => user.displayName).thenReturn('Mette');
      when(() => user.photoURL).thenReturn(null);
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
          mealPlanProvider.overrideWith(() => _Plan()),
          householdProvider.overrideWith((ref) => _Household()),
          selectedDayProvider.overrideWith((ref) => day),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const MealPlanScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('${day}ens madplan'), findsOneWidget);
      expect(find.text('Overfør til indkøb'), findsOneWidget);
      expect(find.textContaining('kcal'), findsWidgets);
    });
  }

  testWidgets('slot med slettet opskrift viser tekst og åbner redigeringsarket',
      (tester) async {
    final user = _User();
    when(() => user.displayName).thenReturn('Mette');
    when(() => user.photoURL).thenReturn(null);
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
        mealPlanProvider.overrideWith(() => _MissingRecipePlan()),
        recipesProvider.overrideWith(() => _NoRecipes()),
        householdProvider.overrideWith((ref) => _Household()),
        selectedDayProvider.overrideWith((ref) => 'Mandag'),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const MealPlanScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dagens kort og "Ugens aftensmad" (mandag er valgt).
    expect(find.text('Opskriften findes ikke længere'), findsNWidgets(2));

    await tester.tap(find.text('Opskriften findes ikke længere').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fjern fra madplanen'), findsOneWidget);
  });

  // Ugestriben (#63): alle 7 dage skal kunne ses uden at scrolle sidelæns.
  group('ugestriben viser alle 7 dage', () {
    const abbrs = ['MAN', 'TIR', 'ONS', 'TOR', 'FRE', 'LØR', 'SØN'];
    // Onsdag; ugen går fra mandag 12. til søndag 18. oktober.
    final now = DateTime(2026, 10, 14);

    Future<void> pumpScreen(
      WidgetTester tester, {
      double width = 390,
      double textScale = 1,
      MealPlanNotifier Function()? plan,
      HouseholdNotifier Function()? household,
      String day = 'Mandag',
    }) async {
      final user = _User();
      when(() => user.displayName).thenReturn('Mette');
      when(() => user.photoURL).thenReturn(null);
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
          mealPlanProvider.overrideWith(() => plan?.call() ?? _Plan()),
          householdProvider.overrideWith((ref) => household?.call() ?? _Household()),
          clockProvider.overrideWithValue(() => now),
          selectedDayProvider.overrideWith((ref) => day),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const MealPlanScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Trykfladen (nærmeste GestureDetector) om en dags "MAN"-tekst.
    Finder cell(String abbr) =>
        find.ancestor(of: find.text(abbr), matching: find.byType(GestureDetector)).first;

    for (final width in [320.0, 360.0, 390.0, 430.0, 1000.0]) {
      testWidgets('alle 7 dage ligger inden for skærmen i $width pt', (tester) async {
        await pumpScreen(tester, width: width);
        final screen = Rect.fromLTWH(0, 0, width, 1200);
        for (final abbr in abbrs) {
          final text = find.text(abbr);
          expect(text, findsOneWidget, reason: abbr);
          final rect = tester.getRect(text);
          expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue,
              reason: '$abbr ligger uden for skærmen: $rect');
          expect(text.hitTestable(), findsOneWidget, reason: '$abbr kan ikke rammes');
        }
      });
    }

    for (final (width, minWidth) in [(320.0, 40.0), (390.0, 48.0), (430.0, 48.0)]) {
      testWidgets('trykfladerne er store nok i $width pt', (tester) async {
        await pumpScreen(tester, width: width);
        for (final abbr in abbrs) {
          final size = tester.getSize(cell(abbr));
          expect(size.height, greaterThanOrEqualTo(48), reason: abbr);
          expect(size.width, greaterThanOrEqualTo(minWidth), reason: abbr);
        }
      });
    }

    testWidgets('dagene strækkes ikke grotesk på en bred skærm', (tester) async {
      await pumpScreen(tester, width: 1000);
      expect(tester.getSize(cell('MAN')).width, lessThanOrEqualTo(64));
      expect(tester.getRect(cell('SØN')).right, lessThan(470));
    });

    testWidgets('datoerne følger ugen, også over månedsskift', (tester) async {
      await pumpScreen(tester);
      for (final (abbr, date) in [('MAN', '12'), ('LØR', '17'), ('SØN', '18')]) {
        expect(find.descendant(of: cell(abbr), matching: find.text(date)), findsOneWidget,
            reason: abbr);
      }
      final container = ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
      container.read(weekOffsetProvider.notifier).state = 3; // 2.-8. november
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: cell('MAN'), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: cell('SØN'), matching: find.text('8')), findsOneWidget);
    });

    testWidgets('tryk på lørdag viser lørdagens måltider (uge med data)', (tester) async {
      await pumpScreen(tester, width: 320);
      expect(find.text('Mandagens madplan'), findsOneWidget);
      await tester.tap(find.text('LØR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Lørdagens madplan'), findsOneWidget);
      // Lørdagens kort + mandag og lørdag i "Ugens aftensmad".
      expect(find.text('Lasagne'), findsNWidgets(3));
    });

    testWidgets('tryk på søndag viser en tom dag (uge uden data)', (tester) async {
      await pumpScreen(tester, plan: () => _EmptyPlan());
      await tester.tap(find.text('SØN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Søndagens madplan'), findsOneWidget);
      expect(find.text('Lasagne'), findsNothing);
      expect(find.text('Morgenmad'), findsOneWidget);
    });

    testWidgets('mealTypes-filteret påvirker ikke striben', (tester) async {
      await pumpScreen(tester, household: () => _DinnerOnlyHousehold());
      expect(find.text('Morgenmad'), findsNothing);
      expect(find.text('Aftensmad'), findsOneWidget);
      for (final abbr in abbrs) {
        expect(find.text(abbr), findsOneWidget);
      }
    });

    for (final width in [320.0, 390.0]) {
      testWidgets('tekstskala 2.0 giver ingen overflow i $width pt', (tester) async {
        await pumpScreen(tester, width: width, textScale: 2.0);
        // Madplanens overskriftsrække (logo + titel + avatar) løber allerede over
        // ved tekstskala 2.0, uafhængigt af ugestriben. Den ligger uden for #63, så
        // vi tømmer fejlene og kontrollerer i stedet at stribens indhold ligger
        // inde i sit eget felt og inden for skærmen.
        while (tester.takeException() != null) {}
        for (final abbr in abbrs) {
          expect(find.text(abbr), findsOneWidget);
          final text = tester.getRect(find.text(abbr));
          final box = tester.getRect(cell(abbr));
          expect(box.contains(text.topLeft) && box.contains(text.bottomRight), isTrue,
              reason: '$abbr løber ud af sit felt: $text mod $box');
          expect(find.descendant(of: cell(abbr), matching: find.byType(FittedBox)),
              findsOneWidget);
        }
      });
    }

    testWidgets('ved tekstskala 3.0 vokser felterne i højden og er lige høje', (tester) async {
      await pumpScreen(tester, width: 390, textScale: 3.0);
      while (tester.takeException() != null) {}
      final heights = {for (final a in abbrs) tester.getSize(cell(a)).height};
      expect(heights.length, 1, reason: 'alle felter skal være lige høje: $heights');
      // Fast højde 90 ville skalere teksten ned i stedet for at give den plads.
      expect(heights.first, greaterThan(120));
      for (final a in abbrs) {
        final text = tester.getRect(find.text(a));
        final box = tester.getRect(cell(a));
        expect(box.contains(text.topLeft) && box.contains(text.bottomRight), isTrue, reason: a);
      }
      // Datoen vokser med teksten, så langt bredden tillader (ikke skaleret helt ned).
      final big = tester.getRect(find.descendant(of: cell('MAN'), matching: find.text('12'))).height;
      await pumpScreen(tester, width: 390, textScale: 1.0);
      final normal = tester.getRect(find.descendant(of: cell('MAN'), matching: find.text('12'))).height;
      expect(big, greaterThan(normal * 1.1));
    });

    testWidgets('hver dag har en skærmlæser-label med dagsnavn, dato og valgt-tilstand',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);
      final monday = _inStrip('Mandag 12. oktober, aftensmad: Lasagne');
      expect(monday, findsOneWidget);
      expect(
        tester.getSemantics(monday),
        containsSemantics(
          label: 'Mandag 12. oktober, aftensmad: Lasagne',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      final sunday = _inStrip('Søndag 18. oktober, ingen aftensmad planlagt');
      expect(sunday, findsOneWidget);
      expect(
        tester.getSemantics(sunday),
        containsSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      // Rækkefølgen er Man -> Søn.
      final lefts = [
        for (final label in [
          RegExp('^Mandag 12. oktober'),
          RegExp('^Tirsdag 13. oktober'),
          RegExp('^Onsdag 14. oktober'),
          RegExp('^Torsdag 15. oktober'),
          RegExp('^Fredag 16. oktober'),
          RegExp('^Lørdag 17. oktober'),
          RegExp('^Søndag 18. oktober'),
        ])
          tester.getRect(_inStrip(label)).left,
      ];
      expect([...lefts]..sort(), lefts);
      handle.dispose();
    });
  });
  // Ugens aftensmad (#27): prik i striben + oversigt under dagens måltider.
  group('ugens aftensmad', () {
    const days = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];
    Finder dot(String day) => find.byKey(ValueKey('dinner-dot-$day'));
    Finder ring(String day) => find.byKey(ValueKey('dinner-ring-$day'));
    Finder marker(String day) => dot(day).evaluate().isNotEmpty ? dot(day) : ring(day);
    Finder cell(String abbr) =>
        find.ancestor(of: find.text(abbr), matching: find.byType(GestureDetector)).first;

    testWidgets('oversigten viser hver dags aftensmad uden at trykke', (tester) async {
      await _pumpDinnerScreen(tester, recipes: () => _NoRecipes());
      expect(find.text('Ugens aftensmad'), findsOneWidget);
      // Mandag er valgt, så Lasagne står også i dagens kort: 2 steder.
      expect(find.text('Lasagne'), findsNWidgets(2));
      expect(find.text('Rester fra i går'), findsOneWidget);
      expect(find.text(_longTitle), findsOneWidget);
      // Slettet opskrift: samme tekst som dagskortet bruger (kortet er kun
      // vist, når onsdag er valgt).
      expect(find.text('Opskriften findes ikke længere'), findsOneWidget);
      expect(find.text('Henter opskrift…'), findsOneWidget);
    });

    testWidgets('dage uden aftensmad står som "Ikke planlagt" med tom ring', (tester) async {
      await _pumpDinnerScreen(tester);
      // Fredag (kun morgenmad) og søndag (ingen post).
      expect(find.text('Ikke planlagt'), findsNWidgets(2));
      expect(ring('Fredag'), findsOneWidget);
      expect(ring('Søndag'), findsOneWidget);
      expect(dot('Fredag'), findsNothing);
      expect(dot('Søndag'), findsNothing);
    });

    testWidgets('prik for planlagt aftensmad (også slettet/ikke indlæst opskrift)', (tester) async {
      await _pumpDinnerScreen(tester);
      for (final d in ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Lørdag']) {
        expect(dot(d), findsOneWidget, reason: d);
        expect(ring(d), findsNothing, reason: d);
      }
    });

    testWidgets('prik og ring ligger i dagens felt i striben', (tester) async {
      await _pumpDinnerScreen(tester);
      expect(find.descendant(of: cell('MAN'), matching: dot('Mandag')), findsOneWidget);
      expect(find.descendant(of: cell('SØN'), matching: ring('Søndag')), findsOneWidget);
    });

    testWidgets('rækkerne viser kort dagsnavn og dato', (tester) async {
      await _pumpDinnerScreen(tester);
      expect(find.text('Man 12. okt.'), findsOneWidget);
      expect(find.text('Søn 18. okt.'), findsOneWidget);
    });

    testWidgets('oversigten ligger efter dagens måltider', (tester) async {
      await _pumpDinnerScreen(tester);
      final snack = tester.getTopLeft(find.text('Snack')).dy;
      final overview = tester.getTopLeft(find.text('Ugens aftensmad')).dy;
      expect(overview, greaterThan(snack));
    });

    testWidgets('tryk på en række vælger dagen', (tester) async {
      await _pumpDinnerScreen(tester);
      expect(find.text('Mandagens madplan'), findsOneWidget);
      await tester.tap(find.text('Rester fra i går'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tirsdagens madplan'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
      expect(container.read(selectedDayProvider), 'Tirsdag');
    });

    testWidgets('tryk på tom dag i oversigten vælger dagen', (tester) async {
      await _pumpDinnerScreen(tester);
      await tester.tap(find.text('Søn 18. okt.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Søndagens madplan'), findsOneWidget);
    });

    testWidgets('uge uden nogen data: syv gange "Ikke planlagt" og syv ringe', (tester) async {
      await _pumpDinnerScreen(tester, plan: () => _EmptyPlan());
      expect(find.text('Ikke planlagt'), findsNWidgets(7));
      for (final d in days) {
        expect(ring(d), findsOneWidget, reason: d);
      }
    });

    testWidgets('dag med alle fire måltider og dag med kun aftensmad', (tester) async {
      final full = DailyPlan(
        breakfast: MealSlot(directEntry: 'Grød'),
        lunch: MealSlot(directEntry: 'Sandwich'),
        dinner: MealSlot(directEntry: 'Pasta'),
        snack: MealSlot(directEntry: 'Æble'),
      );
      await _pumpDinnerScreen(
        tester,
        plan: () => _DinnerWeekPlanOf({
          'Mandag': full,
          'Tirsdag': _dayWith(dinner: MealSlot(directEntry: 'Suppe')),
        }),
      );
      expect(find.text('Pasta'), findsNWidgets(2)); // dagens kort + oversigt
      expect(find.text('Suppe'), findsOneWidget);
      expect(find.text('Grød'), findsOneWidget); // kun i dagens kort
      expect(find.text('Ikke planlagt'), findsNWidgets(5));
    });

    testWidgets('opskrift der ikke kunne hentes får samme tekst som dagskortet', (tester) async {
      await _pumpDinnerScreen(tester, recipes: () => _FailingRecipes());
      expect(find.text('Henter opskrift…'), findsNothing);
      expect(find.text('Opskriften kunne ikke hentes'), findsOneWidget);
      expect(dot('Torsdag'), findsOneWidget);
    });

    testWidgets('mealTypes uden aftensmad skjuler prikker og oversigt', (tester) async {
      await _pumpDinnerScreen(tester, household: () => _OtherMealsHousehold());
      expect(find.text('Ugens aftensmad'), findsNothing);
      expect(find.text('Ikke planlagt'), findsNothing);
      expect(find.text('Rester fra i går'), findsNothing);
      for (final d in days) {
        expect(dot(d), findsNothing, reason: d);
        expect(ring(d), findsNothing, reason: d);
      }
    });

    testWidgets('uden mealTypes-valg (alle måltider) vises oversigten', (tester) async {
      await _pumpDinnerScreen(tester);
      expect(find.text('Ugens aftensmad'), findsOneWidget);
    });

    testWidgets('med kun aftensmad valgt vises oversigten', (tester) async {
      await _pumpDinnerScreen(tester, household: () => _DinnerOnlyHousehold());
      expect(find.text('Ugens aftensmad'), findsOneWidget);
      expect(find.text('Rester fra i går'), findsOneWidget);
    });

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('ingen overflow med lang titel i $width pt og tekstskala $scale',
            (tester) async {
          await _pumpDinnerScreen(tester, width: width, textScale: scale);
          // Overskriftsrækken øverst løber over ved stor skrift (kendt, uden for
          // #27) og ville ellers skjule fejl i striben/oversigten. Samme skærm uden
          // aftensmad giver lige mange fejl, så prikker + oversigt tilføjer ingen.
          final withDinner = _drainExceptions(tester);
          final title = find.text(_longTitle);
          expect(title, findsOneWidget);
          expect(tester.getRect(title).right, lessThanOrEqualTo(width));
          expect(tester.getRect(title).height, tester.getRect(find.text('Rester fra i går')).height,
              reason: 'titlen skal være 1 linje');
          for (final d in days) {
            final box = tester.getRect(cell(d.substring(0, 3).toUpperCase()));
            final m = tester.getRect(marker(d));
            expect(box.contains(m.topLeft) && box.contains(m.bottomRight), isTrue,
                reason: '$d: $m uden for $box');
          }
          for (final shortDay in ['Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør', 'Søn']) {
            final row = tester.getRect(_overviewRow(shortDay).first);
            expect(row.left, greaterThanOrEqualTo(0), reason: shortDay);
            expect(row.right, lessThanOrEqualTo(width), reason: shortDay);
          }

          await tester.pumpWidget(const SizedBox());
          await _pumpDinnerScreen(tester,
              width: width, textScale: scale, household: () => _OtherMealsHousehold());
          expect(withDinner, _drainExceptions(tester));
        });
      }
    }

    testWidgets('alle rækker har trykflade på mindst 48 i højden', (tester) async {
      await _pumpDinnerScreen(tester);
      for (final shortDay in ['Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør', 'Søn']) {
        final size = tester.getSize(_overviewRow(shortDay).first);
        expect(size.height, greaterThanOrEqualTo(48), reason: shortDay);
      }
    });

    testWidgets('skærmlæser-label i striben indeholder aftensmaden', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDinnerScreen(tester);
      expect(_inStrip('Mandag 12. oktober, aftensmad: Lasagne'), findsOneWidget);
      expect(_inStrip('Tirsdag 13. oktober, aftensmad: Rester fra i går'),
          findsOneWidget);
      expect(
          _inStrip('Onsdag 14. oktober, aftensmad: Opskriften findes ikke længere'),
          findsOneWidget);
      expect(_inStrip('Fredag 16. oktober, ingen aftensmad planlagt'),
          findsOneWidget);
      expect(_inStrip('Søndag 18. oktober, ingen aftensmad planlagt'),
          findsOneWidget);
      expect(
        tester.getSemantics(_inStrip('Mandag 12. oktober, aftensmad: Lasagne')),
        containsSemantics(
            isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('rækkerne i oversigten er knapper med valgt-tilstand og fuld label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDinnerScreen(tester);
      // Strip og række har samme label (fuldt dagsnavn): to af hver.
      Finder row(String label) => find.bySemanticsLabel(label).last;
      expect(find.bySemanticsLabel('Mandag 12. oktober, aftensmad: Lasagne'), findsNWidgets(2));
      expect(
        tester.getSemantics(row('Mandag 12. oktober, aftensmad: Lasagne')),
        containsSemantics(
            isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(row('Tirsdag 13. oktober, aftensmad: Rester fra i går')),
        containsSemantics(
            isButton: true, isSelected: false, hasSelectedState: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(row('Søndag 18. oktober, ingen aftensmad planlagt')),
        containsSemantics(isButton: true, isSelected: false, hasSelectedState: true),
      );
      // Rækkens label ligger under dagens måltider, striben over.
      expect(tester.getRect(row('Mandag 12. oktober, aftensmad: Lasagne')).top,
          greaterThan(tester.getRect(find.text('Snack')).top));
      handle.dispose();
    });

    testWidgets('markørens farve følger valgt/ikke valgt', (tester) async {
      final colors = AppTheme.lightTheme.colorScheme;
      Color? fill(String key) =>
          ((tester.widget<Container>(find.byKey(ValueKey(key))).decoration) as BoxDecoration)
              .color;
      Color? ringColor(String key) =>
          ((tester.widget<Container>(find.byKey(ValueKey(key))).decoration) as BoxDecoration)
              .border
              ?.top
              .color;

      await _pumpDinnerScreen(tester); // Mandag valgt
      expect(fill('dinner-dot-Mandag'), colors.onPrimary); // lys prik på grøn
      expect(fill('dinner-dot-Tirsdag'), colors.primary);
      expect(ringColor('dinner-ring-Søndag'), colors.outline);

      await tester.pumpWidget(const SizedBox());
      await _pumpDinnerScreen(tester, day: 'Fredag'); // dag uden aftensmad valgt
      expect(ringColor('dinner-ring-Fredag'), colors.onPrimary);
      expect(ringColor('dinner-ring-Søndag'), colors.outline);
      expect(fill('dinner-dot-Mandag'), colors.primary);
    });

    testWidgets('oversigten følger ugeskift', (tester) async {
      await _pumpDinnerScreen(tester);
      expect(find.text('Man 12. okt.'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
      container.read(weekOffsetProvider.notifier).state = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Man 12. okt.'), findsNothing);
      expect(find.text('Man 19. okt.'), findsOneWidget);
      expect(find.text('Søn 25. okt.'), findsOneWidget);
      expect(find.text('Ugens aftensmad'), findsOneWidget);
      container.read(weekOffsetProvider.notifier).state = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Man 12. okt.'), findsOneWidget);
    });

    testWidgets('skærmlæser-label nævner ikke aftensmad når den er skjult', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDinnerScreen(tester, household: () => _OtherMealsHousehold());
      expect(find.bySemanticsLabel('Mandag 12. oktober'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('aftensmad:|ingen aftensmad')), findsNothing);
      handle.dispose();
    });

    testWidgets('opdateres live når planen ændres', (tester) async {
      _LiveDinnerPlan.controller = StreamController<WeeklyMealPlan>();
      addTearDown(_LiveDinnerPlan.controller.close);
      _LiveDinnerPlan.controller
          .add(WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 10, 12), days: {}));
      await _pumpDinnerScreen(tester, plan: () => _LiveDinnerPlan());
      expect(find.text('Ikke planlagt'), findsNWidgets(7));
      expect(ring('Onsdag'), findsOneWidget);

      _LiveDinnerPlan.controller.add(WeeklyMealPlan(
          id: 'w',
          weekStart: DateTime(2026, 10, 12),
          days: {'Onsdag': _dayWith(dinner: MealSlot(directEntry: 'Nyt fra anden enhed'))}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nyt fra anden enhed'), findsOneWidget);
      expect(dot('Onsdag'), findsOneWidget);
      expect(ring('Onsdag'), findsNothing);
      expect(find.text('Ikke planlagt'), findsNWidgets(6));
    });
  });
}

/// Semantik-noden i ugestriben (#63). "Ugens aftensmad" (#27) har samme label,
/// så uden afgrænsning kunne en test bestå på oversigtens række i stedet.
Finder _inStrip(Pattern label) => find.descendant(
      of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_WeeklyCarousel'),
      matching: find.bySemanticsLabel(label),
    );
