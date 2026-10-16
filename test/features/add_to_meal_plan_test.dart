import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart'
    show clockProvider;
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

class _MockMealPlanNotifier extends MealPlanNotifier {
  _MockMealPlanNotifier() : super(firestore: MockFirestore());

  String? capturedWeekId;
  int calls = 0;
  String? capturedDay;
  String? capturedSlot;
  Recipe? capturedRecipe;

  @override
  Stream<WeeklyMealPlan> build() =>
      Stream.value(WeeklyMealPlan(id: 'test', weekStart: DateTime.now(), days: {}));

  @override
  Future<void> updateSlot(
    String day,
    String slotType, {
    Recipe? recipe,
    String? directEntry,
    String? weekId,
  }) async {
    capturedWeekId = weekId;
    calls++;
    capturedDay = day;
    capturedSlot = slotType;
    capturedRecipe = recipe;
  }
}

final _testRecipe = Recipe(
  id: 'r1',
  title: 'Spaghetti Bolognese',
  category: RecipeCategory.aftensmad,
  calories: 650,
  time: '30 min',
  ingredients: [],
);

Override _householdOverride(List<MealType> mealTypes) => householdProvider
    .overrideWith((ref) => _MockHouseholdNotifier(HouseholdState(mealTypes: mealTypes)));

// Hjælpefunktion der bygger sheet'en med en route så Navigator.pop() virker
Widget _buildApp(
  _MockMealPlanNotifier notifier, {
  List<MealType> mealTypes = MealType.values,
}) {
  return ProviderScope(
    overrides: [
      mealPlanProvider.overrideWith(() => notifier),
      _householdOverride(mealTypes),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
                ),
              ),
              child: const Text('Åbn'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Sæt telefon-skærmstørrelse så overflow undgås
  const phoneSize = Size(390, 844);

  group('AddToMealPlanSheet', () {
    testWidgets('viser opskriftens navn og titel', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mealPlanProvider.overrideWith(() => notifier),
            _householdOverride(MealType.values),
          ],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spaghetti Bolognese'), findsOneWidget);
      expect(find.text('Tilføj til madplan'), findsOneWidget);
    });

    testWidgets('"Bekræft"-knap er deaktiveret uden valg', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mealPlanProvider.overrideWith(() => notifier),
            _householdOverride(MealType.values),
          ],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('"Bekræft"-knap aktiveres når dag og måltid er valgt', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mealPlanProvider.overrideWith(() => notifier),
            _householdOverride(MealType.values),
          ],
          child: MaterialApp(
            home: Scaffold(body: AddToMealPlanSheet(recipe: _testRecipe)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mandag'));
      await tester.pump();
      await tester.tap(find.text('Aftensmad'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('kalder updateSlot med korrekte værdier', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockMealPlanNotifier();
      await tester.pumpWidget(_buildApp(notifier));

      // Naviger til sheet via route (så Navigator.pop() virker)
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onsdag'));
      await tester.pump();
      await tester.tap(find.text('Frokost'));
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pump(); // lad async-updateSlot køre
      await tester.pump(); // lad Navigator.pop animere

      expect(notifier.capturedDay, 'Onsdag');
      // Firestore-nøglen, som madplanen læser — ikke den danske label.
      expect(notifier.capturedSlot, 'lunch');
      expect(notifier.capturedRecipe?.id, _testRecipe.id);
    });

    testWidgets('viser kun de måltider brugeren har valgt', (tester) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(
        _MockMealPlanNotifier(),
        mealTypes: [MealType.breakfast, MealType.dinner],
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();

      expect(find.text('Morgenmad'), findsOneWidget);
      expect(find.text('Aftensmad'), findsOneWidget);
      expect(find.text('Frokost'), findsNothing);
      expect(find.text('Snack'), findsNothing);
    });
  });

  group('AddToMealPlanSheet – uge (#60)', () {
    // 2026-10-15 er en torsdag; ugen er 12.-18. okt. (uge 42).
    final now = DateTime(2026, 10, 15, 18, 17);

    Future<ProviderContainer> pumpSheet(
      WidgetTester tester,
      _MockMealPlanNotifier notifier, {
      int offset = 0,
      Future<Recipe> Function(Recipe)? resolve,
    }) async {
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mealPlanProvider.overrideWith(() => notifier),
          _householdOverride(MealType.values),
          clockProvider.overrideWithValue(() => now),
          weekOffsetProvider.overrideWith((ref) => offset),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: AddToMealPlanSheet(recipe: _testRecipe, resolveRecipe: resolve),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(AddToMealPlanSheet)));
    }

    Future<void> choose(WidgetTester tester, String day, String meal) async {
      await tester.tap(find.text(day));
      await tester.pump();
      await tester.tap(find.text(meal));
      await tester.pump();
    }

    testWidgets('viser ugenummer, datoer og badge for den viste uge', (tester) async {
      await pumpSheet(tester, _MockMealPlanNotifier());
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(find.text('Denne uge'), findsOneWidget);
    });

    testWidgets('starter på den uge madplanen viser (weekOffsetProvider)', (tester) async {
      final notifier = _MockMealPlanNotifier();
      await pumpSheet(tester, notifier, offset: 1);
      expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);
      expect(find.text('Næste uge'), findsWidgets);

      await choose(tester, 'Tirsdag', 'Aftensmad');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(notifier.capturedWeekId, '2026-10-19');
    });

    testWidgets('pile skifter uge, gemmer i den uge og lader madplanens uge være',
        (tester) async {
      final notifier = _MockMealPlanNotifier();
      final container = await pumpSheet(tester, notifier);
      for (final tip in ['Forrige uge', 'Næste uge']) {
        final size = tester.getSize(find.byTooltip(tip));
        expect(size.width, greaterThanOrEqualTo(48), reason: tip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tip);
      }
      await tester.tap(find.byTooltip('Næste uge'));
      await tester.pumpAndSettle();
      expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);

      await choose(tester, 'Tirsdag', 'Aftensmad');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(notifier.capturedWeekId, '2026-10-19');
      expect(container.read(weekOffsetProvider), 0);
    });

    testWidgets('forrige uge to gange giver mandagen to uger tilbage', (tester) async {
      final notifier = _MockMealPlanNotifier();
      await pumpSheet(tester, notifier);
      await tester.tap(find.byTooltip('Forrige uge'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Forrige uge'));
      await tester.pumpAndSettle();
      expect(find.text('Uge 40 · 28. sep.–4. okt.'), findsOneWidget);
      await choose(tester, 'Mandag', 'Frokost');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(notifier.capturedWeekId, '2026-09-28');
    });

    testWidgets('bekræftelsen nævner dag og uge', (tester) async {
      await pumpSheet(tester, _MockMealPlanNotifier());
      await tester.tap(find.byTooltip('Næste uge'));
      await tester.pumpAndSettle();
      await choose(tester, 'Tirsdag', 'Aftensmad');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();
      expect(find.text('Spaghetti Bolognese tilføjet til tirsdag i uge 43 (Aftensmad)'),
          findsOneWidget);
    });

    testWidgets('dobbelttryk på Bekræft skriver kun én gang', (tester) async {
      final gate = Completer<Recipe>();
      final notifier = _MockMealPlanNotifier();
      await pumpSheet(tester, notifier, resolve: (_) => gate.future);
      await choose(tester, 'Tirsdag', 'Aftensmad');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      gate.complete(_testRecipe);
      await tester.pumpAndSettle();
      expect(notifier.calls, 1);
    });

    testWidgets('viser fremdrift mens der gemmes og snackbar også hvis arket er lukket',
        (tester) async {
      final gate = Completer<Recipe>();
      await tester.binding.setSurfaceSize(phoneSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mealPlanProvider.overrideWith(() => _MockMealPlanNotifier()),
          _householdOverride(MealType.values),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: AddToMealPlanSheet(recipe: _testRecipe, resolveRecipe: (_) => gate.future),
                  ),
                )),
                child: const Text('Åbn'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Åbn'));
      await tester.pumpAndSettle();
      await choose(tester, 'Tirsdag', 'Aftensmad');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Bekræft'), findsNothing);
      // Arket lukkes (X) mens der gemmes.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(AddToMealPlanSheet), findsNothing);
      gate.complete(_testRecipe);
      await tester.pumpAndSettle();
      expect(find.textContaining('tilføjet til tirsdag'), findsOneWidget);
    });
  });
}
