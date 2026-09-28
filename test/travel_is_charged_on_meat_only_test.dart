import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// What the journey costs the client.
///
/// Only certain raw processed meat and processed meat work carries a
/// kilometre charge. The distance is recorded and printed on every visit —
/// the office wants to see how far the inspector drove whatever was
/// inspected — but an egg or poultry visit is not billed for it.
void main() {
  InvoiceTotals totalsFor({required bool raw, required bool pmp}) =>
      InvoiceRules.totals(
        normalHours: 2,
        overtimeHours: 0,
        sundayHours: 0,
        kilometres: 100,
        chargeTravel: InvoiceRules.travelIsChargeable(rawRmp: raw, pmp: pmp),
        pmpFatTests: 0,
        pmpProteinTests: 0,
        pmpCalciumTests: 0,
        pmpPhysicalTests: 0,
        rawFatTests: 0,
        rawProteinTests: 0,
        rawSoyaTests: 0,
        rawStarchTests: 0,
        rawDnaTests: 0,
        rawCalciumTests: 0,
      );

  test('raw processed meat is charged for the journey', () {
    expect(totalsFor(raw: true, pmp: false).travel,
        100 * InvoiceRates.perKilometre);
  });

  test('processed meat is charged for the journey', () {
    expect(totalsFor(raw: false, pmp: true).travel,
        100 * InvoiceRates.perKilometre);
  });

  test('a visit with neither is not charged for the journey', () {
    // An egg or poultry visit: the kilometres are on the form, the charge is
    // nought, and the hours still bill as they always did.
    final totals = totalsFor(raw: false, pmp: false);
    expect(totals.travel, 0);
    expect(totals.normal, 2 * InvoiceRates.normalHour);
    expect(totals.inspection, totals.normal);
  });

  test('the rule itself', () {
    expect(InvoiceRules.travelIsChargeable(rawRmp: true, pmp: true), isTrue);
    expect(InvoiceRules.travelIsChargeable(rawRmp: true, pmp: false), isTrue);
    expect(InvoiceRules.travelIsChargeable(rawRmp: false, pmp: true), isTrue);
    expect(InvoiceRules.travelIsChargeable(rawRmp: false, pmp: false), isFalse);
  });
}
