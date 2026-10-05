import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/meal_plan/meal_types_sheet.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier() : super(AuthState());
}

/// Husker det seneste valg, ligesom den rigtige notifier gør optimistisk.
class _FakeHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _FakeHouseholdNotifier(List<MealType> mealTypes)
      : super(HouseholdState(householdId: 'h1', mealTypes: mealTypes));

  @override
  Future<void> setMealTypes(Set<MealType> types) async {
    state = state.copyWith(mealTypes: MealType.values.where(types.contains).toList());
  }
}

class _EmptyMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async =>
      WeeklyMealPlan(id: 'test', weekStart: DateTime(2026, 10, 5), days: {});
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('da_DK', null);
  });

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<_FakeHouseholdNotifier> pump(
    WidgetTester tester,
    Widget child,
    List<MealType> mealTypes,
  ) async {
    final household = _FakeHouseholdNotifier(mealTypes);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _MockAuthNotifier()),
        householdProvider.overrideWith((ref) => household),
        mealPlanProvider.overrideWith(() => _EmptyMealPlanNotifier()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
    return household;
  }

  testWidgets('madplanen viser kun brugerens valgte måltider', (tester) async {
    // Bred flade: testfonten gør headerens "Mandag's Madplan" + "Overfør til
    // indkøb" langt bredere end på en rigtig telefon.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, const MealPlanScreen(), [MealType.breakfast, MealType.dinner]);

    expect(find.text('Morgenmad'), findsOneWidget);
    expect(find.text('Aftensmad'), findsOneWidget);
    expect(find.text('Frokost'), findsNothing);
    expect(find.text('Snack'), findsNothing);
  });

  testWidgets('frokost kan slås fra og til igen', (tester) async {
    phoneSize(tester);
    final household = await pump(tester, const MealTypesSheet(), MealType.values);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Frokost'));
    await tester.pump();
    expect(household.state.mealTypes,
        [MealType.breakfast, MealType.dinner, MealType.snack]);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Frokost'));
    await tester.pump();
    expect(household.state.mealTypes, MealType.values);
  });

  testWidgets('det sidste valgte måltid kan ikke slås fra', (tester) async {
    phoneSize(tester);
    await pump(tester, const MealTypesSheet(), [MealType.dinner]);

    final dinner = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Aftensmad'));
    final lunch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Frokost'));
    expect(dinner.onChanged, isNull);
    expect(lunch.onChanged, isNotNull);
  });
}
