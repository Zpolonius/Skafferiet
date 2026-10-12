import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/item_history.dart';
import 'package:skafferiet/core/models/quick_add.dart';

ItemHistoryEntry _h(String name, String category,
        {String? unit, String? quantity}) =>
    ItemHistoryEntry(
      key: itemHistoryKey(name)!,
      name: name,
      category: category,
      unit: unit,
      quantity: quantity,
    );

void main() {
  group('parseQuickAdd', () {
    test('mængde, enhed og navn', () {
      final p = parseQuickAdd('2 l mælk');
      expect((p.name, p.quantity, p.unit), ('mælk', '2', 'l'));
    });

    test('kun navn', () {
      final p = parseQuickAdd('mælk');
      expect((p.name, p.quantity, p.unit), ('mælk', null, null));
    });

    test('enhed skrevet sammen med tallet', () {
      final p = parseQuickAdd('500g ost');
      expect((p.name, p.quantity, p.unit), ('ost', '500', 'g'));
    });

    test('decimaltal med komma og punktum giver dansk komma', () {
      expect(parseQuickAdd('1,5 kg kartofler').quantity, '1,5');
      expect(parseQuickAdd('1.5 kg kartofler').quantity, '1,5');
      expect(parseQuickAdd('1,50 kg kartofler').quantity, '1,5');
      expect(parseQuickAdd('1,5 kg kartofler').unit, 'kg');
      expect(parseQuickAdd('1,5 kg kartofler').name, 'kartofler');
    });

    test('tal uden enhed giver mængde og ingen enhed', () {
      final p = parseQuickAdd('2 mælk');
      expect((p.name, p.quantity, p.unit), ('mælk', '2', null));
    });

    test('enheder genkendes uanset store/små bogstaver og slutpunktum', () {
      final p = parseQuickAdd('2 L Mælk');
      expect((p.name, p.quantity, p.unit), ('Mælk', '2', 'l'));
      final q = parseQuickAdd('3 STK. æg');
      expect((q.name, q.quantity, q.unit), ('æg', '3', 'stk'));
    });

    test('flerordsnavn og ekstra mellemrum', () {
      final p = parseQuickAdd('  500   g  hakket   oksekød ');
      expect((p.name, p.quantity, p.unit), ('hakket oksekød', '500', 'g'));
    });

    test('et tal alene, en enhed alene eller tal + enhed mister ikke navnet',
        () {
      for (final input in ['2', 'l', '2 l', '500g', 'kg']) {
        final p = parseQuickAdd(input);
        expect((p.name, p.quantity, p.unit), (input, null, null),
            reason: input);
      }
    });

    test('tal klistret til et ikke-enhedsord er en del af navnet', () {
      final p = parseQuickAdd('7up');
      expect((p.name, p.quantity, p.unit), ('7up', null, null));
      final q = parseQuickAdd('2mælk');
      expect((q.name, q.quantity, q.unit), ('2mælk', null, null));
    });

    test('0 og urimeligt lange tal er ikke en mængde', () {
      expect(parseQuickAdd('0 mælk').quantity, isNull);
      expect(parseQuickAdd('0 mælk').name, '0 mælk');
      expect(parseQuickAdd('12345678901 mælk').quantity, isNull);
    });

    test('dl, cl, ds, bdt og fl genkendes som enheder', () {
      for (final u in ['dl', 'cl', 'ds', 'bdt', 'fl']) {
        final p = parseQuickAdd('2 $u fløde');
        expect((p.name, p.quantity, p.unit), ('fløde', '2', u), reason: u);
      }
      final q = parseQuickAdd('2DL Fløde');
      expect((q.name, q.quantity, q.unit), ('Fløde', '2', 'dl'));
    });

    test('x/× mellem antal og navn er bare antal', () {
      for (final input in ['2 x mælk', '2x mælk', '2 × mælk']) {
        final p = parseQuickAdd(input);
        expect((p.name, p.quantity, p.unit), ('mælk', '2', null),
            reason: input);
      }
      // Uden navn efter x er hele teksten navnet.
      expect(parseQuickAdd('2 x').name, isNotEmpty);
    });

    test('tusindtalspunktum: 1.000 g er 1000 g, men 1.5 er stadig 1,5', () {
      final p = parseQuickAdd('1.000 g mel');
      expect((p.name, p.quantity, p.unit), ('mel', '1000', 'g'));
      expect(parseQuickAdd('12.500 g mel').quantity, '12500');
      expect(parseQuickAdd('1.5 kg mel').quantity, '1,5');
      expect(parseQuickAdd('0.500 kg mel').quantity, '0,5');
    });

    test('tomt og kun mellemrum giver tomt navn', () {
      expect(parseQuickAdd('').name, '');
      expect(parseQuickAdd('   ').name, '');
    });

    test('bevarer det brugeren skrev (store/små bogstaver i navnet)', () {
      expect(parseQuickAdd('2 l Letmælk').name, 'Letmælk');
      expect(parseQuickAdd('iPhone-oplader').name, 'iPhone-oplader');
    });
  });

  group('canonicalItemName', () {
    test('nyt navn får stort begyndelsesbogstav, kendt navn historikkens', () {
      expect(canonicalItemName('  rugbrød ', const []), 'Rugbrød');
      expect(canonicalItemName('smør', [_h('SMØR', 'Mejeri')]), 'SMØR');
      expect(canonicalItemName('Æg', const []), 'Æg');
    });
  });

  group('resolveQuickAdd', () {
    test('known afspejler om varen findes i historikken', () {
      expect(resolveQuickAdd('brød', const [])!.known, isFalse);
      expect(resolveQuickAdd('smør', [_h('Smør', 'Mejeri')])!.known, isTrue);
    });

    test('uden historik: Andet, 1 stk og stort begyndelsesbogstav', () {
      final r = resolveQuickAdd('brød', const [])!;
      expect(r.name, 'Brød');
      expect(r.category, 'Andet');
      expect(r.quantity, '1');
      expect(r.unit, 'stk');
    });

    test('tomt eller kun mellemrum giver null', () {
      expect(resolveQuickAdd('', const []), isNull);
      expect(resolveQuickAdd('   ', const []), isNull);
    });

    test('historik giver stavemåde, kategori, enhed og mængde', () {
      final r = resolveQuickAdd(
        'hakket OKSEKØD',
        [_h('Hakket oksekød', 'Kød', unit: 'g', quantity: '500')],
      )!;
      expect(r.name, 'Hakket oksekød');
      expect(r.category, 'Kød');
      expect(r.unit, 'g');
      expect(r.quantity, '500');
    });

    test('det brugeren skrev af mængde og enhed vinder over historikken', () {
      final r = resolveQuickAdd(
        '2 l mælk',
        [_h('Mælk', 'Mejeri', unit: 'pk', quantity: '1')],
      )!;
      expect((r.name, r.category, r.quantity, r.unit),
          ('Mælk', 'Mejeri', '2', 'l'));
    });

    test('kun mængde skrevet: enheden kommer fra historikken', () {
      final r = resolveQuickAdd(
        '3 mælk',
        [_h('Mælk', 'Mejeri', unit: 'l', quantity: '1')],
      )!;
      expect((r.quantity, r.unit), ('3', 'l'));
    });

    test('historik uden enhed/mængde falder tilbage til 1 stk', () {
      final r = resolveQuickAdd('smør', [_h('Smør', 'Mejeri')])!;
      expect((r.category, r.quantity, r.unit), ('Mejeri', '1', 'stk'));
    });

    test('navnet afkortes ikke stille: for langt navn giver null', () {
      expect(resolveQuickAdd('a' * 81, const []), isNull);
    });
  });
}
