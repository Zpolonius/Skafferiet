// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/features/grocery/edit_grocery_item_dialog.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

/// Fake notifier: leverer en fast liste og registrerer kald til updateItem.
class FakeGroceryListNotifier extends GroceryListNotifier {
  final List<GroceryItem> items;
  final Object? errorToThrow;
  final List<Map<String, Object?>> updates = [];

  FakeGroceryListNotifier(this.items, {this.errorToThrow})
      : super(firestore: MockFirestore());

  @override
  Stream<List<GroceryItem>> build() => Stream.value(items);

  @override
  Future<void> updateItem(
    String id, {
    required String name,
    required String quantity,
    required String? unit,
    required String category,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    updates.add({
      'id': id,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category
    });
  }
}

GroceryItem _item({String? unit = 'stk', String category = 'Mejeri'}) =>
    GroceryItem(
      id: 'item-1',
      name: 'Mælk',
      category: category,
      quantity: '1',
      unit: unit,
      source: 'meal_plan',
      createdAt: DateTime(2026),
    );

Future<FakeGroceryListNotifier> _pumpDialog(
  WidgetTester tester,
  GroceryItem item, {
  List<GroceryItem>? listItems,
  Object? errorToThrow,
}) async {
  final notifier =
      FakeGroceryListNotifier(listItems ?? [item], errorToThrow: errorToThrow);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [groceryListProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => EditGroceryItemDialog(item: item),
              ),
              child: const Text('Åbn'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Åbn'));
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  group('EditGroceryItemDialog', () {
    testWidgets('åbner uden crash for vare med ukendt enhed (fx "fed")',
        (tester) async {
      await _pumpDialog(tester, _item(unit: 'fed'));

      expect(tester.takeException(), isNull);
      expect(find.text('Rediger vare'), findsOneWidget);
      expect(find.text('fed'), findsOneWidget);
    });

    testWidgets('åbner uden crash for vare uden enhed', (tester) async {
      await _pumpDialog(tester, _item(unit: null));

      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('åbner uden crash når varens kategori ikke findes i listen',
        (tester) async {
      // Listen indeholder ikke længere en vare i kategorien 'Kolonial'.
      await _pumpDialog(tester, _item(category: 'Kolonial'),
          listItems: const []);

      expect(tester.takeException(), isNull);
      expect(find.text('Kolonial'), findsOneWidget);
    });

    testWidgets('gemmer trimmede værdier og bevarer ukendt enhed',
        (tester) async {
      final notifier = await _pumpDialog(tester, _item(unit: 'fed'));

      await tester.enterText(find.byKey(const Key('edit_name')), '  Hvidløg  ');
      await tester.enterText(find.byKey(const Key('edit_quantity')), ' 3 ');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      expect(notifier.updates, [
        {
          'id': 'item-1',
          'name': 'Hvidløg',
          'quantity': '3',
          'unit': 'fed',
          'category': 'Mejeri'
        },
      ]);
      expect(find.text('Rediger vare'), findsNothing);
    });

    testWidgets('gemmer null som enhed når varen ingen enhed har',
        (tester) async {
      final notifier = await _pumpDialog(tester, _item(unit: null));

      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      expect(notifier.updates.single['unit'], isNull);
    });

    testWidgets('viser fejl og gemmer ikke ved tomt navn eller mængde',
        (tester) async {
      final notifier = await _pumpDialog(tester, _item());

      await tester.enterText(find.byKey(const Key('edit_name')), '   ');
      await tester.enterText(find.byKey(const Key('edit_quantity')), '');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      expect(find.text('Navn må ikke være tomt'), findsOneWidget);
      expect(find.text('Angiv en mængde'), findsOneWidget);
      expect(notifier.updates, isEmpty);
      expect(find.text('Rediger vare'), findsOneWidget);
    });

    testWidgets('bliver åben og viser besked når varen er slettet imens',
        (tester) async {
      await _pumpDialog(
        tester,
        _item(),
        errorToThrow:
            FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      );

      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Varen findes ikke længere'), findsOneWidget);
      expect(find.text('Rediger vare'), findsOneWidget);
    });

    testWidgets('viser generel fejl ved andre gemmefejl', (tester) async {
      await _pumpDialog(tester, _item(), errorToThrow: Exception('offline'));

      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      expect(find.text('Kunne ikke gemme ændringerne. Prøv igen.'),
          findsOneWidget);
    });
  });
}
