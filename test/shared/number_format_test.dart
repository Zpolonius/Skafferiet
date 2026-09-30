import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/shared/utils/number_format.dart';

void main() {
  group('parseDanishNumber', () {
    test('accepterer komma og punktum', () {
      expect(parseDanishNumber('1,5'), 1.5);
      expect(parseDanishNumber('1.5'), 1.5);
      expect(parseDanishNumber(' 400 '), 400);
    });

    test('afviser tom, ugyldig og negativ input', () {
      expect(parseDanishNumber(''), isNull);
      expect(parseDanishNumber('abc'), isNull);
      expect(parseDanishNumber('-2'), isNull);
      expect(parseDanishNumber('1,2,3'), isNull);
    });
  });

  group('formatDanishNumber', () {
    test('fjerner overflødige decimaler og bruger komma', () {
      expect(formatDanishNumber(400), '400');
      expect(formatDanishNumber(1.5), '1,5');
      expect(formatDanishNumber(12.34), '12,3');
      expect(formatDanishNumber(0.25, maxDecimals: 2), '0,25');
      expect(formatDanishNumber(2.0, maxDecimals: 2), '2');
    });
  });
}
