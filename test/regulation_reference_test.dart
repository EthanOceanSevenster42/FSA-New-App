import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/regulation_reference.dart';

void main() {
  test('placeholder references are dropped', () {
    for (final placeholder in [
      'XXXX',
      'XXX',
      'x',
      ' XX ',
      '[XXX]',
      '[Reg. XX]',
      'Reg XX',
      '(xx.x)',
    ]) {
      expect(cleanRegulation(placeholder), '', reason: placeholder);
    }
  });

  test('real references are kept', () {
    for (final real in [
      '[Reg. 12]',
      '[Reg. 8 (2)-(5)]',
      'Reg. 7',
      'Annexure X',
      'Section 8',
    ]) {
      expect(cleanRegulation(real), real, reason: real);
    }
    expect(cleanRegulation(''), '');
  });
}
