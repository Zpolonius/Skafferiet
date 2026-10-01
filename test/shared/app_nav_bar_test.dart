import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/shared/widgets/app_nav_bar.dart';

const _a = AppNavDestination(
    icon: Icons.calendar_today_outlined,
    activeIcon: Icons.calendar_today,
    label: 'Madplan',
    branchIndex: 0);
const _b = AppNavDestination(
    icon: Icons.shopping_basket_outlined,
    activeIcon: Icons.shopping_basket,
    label: 'Indkøb',
    branchIndex: 1);
const _home = AppNavDestination(
    icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Hjem', branchIndex: 2);
const _c = AppNavDestination(
    icon: Icons.restaurant_menu_outlined,
    activeIcon: Icons.restaurant_menu,
    label: 'Opskrifter',
    branchIndex: 3);
const _d = AppNavDestination(
    icon: Icons.push_pin_outlined,
    activeIcon: Icons.push_pin,
    label: 'Tavle',
    semanticLabel: 'Opslagstavle',
    branchIndex: 4);

void main() {
  Future<List<int>> pumpBar(WidgetTester tester, {int current = 2, double textScale = 1}) async {
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: AppNavBar(
          leading: const [_a, _b],
          center: _home,
          trailing: const [_c, _d],
          currentIndex: current,
          onSelect: selected.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return selected;
  }

  testWidgets('alle fem faner kan findes via deres navn', (tester) async {
    await pumpBar(tester);
    for (final label in ['Madplan', 'Indkøb', 'Hjem', 'Opskrifter', 'Opslagstavle']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('fanerne viser korte tekster under ikonerne', (tester) async {
    await pumpBar(tester);
    for (final label in ['Madplan', 'Indkøb', 'Hjem', 'Opskrifter', 'Tavle']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('teksten under midterknappen skifter også til Hjem', (tester) async {
    final selected = await pumpBar(tester, current: 0);
    await tester.tap(find.text('Hjem'));
    expect(selected, [2]);
  });

  testWidgets('stor systemskrift sprænger ikke baren (smal telefon)', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpBar(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    // Hele ordet står inden for sin fane i stedet for at blive klippet.
    final label = tester.getRect(find.text('Opskrifter'));
    final tab = tester.getRect(
      find.ancestor(of: find.text('Opskrifter'), matching: find.byType(InkResponse)).first,
    );
    expect(label.left, greaterThanOrEqualTo(tab.left));
    expect(label.right, lessThanOrEqualTo(tab.right));
  });

  testWidgets('tryk sender grenens indeks', (tester) async {
    final selected = await pumpBar(tester);
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.tap(find.byIcon(Icons.shopping_basket_outlined));
    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.tap(find.byIcon(Icons.restaurant_menu_outlined));
    await tester.tap(find.byIcon(Icons.push_pin_outlined));
    expect(selected, [0, 1, 2, 3, 4]);
  });

  testWidgets('aktiv fane vises med udfyldt ikon og markeres som valgt', (tester) async {
    await pumpBar(tester, current: 4);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget, reason: 'Hjem er ikke aktiv');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Opslagstavle')),
      matchesSemantics(
          label: 'Opslagstavle',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true),
    );
  });

  testWidgets('midterknappen rager op over baren', (tester) async {
    await pumpBar(tester);
    final center = tester.getRect(find.byIcon(Icons.home_rounded));
    final tab = tester.getRect(find.byIcon(Icons.calendar_today_outlined));
    expect(center.center.dy, lessThan(tab.center.dy - 10));
  });

  testWidgets('faner har tryk-områder på mindst 48x48', (tester) async {
    await pumpBar(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
