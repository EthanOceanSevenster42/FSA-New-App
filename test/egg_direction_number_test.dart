import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// The rejection number follows the original app's rule exactly.
void main() {
  test('client, inspector, date and a three-digit sequence', () {
    expect(
      EggDirectionNumber.generate(
        clientId: 4821,
        inspectorId: 7,
        on: DateTime(2026, 8, 27, 13, 5),
        issuedTodayBefore: 0,
      ),
      '4821-7-20260827-001',
    );
  });

  test('the sequence is the count already issued today, plus one', () {
    expect(
      EggDirectionNumber.generate(
        clientId: 1, inspectorId: 33, on: DateTime(2026, 1, 9), issuedTodayBefore: 11),
      '1-33-20260109-012',
    );
  });

  test('month and day are zero-padded, the sequence to three digits', () {
    final n = EggDirectionNumber.generate(
        clientId: 12, inspectorId: 3, on: DateTime(2026, 3, 4), issuedTodayBefore: 999);
    expect(n, '12-3-20260304-1000', reason: 'past 999 it simply grows');
    expect(
      EggDirectionNumber.generate(
          clientId: 12, inspectorId: 3, on: DateTime(2026, 3, 4), issuedTodayBefore: 4),
      '12-3-20260304-005',
    );
  });
}
