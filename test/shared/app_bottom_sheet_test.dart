import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/shared/widgets/app_bottom_sheet.dart';

void main() {
  test('ingen kalder showModalBottomSheet direkte – brug showAppBottomSheet', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('app_bottom_sheet.dart'))
        .where((f) => RegExp(r'showModalBottomSheet\s*[<(]').hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason: 'Disse filer åbner sheets uden safe area / over bundmenuen. '
            'Brug showAppBottomSheet fra lib/shared/widgets/app_bottom_sheet.dart.');
  });

  testWidgets('sheet fra en fane holder sig under statuslinjen og dækker bundmenuen', (tester) async {
    // Telefon med kamera-hak (50 dp) og hjem-streg (34 dp).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 150, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 150, bottom: 102);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBar(destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'A'),
          NavigationDestination(icon: Icon(Icons.list), label: 'B'),
        ]),
        // Indlejret navigator ligesom en fane i StatefulShellRoute.
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAppBottomSheet(
                    context: ctx,
                    // Et sheet der beder om al pladsen det kan få.
                    builder: (sheetCtx) => Container(
                      key: const Key('sheet'),
                      height: 5000,
                      color: Colors.white,
                      alignment: Alignment.bottomCenter,
                      padding: EdgeInsets.only(bottom: sheetBottomInset(sheetCtx)),
                      child: const Text('Gem'),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byKey(const Key('sheet')));
    expect(sheet.top, greaterThanOrEqualTo(50), reason: 'må ikke gå op under statuslinjen');
    expect(sheet.bottom, 844, reason: 'skal dække bundmenuen helt ned til kanten');
    expect(tester.getBottomLeft(find.text('Gem')).dy, lessThanOrEqualTo(844 - 34),
        reason: 'knappen skal stå over hjem-stregen');
  });
}
