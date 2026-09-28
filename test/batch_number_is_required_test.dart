import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/batch_number.dart';

/// Batch Number is required on every commodity (Ethan, 2026-09-24): a pack
/// with none is written N/A, not left blank.
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

  test('anything else is not a batch', () {
    expect(BatchNumber.missing('abc'), isNotNull);
  });
}
