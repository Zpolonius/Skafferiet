// Ugevælgeren i "Til madplan" (#60): små skærme, midnat, fortid, gem og skærmlæser.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart'
    show clockProvider;
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

class _Fs extends Mock implements FirebaseFirestore {}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(mealTypes: MealType.values));
}

class _Plan extends MealPlanNotifier {
  _Plan() : super(firestore: _Fs());
  final weekIds = <String?>[];
  Object? failWith;

  @override
  Stream<WeeklyMealPlan> build() =>
      Stream.value(WeeklyMealPlan(id: 't', weekStart: DateTime.now(), days: {}));

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    weekIds.add(weekId);
    if (failWith != null) throw failWith!;
  }
}

final _recipe = Recipe(
  id: 'r1',
  title: 'Spaghetti Bolognese med ekstra lang titel',
  category: RecipeCategory.aftensmad,
  calories: 650,
  time: '30 min',
  ingredients: [],
);

void main() {
  var now = DateTime(2026, 10, 18, 23, 59); // søndag

  Future<void> open(WidgetTester tester, _Plan plan,
      {Size size = const Size(360, 640),
      double scale = 1.0,
      Future<Recipe> Function(Recipe)? resolve,
      int offset = 0}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mealPlanProvider.overrideWith(() => plan),
        householdProvider.overrideWith((ref) => _Household()),
        clockProvider.overrideWithValue(() => now),
        weekOffsetProvider.overrideWith((ref) => offset),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppBottomSheet(
                context: context,
                builder: (_) =>
                    AddToMealPlanSheet(recipe: _recipe, resolveRecipe: resolve),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() => now = DateTime(2026, 10, 18, 23, 59));

  for (final scale in [1.0, 1.3, 2.0]) {
    // Arket flød over fra skala 1.1 i runde 1; nu kan det scrolle.
    testWidgets('ingen overflow på 360x640 ved tekstskala $scale',
        (tester) async {
      await open(tester, _Plan(), scale: scale, offset: 5);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Næste uge'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fejl i resolveRecipe: arket bliver, Bekræft kan prøves igen',
      (tester) async {
    final plan = _Plan();
    var attempts = 0;
    await open(tester, plan, resolve: (r) async {
      attempts++;
      if (attempts == 1) throw Exception('offline');
      return r;
    });
    await tester.tap(find.byTooltip('Næste uge'));
    await tester.pump();
    await tester.tap(find.text('Tirsdag'));
    await tester.pump();
    await tester.tap(find.text('Aftensmad'));
    await tester.pump();
    await tester.tap(find.text('Bekræft'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Noget gik galt'), findsOneWidget);
    expect(find.byType(AddToMealPlanSheet), findsOneWidget);
    expect(plan.weekIds, isEmpty);
    await tester.tap(find.text('Bekræft'));
    await tester.pumpAndSettle();
    expect(plan.weekIds, ['2026-10-19']);
    expect(find.byType(AddToMealPlanSheet), findsNothing);
    // Fejl-snackbaren står stadig; bekræftelsen ligger i kø bag den.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('${_recipe.title} tilføjet til tirsdag i uge 43 (Aftensmad)'),
        findsOneWidget);
  });

  testWidgets('semantik: ugen læses op, pilene har labels', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, _Plan(), size: const Size(400, 900));
    final node = tester.getSemantics(find.text('Uge 42 · 12.–18. okt.'));
    expect(node.label, 'Uge 42, 12. til 18. oktober, denne uge');
    for (final tip in ['Næste uge', 'Forrige uge']) {
      final b = tester.getSemantics(find.byTooltip(tip));
      expect('${b.label}${b.tooltip}', contains(tip));
    }
    handle.dispose();
  });

  testWidgets('midnat (søndag→mandag) mens arket er åbent: vist == skrevet',
      (tester) async {
    final plan = _Plan();
    await open(tester, plan, size: const Size(400, 900));
    await tester.tap(find.byTooltip('Næste uge'));
    await tester.pump();
    expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);
    now = DateTime(2026, 10, 19, 0, 1);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AddToMealPlanSheet)));
    container.read(todayProvider.notifier).refresh();
    await tester.pump();
    // Den valgte uge er uændret, selv om "i dag" er rykket en uge.
    expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);
    // "i dag" ligger nu i den valgte uge, så badget skifter til "Denne uge".
    expect(find.text('Denne uge'), findsOneWidget);
    expect(find.text('Næste uge'), findsNothing);
    const shownAfter = '2026-10-19';
    await tester.tap(find.text('Tirsdag'));
    await tester.pump();
    await tester.tap(find.text('Aftensmad'));
    await tester.pump();
    await tester.tap(find.text('Bekræft'));
    await tester.pumpAndSettle();
    expect(plan.weekIds.single, shownAfter, reason: 'skrevet uge = vist uge');
  });

  testWidgets('fortid: to uger tilbage har intet badge, én tilbage er "Sidste uge"',
      (tester) async {
    final handle = tester.ensureSemantics();
    final plan = _Plan();
    await open(tester, plan, size: const Size(400, 900));
    await tester.tap(find.byTooltip('Forrige uge'));
    await tester.pump();
    expect(find.text('Sidste uge'), findsOneWidget);
    expect(tester.getSemantics(find.text('Uge 41 · 5.–11. okt.')).label,
        'Uge 41, 5. til 11. oktober, sidste uge');
    await tester.tap(find.byTooltip('Forrige uge'));
    await tester.pump();
    expect(find.text('Sidste uge'), findsNothing);
    expect(find.text('Uge 40 · 28. sep.–4. okt.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('kort indhold: arket fylder kun sit indhold og har runde hjørner',
      (tester) async {
    await open(tester, _Plan(), size: const Size(400, 900));
    final sheet = tester.getRect(find.byType(AddToMealPlanSheet));
    expect(sheet.height, lessThan(700), reason: 'ikke fuld højde: $sheet');
    expect(sheet.bottom, 900);
    final box = tester.widget<Container>(find
        .descendant(of: find.byType(AddToMealPlanSheet), matching: find.byType(Container))
        .first);
    expect((box.decoration as BoxDecoration).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)));
  });

  testWidgets('bundindryk (hjem-streg/tastatur) lægges stadig til', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mealPlanProvider.overrideWith(() => _Plan()),
        householdProvider.overrideWith((ref) => _Household()),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AddToMealPlanSheet(recipe: _recipe)),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final box = tester.widget<Container>(find
        .descendant(of: find.byType(AddToMealPlanSheet), matching: find.byType(Container))
        .first);
    expect((box.padding as EdgeInsets).bottom, 324);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dagslisten scroller stadig vandret inde i den lodrette scroll',
      (tester) async {
    await open(tester, _Plan(), size: const Size(320, 640));
    final sunday = find.text('Søndag');
    expect(sunday.hitTestable(), findsNothing, reason: 'Søndag starter uden for skærmen');
    expect(find.text('Fredag').hitTestable(), findsNothing);
    final y = tester.getCenter(find.text('Mandag')).dy;
    final top = tester.getTopLeft(find.byType(AddToMealPlanSheet)).dy;
    await tester.dragFrom(Offset(250, y), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Mandag'), findsNothing, reason: 'listen er scrollet vandret');
    expect(find.text('Fredag').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AddToMealPlanSheet)).dy, top);
  });

  testWidgets('gemmer: knappen beholder størrelsen og har semantik', (tester) async {
    final handle = tester.ensureSemantics();
    final gate = Completer<Recipe>();
    await open(tester, _Plan(), size: const Size(400, 900), resolve: (_) => gate.future);
    await tester.tap(find.text('Tirsdag'));
    await tester.pump();
    await tester.tap(find.text('Aftensmad'));
    await tester.pump();
    final sizeBefore = tester.getSize(find.byType(FilledButton));
    await tester.tap(find.text('Bekræft'));
    await tester.pump();
    expect(tester.getSize(find.byType(FilledButton)), sizeBefore);
    final node = tester.getSemantics(find.byType(FilledButton));
    expect(node.label, isNotEmpty, reason: 'skærmlæser hører intet mens der gemmes');
    gate.complete(_recipe);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('lukket under gem + fejl: fejl-snackbar, ingen exception', (tester) async {
    final gate = Completer<Recipe>();
    final plan = _Plan()..failWith = Exception('nej');
    await open(tester, plan, size: const Size(400, 900), resolve: (_) => gate.future);
    await tester.tap(find.text('Tirsdag'));
    await tester.pump();
    await tester.tap(find.text('Aftensmad'));
    await tester.pump();
    await tester.tap(find.text('Bekræft'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(AddToMealPlanSheet), findsNothing);
    gate.complete(_recipe);
    await tester.pumpAndSettle();
    expect(find.textContaining('Noget gik galt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lukket under gem + succes: snackbar, intet ekstra pop', (tester) async {
    final gate = Completer<Recipe>();
    final plan = _Plan();
    await open(tester, plan, size: const Size(400, 900), resolve: (_) => gate.future);
    await tester.tap(find.text('Tirsdag'));
    await tester.pump();
    await tester.tap(find.text('Aftensmad'));
    await tester.pump();
    await tester.tap(find.text('Bekræft'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    gate.complete(_recipe);
    await tester.pumpAndSettle();
    expect(plan.weekIds, ['2026-10-12']);
    expect(find.text('open'), findsOneWidget, reason: 'hjemskærmen må ikke poppes');
    expect(find.textContaining('tilføjet til tirsdag i uge 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
