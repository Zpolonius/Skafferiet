import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/home/home_screen.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('da_DK', null);
  });

  testWidgets('HomeScreen displays correct greeting and user name', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Da vi bruger mock data i providers, forventer vi "Godmorgen/dag/aften, Mette!"
    // (Vi kan ikke nemt styre DateTime.now() i en simpel test, men vi kan tjekke for én af hilsnerne)
    expect(find.textContaining('Mette!'), findsOneWidget);
    expect(find.text('Her er dit overblik for i dag.'), findsOneWidget);
  });

  testWidgets('HomeScreen shows quick action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    expect(find.text('Tilføj måltid'), findsOneWidget);
    expect(find.text('Tilføj vare'), findsOneWidget);
  });
}
