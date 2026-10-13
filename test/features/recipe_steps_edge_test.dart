// Kanttilfælde for fremgangsmåden (#25): trin-editoren og detaljeskærmen.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/recipes/recipe_detail_screen.dart';
import 'package:skafferiet/features/recipes/recipe_form_widgets.dart';

void main() {
  List<String>? latest;

  void phone(WidgetTester tester, {double width = 1080, double height = 2400}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpEditor(WidgetTester tester,
      {List<String> initial = const []}) async {
    phone(tester);
    latest = null;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecipeStepsEditor(
              initialSteps: initial, onChanged: (s) => latest = s),
        ),
      ),
    ));
  }

  Future<void> pumpDetail(WidgetTester tester, List<String> steps,
      {double width = 1080}) async {
    phone(tester, width: width);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: RecipeInstructions(steps: steps),
        ),
      ),
    ));
  }

  EditableText editable(WidgetTester tester, int i) =>
      tester.widget<EditableText>(find.byType(EditableText).at(i));

  group('editor', () {
    testWidgets('nyt trin får fokus', (tester) async {
      await pumpEditor(tester, initial: ['A']);
      await tester.tap(find.text('Tilføj trin'));
      await tester.pumpAndSettle();
      expect(editable(tester, 1).focusNode.hasFocus, isTrue);
      expect(editable(tester, 0).focusNode.hasFocus, isFalse);
    });

    testWidgets('fokus og tekst følger trinnet ved Flyt ned', (tester) async {
      await pumpEditor(tester, initial: ['A', 'B']);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      final ctrlA = editable(tester, 0).controller;
      await tester.tap(find.byTooltip('Flyt ned').first);
      await tester.pumpAndSettle();
      expect(editable(tester, 1).controller, same(ctrlA));
      expect(editable(tester, 1).controller.text, 'A');
      expect(tester.takeException(), isNull);
    });

    testWidgets('slet trinnet der har fokus kaster ikke', (tester) async {
      await pumpEditor(tester, initial: ['A', 'B']);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Slet trin').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(latest, ['B']);
      // Skriv videre i det tilbageværende felt
      await tester.enterText(find.byType(TextField), 'B2');
      expect(latest, ['B2']);
    });

    testWidgets('1000 tegn håndhæves ved indtastning', (tester) async {
      await pumpEditor(tester, initial: ['']);
      await tester.enterText(find.byType(TextField), 'x' * 1200);
      await tester.pump();
      expect(latest!.single.length, 1000);
    });

    testWidgets('indsat flerlinjet tekst bliver ét trin', (tester) async {
      await pumpEditor(tester, initial: ['']);
      await tester.enterText(find.byType(TextField), ' linje 1\nlinje 2 \n');
      expect(cleanInstructions(latest!), ['linje 1\nlinje 2']);
    });

    testWidgets(
        'initialSteps over 50 (gammel data) vises og knappen er slået fra',
        (tester) async {
      await pumpEditor(tester, initial: List.generate(51, (i) => 'T$i'));
      expect(find.text('Du kan højst have 50 trin'), findsOneWidget);
    });

    testWidgets('semantik: felt og knapper er separate noder i rækkefølge',
        (tester) async {
      final h = tester.ensureSemantics();
      await pumpEditor(tester, initial: ['A', 'B']);
      expect(find.bySemanticsLabel(RegExp('Trin 1')), findsOneWidget);
      expect(find.byTooltip('Flyt op'), findsNWidgets(2));
      final up1 = tester.getSemantics(find.byTooltip('Flyt op').first);
      expect(up1.tooltip, 'Flyt op');
      expect(up1.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      final down1 = tester.getSemantics(find.byTooltip('Flyt ned').first);
      expect(down1.tooltip, 'Flyt ned');
      expect(down1.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final del1 = tester.getSemantics(find.byTooltip('Slet trin').first);
      expect(del1.tooltip, 'Slet trin');
      // Feltet og knapperne er ikke flettet sammen
      final field = tester.getSemantics(find.byType(EditableText).first);
      expect(field.label, 'Trin 1');
      expect(field.id, isNot(del1.id));

      // Rækkefølge: felt for trin 1 kommer før dets knapper, som kommer før trin 2
      final field1 = tester.getRect(find.byType(TextField).at(0));
      final del1r = tester.getRect(find.byTooltip('Slet trin').at(0));
      final field2 = tester.getRect(find.byType(TextField).at(1));
      expect(del1r.top, greaterThan(field1.top));
      expect(field2.top, greaterThan(del1r.top));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });

    testWidgets('træk: præcis rækkefølge og intet fokus-tyveri fra proxy',
        (tester) async {
      await pumpEditor(tester, initial: ['A', 'B', 'C']);
      await tester.tap(find.text('Tilføj trin'));
      await tester.pumpAndSettle();
      expect(editable(tester, 3).focusNode.hasFocus, isTrue);
      final h0 = tester.getRect(find.byType(TextField).at(0));
      final h1 = tester.getRect(find.byType(TextField).at(1));
      final pitch = h1.top - h0.top;
      final handle = find.byIcon(Icons.drag_indicator).first;
      final g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var k = 0; k < 10; k++) {
        await g.moveBy(Offset(0, pitch * 0.9 / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(latest, ['B', 'A', 'C', '']);
    });

    testWidgets('træk af nyligt tilføjet (autofocus) trin: fokus efter træk',
        (tester) async {
      await pumpEditor(tester, initial: ['A', 'B']);
      await tester.tap(find.text('Tilføj trin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'C');
      // Fokus flyttes til trin 1
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(editable(tester, 0).focusNode.hasFocus, isTrue);
      final h0 = tester.getRect(find.byType(TextField).at(0));
      final h1 = tester.getRect(find.byType(TextField).at(1));
      final pitch = h1.top - h0.top;
      final g = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.drag_indicator).last));
      await tester.pump(const Duration(milliseconds: 100));
      for (var k = 0; k < 10; k++) {
        await g.moveBy(Offset(0, -pitch * 0.9 / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(latest, ['A', 'C', 'B']);
      final fieldsWithFocus = [
        for (var i = 0; i < 3; i++) editable(tester, i).focusNode.hasFocus
      ];
      expect(fieldsWithFocus, [true, false, false],
          reason: 'fokus skal blive på trin 1 under/efter træk');
    });

    testWidgets('360 dp: ingen overflow med 3 lange trin', (tester) async {
      await pumpEditor(tester, initial: List.generate(3, (i) => 'ord ' * 200));
      expect(tester.takeException(), isNull);
    });
  });

  group('detalje', () {
    testWidgets('tap targets, labels og kontrast', (tester) async {
      final h = tester.ensureSemantics();
      await pumpDetail(tester, ['Hak løget', 'Steg det']);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.tap(find.text('Hak løget'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      final node = tester.getSemantics(find.byType(InkWell).first);
      expect(node.label, 'Trin 1: Hak løget');
      expect(node.value, 'udført');
      h.dispose();
    });

    testWidgets('360 dp: meget langt trin uden mellemrum giver ikke overflow',
        (tester) async {
      await pumpDetail(tester, ['x' * 1000, 'ord ' * 250]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('markering bevares ved uændrede trin, nulstilles ved ændring',
        (tester) async {
      phone(tester);
      Widget app(List<String> s) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: RecipeInstructions(steps: s)));
      await tester.pumpWidget(app(['A', 'B']));
      await tester.tap(find.text('A'));
      await tester.pump();
      // Nyt listeobjekt med samme indhold (fx anden felt-opdatering fra Firestore)
      await tester.pumpWidget(app(List.of(['A', 'B'])));
      expect(tester.widget<Text>(find.text('A')).style?.decoration,
          TextDecoration.lineThrough);
      await tester.pumpWidget(app(['A', 'B', 'C']));
      expect(tester.widget<Text>(find.text('A')).style?.decoration,
          isNot(TextDecoration.lineThrough));
    });

    testWidgets('tastatur/skærmlæser: Semantics onTap toggler', (tester) async {
      final h = tester.ensureSemantics();
      await pumpDetail(tester, ['A']);
      tester.semantics.tap(find.semantics.byLabel('Trin 1: A'));
      await tester.pump();
      expect(tester.getSemantics(find.byType(InkWell).first).value, 'udført');
      h.dispose();
    });
  });
}
