import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// The Request for Invoice works its own sums: every row is its count times
/// its rate, and the totals are those rows added up (Ethan, 2026-09-29).
void main() {
  setUp(() => InvoiceRates.use(InvoiceRates.defaults));

  InvoiceTotals totals({bool chargeTravel = true, int rawSoya = 0}) =>
      InvoiceRules.totals(
        normalHours: 2.2,
        overtimeHours: 0,
        sundayHours: 0,
        kilometres: 40,
        chargeTravel: chargeTravel,
        pmpFatTests: 2,
        pmpProteinTests: 1,
        pmpCalciumTests: 0,
        pmpPhysicalTests: 0,
        rawFatTests: 0,
        rawProteinTests: 0,
        rawSoyaTests: rawSoya,
        rawStarchTests: 0,
        rawDnaTests: 1,
        rawCalciumTests: 0,
      );

  test('time is charged in half hours at the hourly rate', () {
    // 2.2 hours is charged as 2.5 hours at R540.60.
    expect(totals().normal, closeTo(2.5 * 540.60, 0.001));
    expect(totals().overtime, 0);
  });

  test('travel is kilometres times the rate, where it is charged', () {
    expect(totals().travel, closeTo(40 * 6.50, 0.001));
    expect(totals(chargeTravel: false).travel, 0);
  });

  test('each laboratory total is its tests times their fees', () {
    expect(totals().pmpLab, closeTo(2 * 875.56 + 533.18, 0.001));
    expect(totals().rawLab, closeTo(2761.30, 0.001));
    expect(totals(rawSoya: 3).rawLab, closeTo(2761.30 + 3 * 1764.90, 0.001));
  });

  test('the invoice total is the inspection and both laboratory totals', () {
    final t = totals();
    expect(t.inspection, closeTo(t.normal + t.overtime + t.sunday + t.travel, 0.001));
    expect(t.grand, closeTo(t.inspection + t.pmpLab + t.rawLab, 0.001));
    expect(t.grand, closeTo(1351.50 + 260.00 + 2284.30 + 2761.30, 0.001));
  });
}
