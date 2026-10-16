// QA for #36: redigeringsarket med det rigtige MealPlanNotifier mod
// FakeFirebaseFirestore (data i Firestore, uge, fejl, tilgængelighed).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/services/week_dates.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/edit_meal_slot_sheet.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

final _lasagne = Recipe(
    id: 'r1',
    title: 'Lasagne',
    calories: 600,
    time: '45 min',
    category: RecipeCategory.aftensmad);
final _aebleskiver = Recipe(
    id: 'r2',
    title: 'Æbleskiver med flødeskum',
    calories: 300,
    time: '30 min',
    category: RecipeCategory.snack);
final _long = Recipe(
    id: 'r3',
    title:
        'En meget meget lang opskriftstitel der aldrig slutter og fortsætter på flere linjer i kortet',
    calories: 1,
    time: '1 min',
    category: RecipeCategory.aftensmad,
    imageUrl: '');

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _Recipes(this.source);
  final Stream<List<Recipe>> source;
  @override
  Stream<List<Recipe>> build() => source;
}

/// Real notifier, but writes can be made to hang or fail.
class _GatedPlan extends MealPlanNotifier {
  _GatedPlan(FirebaseFirestore fs) : super(firestore: fs);
  Completer<void>? gate;
  Object? failUpdate;
  Object? failRestore;
  final restoreWeeks = <String?>[];

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry}) async {
    if (gate != null) await gate!.future;
    if (failUpdate != null) throw failUpdate!;
    return super
        .updateSlot(day, slotType, recipe: recipe, directEntry: directEntry);
  }

  @override
  Future<void> restoreSlot(String day, String slotType, MealSlot slot,
      {String? weekId, bool ownRemovePending = false}) async {
    restoreWeeks.add(weekId);
    if (failRestore != null) throw failRestore!;
    return super.restoreSlot(day, slotType, slot,
        weekId: weekId, ownRemovePending: ownRemovePending);
  }
}

String _weekId(int offset) {
  return weekIdOf(addWeeks(weekStartOf(DateTime.now()), offset));
}

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, int offset) =>
    fs
        .collection('households')
        .doc('h1')
        .collection('meal_plans')
        .doc(_weekId(offset));

Future<Map<String, dynamic>?> _slot(
    FakeFirebaseFirestore fs, int offset, String day,
    [String key = 'dinner']) async {
  final d = (await _doc(fs, offset).get()).data();
  return ((d?['days'] as Map?)?[day] as Map?)?[key] as Map<String, dynamic>?;
}

class _Env {
  _Env(this.fs, this.plan, this.container);
  final FakeFirebaseFirestore fs;
  final _GatedPlan plan;
  final ProviderContainer container;
}

Future<_Env> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> dinners,
  int weekOffset = 0,
  Stream<List<Recipe>>? recipes,
  Size size = const Size(390, 1400),
  String day = 'Tirsdag',
}) async {
  final fs = FakeFirebaseFirestore();
  await _doc(fs, weekOffset).set({
    'days': {
      for (final e in dinners.entries) e.key: {'dinner': e.value}
    }
  });
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final plan = _GatedPlan(fs);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const MealPlanScreen()),
    GoRoute(
        path: '/other',
        builder: (_, __) => const Scaffold(body: Text('ANDEN SKÆRM'))),
    GoRoute(
        path: '/recipes/:id',
        builder: (_, s) =>
            Scaffold(body: Text('RECEPT ${s.pathParameters['id']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => plan),
      recipesProvider.overrideWith(() =>
          _Recipes(recipes ?? Stream.value([_lasagne, _aebleskiver, _long]))),
      householdProvider.overrideWith((ref) => _Household()),
      selectedDayProvider.overrideWith((ref) => day),
      weekOffsetProvider.overrideWith((ref) => weekOffset),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await _settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
  return _Env(fs, plan, container);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(EditMealSlotSheet), matching: f);

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  testWidgets(
      'P1 data: Fjern skriver recipeId=null+directEntry=null, Fortryd gendanner missing id præcist',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'gone', 'directEntry': null}
    });
    expect(find.text('Opskriften findes ikke længere'), findsOneWidget);
    await tester.tap(find.text('Opskriften findes ikke længere'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': null, 'directEntry': null});
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': 'gone', 'directEntry': null});
    expect(find.text('Opskriften findes ikke længere'), findsOneWidget);
  });

  testWidgets(
      'P2 Fortryd efter ugeskift skriver tilbage til den oprindelige uge',
      (tester) async {
    final env = await _pump(tester, weekOffset: 1, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    env.container.read(weekOffsetProvider.notifier).state = 3;
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(env.plan.restoreWeeks, [_weekId(1)]);
    expect(await _slot(env.fs, 1, 'Tirsdag'),
        {'recipeId': 'r1', 'directEntry': null});
    expect(await _slot(env.fs, 3, 'Tirsdag'), isNull);
  });

  testWidgets('P3 Fortryd efter navigation til anden skærm og dobbelttryk',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': null, 'directEntry': 'Sushi'}
    });
    await tester.tap(find.text('Sushi'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    GoRouter.of(tester.element(find.byType(MealPlanScreen))).go('/other');
    await _settle(tester);
    expect(find.text('ANDEN SKÆRM'), findsOneWidget);
    expect(find.text('Fortryd'), findsOneWidget,
        reason: 'SnackBar på root messenger');
    await tester.tap(find.text('Fortryd'));
    await tester.pump();
    // Andet tryk: SnackBarAction er allerede brugt / ved at lukke.
    if (find.text('Fortryd').evaluate().isNotEmpty) {
      await tester.tap(find.text('Fortryd'), warnIfMissed: false);
    }
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(env.plan.restoreWeeks.length, 1);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': null, 'directEntry': 'Sushi'});
  });

  testWidgets(
      'P4 travl: knapper låst, arket kan ikke lukkes; fejl -> dansk besked, knapper aktive, kan lukkes, retry virker',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    env.plan.gate = Completer<void>();
    env.plan.failUpdate = Exception('permission-denied');
    await tester.tap(find.text('Fjern fra madplanen'));
    await tester.pump();
    ButtonStyleButton btn(String l) => tester.widget<ButtonStyleButton>(find
        .ancestor(
            of: _inSheet(find.text(l)),
            matching: find.bySubtype<ButtonStyleButton>())
        .first);
    expect(btn('Skift').onPressed, isNull);
    expect(btn('Fjern fra madplanen').onPressed, isNull);
    expect(btn('Se opskrift').onPressed, isNull);
    // Prøv at lukke med barrieren og systemets tilbage.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditMealSlotSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditMealSlotSheet), findsOneWidget);
    env.plan.gate!.complete();
    await _settle(tester);
    expect(find.textContaining('Kunne ikke gemme'), findsOneWidget);
    expect(btn('Fjern fra madplanen').onPressed, isNotNull);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': 'r1', 'directEntry': null});
    // Retry lykkes.
    env.plan.gate = null;
    env.plan.failUpdate = null;
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': null, 'directEntry': null});
  });

  testWidgets('P4b efter fejl kan arket lukkes med barrieren', (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    env.plan.failUpdate = Exception('x');
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
  });

  testWidgets('P5 Fortryd fejler -> dansk fejlbesked', (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    env.plan.failRestore = Exception('x');
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(find.text('Kunne ikke fortryde. Prøv igen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P6 KONKURRENCE: andet medlem ændrer måltid mens arket er åbent',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    // Andet medlem skifter til eget måltid.
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': 'Pizza fra B'}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    final after = await _slot(env.fs, 0, 'Tirsdag');
    expect(after, {'recipeId': null, 'directEntry': 'Pizza fra B'},
        reason: 'Fortryd skal gendanne det måltid arket viste (Pizza fra B), '
            'ikke det forældede Lasagne');
  });

  testWidgets('P7 Fortryd overskriver ikke et andet medlems nye måltid',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': 'Pizza fra B'}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    final after = await _slot(env.fs, 0, 'Tirsdag');
    expect(after, {'recipeId': null, 'directEntry': 'Pizza fra B'});
  });

  testWidgets('P8 "Henter opskrift…": recipes indlæses mens arket er åbent',
      (tester) async {
    final recipes = StreamController<List<Recipe>>();
    addTearDown(recipes.close);
    final env = await _pump(tester, recipes: recipes.stream, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    // Kortet bag viser en neutral henter-tilstand, ikke "Tilføj aftensmad".
    expect(find.text('Tilføj aftensmad'), findsNothing);
    await tester.tap(find.text('Henter opskrift…'));
    await _settle(tester);
    expect(_inSheet(find.text('Henter opskrift…')), findsOneWidget);
    recipes.add([_lasagne]);
    await _settle(tester);
    expect(_inSheet(find.text('Lasagne')), findsOneWidget);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': 'r1', 'directEntry': null});
  });

  testWidgets(
      'P9 opskrifter fejler: ingen crash, picker viser fejl, Fjern+Fortryd bevarer id',
      (tester) async {
    final env =
        await _pump(tester, recipes: Stream.error(Exception('boom')), dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    expect(find.text('Henter opskrift…'), findsNothing);
    await tester.tap(find.text('Opskriften kunne ikke hentes'));
    await _settle(tester);
    expect(_inSheet(find.text('Opskriften kunne ikke hentes')), findsOneWidget);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    expect(_inSheet(find.text('Kunne ikke hente opskrifter')), findsOneWidget);
    await tester.tap(find.text('Tilbage'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': 'r1', 'directEntry': null});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'P10 filter: store bogstaver, æøå, mellemrum; tom liste; samme opskrift',
      (tester) async {
    final handle = tester.ensureSemantics();
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    final field = _inSheet(find.byType(TextField));
    await tester.enterText(field, '  ÆBLESKIVER ');
    await _settle(tester);
    expect(_inSheet(find.text('Æbleskiver med flødeskum')), findsOneWidget);
    expect(_inSheet(find.text('Lasagne')), findsNothing);
    await tester.enterText(field, 'fløde');
    await _settle(tester);
    expect(_inSheet(find.text('Æbleskiver med flødeskum')), findsOneWidget);
    await tester.enterText(field, 'xyz');
    await _settle(tester);
    expect(_inSheet(find.text('Ingen opskrifter matcher')), findsOneWidget);
    await tester.enterText(field, '');
    await _settle(tester);
    // Nuværende markeret.
    expect(find.bySemanticsLabel(RegExp('Nuværende')), findsOneWidget);
    // Samme opskrift igen.
    await tester.tap(_inSheet(find.text('Lasagne')));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': 'r1', 'directEntry': null});
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('P11 tom opskriftsliste viser tom-tilstand', (tester) async {
    await _pump(tester, recipes: Stream.value(const []), dinners: {
      'Tirsdag': {'recipeId': null, 'directEntry': 'Sushi'}
    });
    await tester.tap(find.text('Sushi'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    expect(
        _inSheet(find.text('Du har ingen opskrifter endnu')), findsOneWidget);
  });

  testWidgets('P12 lille skærm + tastatur + lang titel: ingen overflow',
      (tester) async {
    await _pump(tester, size: const Size(320, 568), dinners: {
      'Tirsdag': {'recipeId': 'r3', 'directEntry': null}
    });
    await tester.scrollUntilVisible(
        find.textContaining('En meget meget lang'), 200,
        scrollable: find.byType(Scrollable).first);
    await _settle(tester);
    await tester.tap(find.textContaining('En meget meget lang').first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await tester.tap(_inSheet(find.byType(TextField)));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Eget måltid'));
    await _settle(tester);
    await tester.enterText(_inSheet(find.byType(TextField)), 'Rugbrød');
    await _settle(tester);
    // Gem skal kunne nås (scroll) og trykkes.
    await tester.ensureVisible(_inSheet(find.text('Gem')));
    await _settle(tester);
    final r = tester.getRect(_inSheet(find.text('Gem')));
    expect(r.bottom <= 568 - 280, isTrue, reason: 'Gem must be above keyboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets('P13 tilgængelighed: tap targets, labels, live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Nuværende måltid: Lasagne, 600 kcal')));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    for (final l in ['Se opskrift', 'Skift', 'Fjern fra madplanen']) {
      final s = tester.getSize(find
          .ancestor(
              of: _inSheet(find.text(l)),
              matching: find.bySubtype<ButtonStyleButton>())
          .first);
      expect(s.height >= 48, isTrue, reason: '$l $s');
    }
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('P7b Fortryd efter konflikt skriver intet og forklarer hvorfor',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Fjern fra madplanen'));
    await _settle(tester);
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': 'Pizza fra B'}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    await tester.tap(find.text('Fortryd'));
    await _settle(tester);
    expect(find.text('Måltidet er ændret i mellemtiden – kunne ikke fortryde.'),
        findsOneWidget);
  });

  testWidgets('P6b arket lukkes når et andet medlem rydder måltidet',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': null}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsNothing);
    expect(find.text('Måltidet er fjernet af en anden'), findsOneWidget);
  });

  testWidgets('P6c arket viser et måltid som andet medlem har skiftet til',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': 'Pizza fra B'}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    expect(_inSheet(find.text('Pizza fra B')), findsOneWidget);
    expect(_inSheet(find.text('Se opskrift')), findsNothing);
  });

  testWidgets('P6d Skift: skrevet tekst bevares når et andet medlem rydder',
      (tester) async {
    final env = await _pump(tester, dinners: {
      'Tirsdag': {'recipeId': 'r1', 'directEntry': null}
    });
    await tester.tap(find.text('Lasagne'));
    await _settle(tester);
    await tester.tap(find.text('Skift'));
    await _settle(tester);
    await tester.tap(find.text('Eget måltid'));
    await _settle(tester);
    await tester.enterText(_inSheet(find.byType(TextField)), 'Rugbrød');
    await tester.pump();
    await _doc(env.fs, 0).set({
      'days': {
        'Tirsdag': {
          'dinner': {'recipeId': null, 'directEntry': null}
        }
      }
    }, SetOptions(merge: true));
    await _settle(tester);
    expect(find.byType(EditMealSlotSheet), findsOneWidget);
    expect(find.textContaining('fjernet af en anden'), findsOneWidget);
    await tester.tap(_inSheet(find.text('Gem')));
    await _settle(tester);
    expect(await _slot(env.fs, 0, 'Tirsdag'),
        {'recipeId': null, 'directEntry': 'Rugbrød'});
  });
}
