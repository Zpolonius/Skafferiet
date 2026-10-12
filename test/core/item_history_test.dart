import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/item_history.dart';

ItemHistoryEntry _e(String name,
        {int useCount = 1, DateTime? lastUsed, String category = 'Andet'}) =>
    ItemHistoryEntry(
      key: itemHistoryKey(name)!,
      name: name,
      category: category,
      useCount: useCount,
      lastUsed: lastUsed ?? DateTime(2026, 1, 1),
    );

void main() {
  group('itemHistoryKey', () {
    test('små bogstaver, trimmet og enkelt mellemrum', () {
      expect(itemHistoryKey('  Hakket   Oksekød '), 'hakket oksekød');
      expect(itemHistoryKey('Æbler'), 'æbler');
      expect(itemHistoryKey('ØL'), 'øl');
      expect(itemHistoryKey('Å'), 'å');
      expect(itemHistoryKey('a\tb\nc'), 'a b c');
    });

    test('tomt navn giver ingen nøgle', () {
      expect(itemHistoryKey(''), isNull);
      expect(itemHistoryKey('   \n'), isNull);
    });

    test('nøglen er et gyldigt Firestore-dokument-id', () {
      for (final raw in ['1/2 l mælk', 'a//b', '.', '..', '__x__', '__', '/']) {
        final key = itemHistoryKey(raw);
        expect(key, isNotNull, reason: raw);
        expect(key!.contains('/'), isFalse, reason: raw);
        expect(key, isNot('.'), reason: raw);
        expect(key, isNot('..'), reason: raw);
        expect(RegExp(r'^__.*__$').hasMatch(key), isFalse, reason: raw);
      }
    });

    test('forskellige navne giver forskellige nøgler', () {
      expect(itemHistoryKey('1/2 l mælk'), isNot(itemHistoryKey('1-2 l mælk')));
      expect(itemHistoryKey('.'), isNot(itemHistoryKey('..')));
    });
  });

  group('suggestItems', () {
    final all = [
      _e('Hakket oksekød', useCount: 3),
      _e('Æbler', useCount: 2),
      _e('Mælk', useCount: 9),
      _e('Letmælk', useCount: 1),
      _e('Øko mælk', useCount: 4),
    ];

    List<String> names(String q, [List<ItemHistoryEntry>? from]) =>
        suggestItems(from ?? all, q).map((e) => e.name).toList();

    test('matcher på starten af ord, ikke midt i ord', () {
      expect(names('hak'), ['Hakket oksekød']);
      expect(names('oks'), ['Hakket oksekød']);
      expect(names('ket'), isEmpty);
    });

    test('flere ord i søgningen matcher fra et ords start', () {
      expect(names('hakket ok'), ['Hakket oksekød']);
      expect(names('oksekød'), ['Hakket oksekød']);
      expect(names('hak oks'), isEmpty);
    });

    test('ufølsom over for store/små bogstaver, også æ/ø/å', () {
      expect(names('æb'), ['Æbler']);
      expect(names('ÆB'), ['Æbler']);
      expect(names('øk'), ['Øko mælk']);
      expect(names('HAK'), ['Hakket oksekød']);
    });

    test('sorteret efter useCount og derefter lastUsed', () {
      expect(names('m'), ['Mælk', 'Øko mælk']);
      final tie = [
        _e('Mel', useCount: 2, lastUsed: DateTime(2026, 1, 1)),
        _e('Mælk', useCount: 2, lastUsed: DateTime(2026, 3, 1)),
        _e('Margarine', useCount: 2, lastUsed: DateTime(2026, 2, 1)),
      ];
      expect(names('m', tie), ['Mælk', 'Margarine', 'Mel']);
    });

    test('højst 5 forslag', () {
      final many = [for (var i = 0; i < 12; i++) _e('Mad $i', useCount: i)];
      final result = suggestItems(many, 'ma');
      expect(result, hasLength(5));
      expect(result.first.name, 'Mad 11');
    });

    test('tom søgning giver ingen forslag', () {
      expect(names(''), isEmpty);
      expect(names('   '), isEmpty);
    });

    test('et forslag der er identisk med det skrevne vises ikke', () {
      expect(names('mælk'), ['Øko mælk']);
      expect(names('Mælk '), ['Øko mælk']);
    });
  });

  group('customCategories', () {
    test('kun kategorier der ikke er standard, unikke og sorteret', () {
      final entries = [
        _e('A', category: 'Kød'),
        _e('B', category: 'Krydderier'),
        _e('C', category: 'Krydderier'),
        _e('D', category: 'Baby'),
      ];
      expect(customCategoriesFrom(entries, const ['Kød', 'Andet']),
          ['Baby', 'Krydderier']);
    });
  });

  group('ItemHistoryEntry.fromMap', () {
    test('læser felterne og tåler manglende værdier', () {
      final e = ItemHistoryEntry.fromMap('hakket oksekød', {
        'name': 'Hakket oksekød',
        'category': 'Kød',
        'unit': 'g',
        'quantity': '500',
        'useCount': 3,
      });
      expect(e!.name, 'Hakket oksekød');
      expect(e.unit, 'g');
      expect(e.useCount, 3);
      expect(ItemHistoryEntry.fromMap('x', {'category': 'Kød'}), isNull);
    });
  });
}
