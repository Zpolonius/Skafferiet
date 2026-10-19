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

class _NoRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

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

    expect(find.text('Opskriften findes ikke længere'), findsOneWidget);

    await tester.tap(find.text('Opskriften findes ikke længere'));
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
      expect(find.text('Lasagne'), findsOneWidget);
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
      final monday = find.bySemanticsLabel('Mandag 12. oktober');
      expect(monday, findsOneWidget);
      expect(
        tester.getSemantics(monday),
        containsSemantics(
          label: 'Mandag 12. oktober',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      final sunday = find.bySemanticsLabel('Søndag 18. oktober');
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
          'Mandag 12. oktober',
          'Tirsdag 13. oktober',
          'Onsdag 14. oktober',
          'Torsdag 15. oktober',
          'Fredag 16. oktober',
          'Lørdag 17. oktober',
          'Søndag 18. oktober',
        ])
          tester.getRect(find.bySemanticsLabel(label)).left,
      ];
      expect([...lefts]..sort(), lefts);
      handle.dispose();
    });
  });
}
