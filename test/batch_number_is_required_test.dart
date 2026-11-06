import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/batch_number.dart';

/// Batch Number is required on every commodity (Ethan, 2026-09-24): a pack
/// with none is written N/A, not left blank. Whatever the pack carries is a
/// batch (Ethan, 2026-10-02) — the forms used to accept digits only.
void main() {
  test('a blank box is refused, and stays blank rather than turning N/A', () {
    expect(BatchNumber.missing(''), contains('required'));
    expect(BatchNumber.missing('   '), contains('required'));
    expect(BatchNumber.tidy(''), '');
  });

  test('a number, or N/A written out, is accepted', () {
    expect(BatchNumber.missing('12345'), isNull);
    expect(BatchNumber.missing('N/A'), isNull);
    expect(BatchNumber.tidy('none'), BatchNumber.none);
    expect(BatchNumber.tidy('na'), BatchNumber.none);
  });

  test('any code the pack carries is a batch', () {
    for (final code in [
      'abc',
      'LOT-A12',
      'B/2024-09 x',
      'ABC 123',
      '240930',
      '24-09/30',
      '#7',
      'Lote Ñ-3',
    ]) {
      expect(BatchNumber.valid(code), isTrue, reason: code);
      expect(BatchNumber.missing(code), isNull, reason: code);
      expect(BatchNumber.forRecord(code), code, reason: 'kept as typed');
      expect(BatchNumber.tidy(code), code, reason: 'not tidied away');
    }
  });
}
