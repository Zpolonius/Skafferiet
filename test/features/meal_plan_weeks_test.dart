// Uge-overblik i madplanen (#56): tydelig uge i overskriften, weekendhjælp og
// tilbud om at kopiere forrige uge. Uret styres via clockProvider.
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
import 'package:skafferiet/core/services/week_copy.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/core/models/recipe.dart';
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

class _NoRecipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

// 2026-10-15 er en torsdag; ugen er 12.-18. okt. (ISO-uge 42).
final _thursday = DateTime(2026, 10, 15, 18, 17);
final _saturday = DateTime(2026, 10, 17, 9, 30);
final _sunday = DateTime(2026, 10, 18, 23, 30);

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, String id) =>
    fs.collection('households').doc('h1').collection('meal_plans').doc(id);

Future<Map<String, dynamic>?> _slot(
    FakeFirebaseFirestore fs, String week, String day,
    [String key = 'dinner']) async {
  final d = (await _doc(fs, week).get()).data();
  return ((d?['days'] as Map?)?[day] as Map?)?[key] as Map<String, dynamic>?;
}

/// Som den rigtige, men kopieringen bliver aldrig bekræftet af serveren (som
/// offline): Fortryd skal så tjekke den lokale kopi.
class _OfflineCopyPlan extends MealPlanNotifier {
  _OfflineCopyPlan(FirebaseFirestore fs) : super(firestore: fs);
  bool undoSawPending = false;

  @override
  Future<WeekCopy?> copyWeek({required List<PlannedSlot> from}) async {
    final copy = await super.copyWeek(from: from);
    if (copy == null) return null;
    return WeekCopy(copy.weekId, copy.slots, Completer<void>().future);
  }

  @override
  Future<void> undoCopy(WeekCopy copy, {bool ownWritePending = false}) {
    undoSawPending = ownWritePending;
    return super.undoCopy(copy, ownWritePending: ownWritePending);
  }
}

/// Kopieringen venter på [gate], som en server-transaktion på et langsomt net.
/// Tæller kaldene, så et dobbelttryk kan ses.
class _SlowCopyPlan extends MealPlanNotifier {
  _SlowCopyPlan(FirebaseFirestore fs) : super(firestore: fs);
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<WeekCopy?> copyWeek({required List<PlannedSlot> from}) async {
    calls++;
    await gate.future;
    return super.copyWeek(from: from);
  }
}

class _Env {
  _Env(this.fs, this.container);
  final FakeFirebaseFirestore fs;
  final ProviderContainer container;
  int get offset => container.read(weekOffsetProvider);
}

Future<_Env> _pump(
  WidgetTester tester, {
  required DateTime now,
  Map<String, Map<String, dynamic>> docs = const {},
  Size size = const Size(360, 900),
  MealPlanNotifier Function(FirebaseFirestore fs)? plan,
}) async {
  final fs = FakeFirebaseFirestore();
  for (final e in docs.entries) {
    await _doc(fs, e.key).set(e.value);
  }
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const MealPlanScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(
          () => plan?.call(fs) ?? MealPlanNotifier(firestore: fs)),
      recipesProvider.overrideWith(() => _NoRecipes()),
      householdProvider.overrideWith((ref) => _Household()),
      clockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await _settle(tester);
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MealPlanScreen)));
  return _Env(fs, container);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _plan(Map<String, Map<String, String>> days) => {
      'days': {
        for (final d in days.entries)
          d.key: {
            for (final s in d.value.entries)
              s.key: {'recipeId': null, 'directEntry': s.value}
          }
      }
    };

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  group('overskrift og badge', () {
    testWidgets('denne uge: dato, ISO-ugenummer og badge', (tester) async {
      await _pump(tester, now: _thursday);
      expect(find.text('Uge 42 · 12.–18. okt.'), findsOneWidget);
      expect(find.text('Denne uge'), findsOneWidget);
      expect(find.text('Gå til denne uge'), findsNothing);
      expect(find.bySemanticsLabel('Uge 42, 12. til 18. oktober, denne uge'),
          findsOneWidget);
    });

    testWidgets('næste uge, sidste uge og en uge uden badge', (tester) async {
      final env = await _pump(tester, now: _thursday);
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await _settle(tester);
      expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);
      expect(find.text('Næste uge'), findsOneWidget);
      expect(find.text('Gå til denne uge'), findsOneWidget);

      env.container.read(weekOffsetProvider.notifier).state = -1;
      await _settle(tester);
      expect(find.text('Uge 41 · 5.–11. okt.'), findsOneWidget);
      expect(find.text('Sidste uge'), findsOneWidget);

      env.container.read(weekOffsetProvider.notifier).state = 3;
      await _settle(tester);
      expect(find.text('Uge 45 · 2.–8. nov.'), findsOneWidget);
      for (final badge in ['Denne uge', 'Næste uge', 'Sidste uge']) {
        expect(find.text(badge), findsNothing, reason: badge);
      }
      expect(find.text('Gå til denne uge'), findsOneWidget);
    });

    testWidgets(
        'pilene har tooltips og er mindst 48 dp; "Gå til denne uge" nulstiller',
        (tester) async {
      final env = await _pump(tester, now: _thursday);
      for (final tip in ['Forrige uge', 'Næste uge', 'Mine måltider']) {
        final size = tester.getSize(find.byTooltip(tip));
        expect(size.width, greaterThanOrEqualTo(48), reason: tip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tip);
      }
      await tester.tap(find.byTooltip('Næste uge'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Næste uge'));
      await _settle(tester);
      expect(env.offset, 2);
      await tester.tap(find.byTooltip('Forrige uge'));
      await _settle(tester);
      expect(env.offset, 1);
      await tester.tap(find.text('Gå til denne uge'));
      await _settle(tester);
      expect(env.offset, 0);
      expect(find.text('Denne uge'), findsOneWidget);
    });

    testWidgets('ugestriben viser 12.-18. og ingen overflow på 360 dp',
        (tester) async {
      await _pump(tester, now: _thursday);
      expect(tester.takeException(), isNull);
      for (final d in ['12', '13', '14', '15', '16']) {
        expect(find.text(d), findsWidgets, reason: d);
      }
    });
  });

  group('valgt dag ved start', () {
    testWidgets('madplanen åbner på dagens ugedag og viser dens måltider',
        (tester) async {
      final env = await _pump(tester, now: _thursday, docs: {
        '2026-10-12': _plan({
          'Mandag': {'dinner': 'Mandagsmad'},
          'Torsdag': {'dinner': 'Tacos'},
        }),
      });
      expect(env.container.read(selectedDayProvider), 'Torsdag');
      expect(find.text('Tacos'), findsOneWidget);
      expect(find.text('Mandagsmad'), findsNothing);
    });

    testWidgets('søndag åbner på søndag', (tester) async {
      final env = await _pump(tester, now: _sunday);
      expect(env.container.read(selectedDayProvider), 'Søndag');
    });
  });

  group('weekendhjælp', () {
    testWidgets('vises lørdag og søndag i denne uge', (tester) async {
      for (final now in [_saturday, _sunday]) {
        await _pump(tester, now: now);
        expect(find.text('Planlægger du næste uge?'), findsOneWidget,
            reason: '$now');
        expect(find.text('Gå til næste uge'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('vises ikke på hverdage', (tester) async {
      for (var day = 12; day <= 16; day++) {
        await _pump(tester, now: DateTime(2026, 10, day, 12));
        expect(find.text('Planlægger du næste uge?'), findsNothing,
            reason: 'dag $day');
      }
    });

    testWidgets('vises ikke når man ser en anden uge', (tester) async {
      final env = await _pump(tester, now: _saturday);
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await _settle(tester);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
      env.container.read(weekOffsetProvider.notifier).state = -1;
      await _settle(tester);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
    });

    testWidgets('"Gå til næste uge" åbner næste uge', (tester) async {
      final env = await _pump(tester, now: _sunday);
      await tester.tap(find.text('Gå til næste uge'));
      await _settle(tester);
      expect(env.offset, 1);
      expect(find.text('Uge 43 · 19.–25. okt.'), findsOneWidget);
      expect(find.text('Næste uge'), findsOneWidget);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
    });

    testWidgets('Skjul skjuler resten af weekenden, også efter ugeskift',
        (tester) async {
      final env = await _pump(tester, now: _saturday);
      expect(find.byTooltip('Skjul'), findsOneWidget);
      await tester.tap(find.byTooltip('Skjul'));
      await _settle(tester);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await _settle(tester);
      env.container.read(weekOffsetProvider.notifier).state = 0;
      await _settle(tester);
      expect(find.text('Planlægger du næste uge?'), findsNothing);
    });
  });

  group('tom uge: kopiér forrige uge', () {
    final lastWeek = {
      '2026-10-05': _plan({
        'Mandag': {'dinner': 'Pasta'},
        'Tirsdag': {'lunch': 'Suppe', 'dinner': 'Fiskefrikadeller'},
      }),
    };

    testWidgets('tilbyder at kopiere, og Kopiér skriver ét dokument + Fortryd',
        (tester) async {
      final env = await _pump(tester, now: _thursday, docs: lastWeek);
      expect(find.text('Sidste uge havde 3 måltider – kopiér til denne uge?'),
          findsOneWidget);

      await tester.tap(find.text('Kopiér'));
      await _settle(tester);
      expect(find.text('3 måltider kopieret'), findsOneWidget);
      expect(find.text('Fortryd'), findsOneWidget);
      expect(find.textContaining('Sidste uge havde'), findsNothing);
      expect(await _slot(env.fs, '2026-10-12', 'Mandag'),
          {'recipeId': null, 'directEntry': 'Pasta'});
      expect(await _slot(env.fs, '2026-10-12', 'Tirsdag', 'lunch'),
          {'recipeId': null, 'directEntry': 'Suppe'});
      // Forrige uge er urørt.
      expect(await _slot(env.fs, '2026-10-05', 'Mandag'),
          {'recipeId': null, 'directEntry': 'Pasta'});

      await tester.tap(find.text('Fortryd'));
      await _settle(tester);
      for (final s in [
        ['Mandag', 'dinner'],
        ['Tirsdag', 'lunch'],
        ['Tirsdag', 'dinner'],
      ]) {
        expect(await _slot(env.fs, '2026-10-12', s[0], s[1]),
            {'recipeId': null, 'directEntry': null},
            reason: s.join('/'));
      }
      // Tilbuddet kommer igen, da ugen er tom igen.
      expect(find.text('Sidste uge havde 3 måltider – kopiér til denne uge?'),
          findsOneWidget);
    });

    testWidgets(
        'kopierer opskrift-referencer, også til opskrifter der ikke findes',
        (tester) async {
      final env = await _pump(tester, now: _thursday, docs: {
        '2026-10-05': {
          'days': {
            'Fredag': {
              'dinner': {'recipeId': 'gone', 'directEntry': null}
            }
          }
        },
      });
      expect(find.text('Sidste uge havde 1 måltid – kopiér til denne uge?'),
          findsOneWidget);
      await tester.tap(find.text('Kopiér'));
      await _settle(tester);
      expect(find.text('1 måltid kopieret'), findsOneWidget);
      expect(await _slot(env.fs, '2026-10-12', 'Fredag'),
          {'recipeId': 'gone', 'directEntry': null});
    });

    testWidgets('vises ikke når ugen har måltider eller forrige uge er tom',
        (tester) async {
      await _pump(tester, now: _thursday, docs: {
        ...lastWeek,
        '2026-10-12': _plan({
          'Onsdag': {'dinner': 'Burger'}
        }),
      });
      expect(find.textContaining('havde'), findsNothing);
      expect(find.text('Kopiér'), findsNothing);
      expect(find.text('Burger'), findsNothing); // valgt dag er mandag
    });

    testWidgets('vises ikke når forrige uge kun har ryddede måltider',
        (tester) async {
      await _pump(tester, now: _thursday, docs: {
        '2026-10-05': {
          'days': {
            'Mandag': {
              'dinner': {'recipeId': null, 'directEntry': null}
            }
          }
        },
      });
      expect(find.text('Kopiér'), findsNothing);
    });

    testWidgets('kan lukkes, og kommer ikke igen i samme uge', (tester) async {
      final env = await _pump(tester, now: _thursday, docs: lastWeek);
      await tester.tap(find.byTooltip('Skjul forslag'));
      await _settle(tester);
      expect(find.textContaining('Sidste uge havde'), findsNothing);
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await _settle(tester);
      env.container.read(weekOffsetProvider.notifier).state = 0;
      await _settle(tester);
      expect(find.textContaining('Sidste uge havde'), findsNothing);
    });

    testWidgets('næste uge tilbyder at kopiere denne uge', (tester) async {
      final env = await _pump(tester, now: _thursday, docs: {
        '2026-10-12': _plan({
          'Mandag': {'dinner': 'Pasta'}
        }),
      });
      env.container.read(weekOffsetProvider.notifier).state = 1;
      await _settle(tester);
      expect(find.text('Uge 42 har 1 måltid – kopiér til uge 43?'),
          findsOneWidget);
    });

    testWidgets('overskriver aldrig et måltid der er udfyldt i mellemtiden',
        (tester) async {
      final env = await _pump(tester, now: _thursday, docs: lastWeek);
      expect(find.text('Kopiér'), findsOneWidget);
      // Et andet medlem fylder Mandag/aftensmad lige før der trykkes.
      await _doc(env.fs, '2026-10-12').set(_plan({
        'Mandag': {'dinner': 'Burger'}
      }));
      final notifier = env.container.read(mealPlanProvider.notifier);
      await _settle(tester);
      expect(find.text('Kopiér'), findsNothing);
      // Direkte kald (som om tryk og ændring mødtes): kun tomme pladser kopieres.
      final previous =
          slotsOfData((await _doc(env.fs, '2026-10-05').get()).data());
      final copy = await notifier.copyWeek(from: previous);
      expect(copy, isNotNull);
      await copy!.write;
      expect(copy.slots.length, 2);
      await _settle(tester);
      expect(await _slot(env.fs, '2026-10-12', 'Mandag'),
          {'recipeId': null, 'directEntry': 'Burger'});
      expect(await _slot(env.fs, '2026-10-12', 'Tirsdag', 'dinner'),
          {'recipeId': null, 'directEntry': 'Fiskefrikadeller'});
    });

    testWidgets('dobbelttryk på Kopiér kopierer én gang og beholder Fortryd',
        (tester) async {
      late _SlowCopyPlan plan;
      await _pump(tester,
          now: _thursday,
          docs: lastWeek,
          plan: (fs) => plan = _SlowCopyPlan(fs));
      await tester.tap(find.text('Kopiér'));
      await tester.pump();
      await tester.tap(find.text('Kopiér'), warnIfMissed: false);
      await tester.pump();
      plan.gate.complete();
      await _settle(tester);
      expect(plan.calls, 1);
      expect(find.text('3 måltider kopieret'), findsOneWidget);
      expect(find.text('Fortryd'), findsOneWidget);
      expect(find.textContaining('intet blev kopieret'), findsNothing);
    });

    testWidgets(
        'Fortryd virker også når kopieringen ikke er bekræftet (offline)',
        (tester) async {
      late _OfflineCopyPlan plan;
      final env = await _pump(tester,
          now: _thursday,
          docs: lastWeek,
          plan: (fs) => plan = _OfflineCopyPlan(fs));
      await tester.tap(find.text('Kopiér'));
      await _settle(tester);
      expect(find.text('3 måltider kopieret'), findsOneWidget);
      await tester.tap(find.text('Fortryd'));
      await _settle(tester);
      expect(plan.undoSawPending, isTrue);
      expect(await _slot(env.fs, '2026-10-12', 'Mandag'),
          {'recipeId': null, 'directEntry': null});
      expect(await _slot(env.fs, '2026-10-12', 'Tirsdag', 'dinner'),
          {'recipeId': null, 'directEntry': null});
    });

    testWidgets('Fortryd rører ikke et måltid der er ændret efter kopieringen',
        (tester) async {
      final env = await _pump(tester, now: _thursday, docs: lastWeek);
      await tester.tap(find.text('Kopiér'));
      await _settle(tester);
      await _doc(env.fs, '2026-10-12').set(
          _plan({
            'Mandag': {'dinner': 'Ændret'}
          }),
          SetOptions(merge: true));
      await _settle(tester);
      await tester.tap(find.text('Fortryd'));
      await _settle(tester);
      expect(await _slot(env.fs, '2026-10-12', 'Mandag'),
          {'recipeId': null, 'directEntry': 'Ændret'});
      expect(await _slot(env.fs, '2026-10-12', 'Tirsdag', 'lunch'),
          {'recipeId': null, 'directEntry': null});
    });
  });
}
