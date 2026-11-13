import 'package:flutter_test/flutter_test.dart';

import 'package:egg_empire/game/format_number.dart';

void main() {
  group('formatNumber', () {
    test('uses the suffix ladder and three significant figures', () {
      expect(formatNumber(999), '999');
      expect(formatNumber(1), '1.00');
      expect(formatNumber(0.25), '0.250');
      expect(formatNumber(9.999), '10.0');
      expect(formatNumber(13.78), '13.8');
      expect(formatNumber(118.02), '118');
      expect(formatNumber(1234), '1.23K');
      expect(formatNumber(4.387e42), '4.39Td');
    });

    test('rounds across a suffix boundary', () {
      expect(formatNumber(999.9), '1.00K');
    });

    test('uses scientific notation above the last suffix', () {
      expect(formatNumber(1e45), '1.00e+45');
    });

    test('can format all values scientifically from settings', () {
      expect(formatNumber(1234, scientific: true), '1.23e+3');
    });

    test('preserves sign and formats zero', () {
      expect(formatNumber(-1234), '-1.23K');
      expect(formatNumber(0), '0');
      expect(formatNumber(1e-30), '1.00e-30');
    });
  });
}
