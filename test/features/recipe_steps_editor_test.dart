import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/features/recipes/recipe_form_widgets.dart';

void main() {
  List<String>? latest;

  Future<void> pumpEditor(WidgetTester tester,
      {List<String> initial = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    latest = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecipeStepsEditor(
              initialSteps: initial, onChanged: (s) => latest = s),
        ),
      ),
    ));
  }

  Future<void> tapText(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  List<String> fieldTexts(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .map((f) => f.controller!.text)
      .toList();

  testWidgets('tom editor viser kun Tilføj trin', (tester) async {
    await pumpEditor(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Tilføj trin'), findsOneWidget);
  });

  testWidgets('tilføj, ret og slet trin', (tester) async {
    await pumpEditor(tester);
    await tapText(tester, find.text('Tilføj trin'));
    await tapText(tester, find.text('Tilføj trin'));
    await tester.enterText(find.widgetWithText(TextField, 'Trin 1'), 'Et');
    await tester.enterText(find.widgetWithText(TextField, 'Trin 2'), 'To');
    expect(latest, ['Et', 'To']);

    await tapText(tester, find.byTooltip('Slet trin').first);
    expect(latest, ['To']);
    expect(fieldTexts(tester), ['To']);
    expect(find.widgetWithText(TextField, 'Trin 1'), findsOneWidget);
  });

  testWidgets('flyt op/ned uden træk, første kan ikke op og sidste ikke ned',
      (tester) async {
    await pumpEditor(tester, initial: ['A', 'B', 'C']);
    final ups = tester
        .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up))
        .toList();
    final downs = tester
        .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down))
        .toList();
    expect(ups.first.onPressed, isNull);
    expect(downs.last.onPressed, isNull);

    await tapText(tester, find.byTooltip('Flyt ned').first);
    expect(fieldTexts(tester), ['B', 'A', 'C']);
    await tapText(tester, find.byTooltip('Flyt op').last);
    expect(fieldTexts(tester), ['B', 'C', 'A']);
    expect(latest, ['B', 'C', 'A']);
  });

  testWidgets('trin kan trækkes i håndtaget', (tester) async {
    await pumpEditor(tester, initial: ['A', 'B', 'C']);
    final handle = find.byIcon(Icons.drag_indicator).first;
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    await g.moveBy(const Offset(0, 200));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(fieldTexts(tester).first, isNot('A'));
    expect(fieldTexts(tester).toSet(), {'A', 'B', 'C'});
  });

  testWidgets('højst 50 trin og 1000 tegn pr. trin', (tester) async {
    await pumpEditor(tester, initial: List.generate(49, (i) => 'Trin $i'));
    await tapText(tester, find.text('Tilføj trin'));
    expect(find.text('Du kan højst have 50 trin'), findsOneWidget);
    final btn = tester.widget<TextButton>(find.ancestor(
        of: find.text('Tilføj trin'),
        matching: find.byWidgetPredicate((w) => w is TextButton)));
    expect(btn.onPressed, isNull);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.maxLength, 1000);
  });

  test('cleanInstructions trimmer og dropper tomme', () {
    expect(cleanInstructions(['  a ', '', '   ', 'b']), ['a', 'b']);
  });
}
