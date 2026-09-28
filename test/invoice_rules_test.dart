import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// The Request for Invoice does the tariff's arithmetic (SOP-APS-002 V8).
///
/// "Where hourly rates are applicable, a minimum of one hour (R540.60) will
/// be charged. Thereafter time will be charged in half hour segments of
/// R270.30 per half hour or part thereof. The same principle will be applied
/// to overtime and Sunday time."
void main() {
  InvoiceTotals bill({
    double normal = 0,
    double overtime = 0,
    double sunday = 0,
    double km = 0,
  }) =>
      InvoiceRules.totals(
        normalHours: normal,
        overtimeHours: overtime,
        sundayHours: sunday,
        kilometres: km,
        chargeTravel: true,
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

  group('the one-hour minimum', () {
    test('half an hour in normal time bills as one hour', () {
      // 11:55 to 12:25, as on the Phone Live Test Depot form.
      expect(bill(normal: 0.5).normal, closeTo(540.60, 0.001));
      expect(bill(normal: 0.5).grand, closeTo(540.60, 0.001));
    });

    test('exactly one hour is one hour', () {
      expect(bill(normal: 1).normal, closeTo(540.60, 0.001));
    });

    test('is a floor on the visit, not on every band it touches', () {
      // 15:30 to 16:45: half an hour of normal time, three quarters of
      // overtime. Two per-band minimums would have billed R1 141.62 for a
      // 75-minute visit.
      final t = bill(normal: 0.5, overtime: 0.75);
      expect(t.normal, closeTo(0.5 * 540.60, 0.001));
      expect(t.overtime, closeTo(1.0 * 601.02, 0.001));
      expect(t.inspection, closeTo(270.30 + 601.02, 0.001));
    });

    test('a short visit entirely in overtime is topped up in overtime', () {
      final t = bill(overtime: 0.25);
      expect(t.normal, 0);
      expect(t.overtime, closeTo(601.02, 0.001));
    });

    test('a short visit that straddles 16:00 is topped up where it began',
        () {
      // 15:50 to 16:10 — twenty minutes, ten each side.
      final bands = InvoiceRules.chargeableBands(
          normal: 10 / 60, overtime: 10 / 60, sunday: 0);
      expect(bands.normal + bands.overtime, 1.0);
      expect(bands.normal, 0.5, reason: 'the half hour it started in');
      expect(bands.overtime, 0.5);
    });

    test('nothing is charged for no time', () {
      expect(bill().inspection, 0);
    });
  });

  group('half-hour segments', () {
    test('one hour and six minutes is one and a half', () {
      expect(InvoiceRules.chargeableHours(1.1), 1.5);
      expect(bill(normal: 1.1).normal, closeTo(540.60 + 270.30, 0.001));
    });

    test('two hours and one minute is two and a half', () {
      expect(bill(normal: 2 + 1 / 60).normal, closeTo(2.5 * 540.60, 0.001));
    });

    test('a Sunday is charged at the Sunday rate throughout', () {
      expect(bill(sunday: 1.5).sunday, closeTo(1.5 * 720.80, 0.001));
    });
  });

  group('the rest of the form', () {
    test('kilometres at R6.50 each, no rounding', () {
      expect(bill(km: 128).travel, closeTo(832.00, 0.001));
      expect(bill(normal: 1, km: 128).inspection, closeTo(540.60 + 832, 0.001));
    });

    test('laboratory lines add to the grand total, excluding VAT', () {
      final t = InvoiceRules.totals(
        normalHours: 1,
        overtimeHours: 0,
        sundayHours: 0,
        kilometres: 0,
        chargeTravel: true,
        pmpFatTests: 1,
        pmpProteinTests: 1,
        pmpCalciumTests: 0,
        pmpPhysicalTests: 0,
        rawFatTests: 1,
        rawProteinTests: 1,
        rawSoyaTests: 0,
        rawStarchTests: 0,
        rawDnaTests: 0,
        rawCalciumTests: 0,
      );
      expect(t.pmpLab, closeTo(875.56 + 533.18, 0.001));
      expect(t.rawLab, closeTo(875.56 + 533.18, 0.001));
      expect(t.grand, closeTo(540.60 + 2 * (875.56 + 533.18), 0.001));
    });

    test('amounts print the way the tariff prints them', () {
      expect(InvoiceRules.rand(540.6), 'R540.60');
      expect(InvoiceRules.rand(1764.9), 'R1 764.90');
      expect(InvoiceRules.rand(0), 'R0.00');
    });

    test('the split puts 08:00–16:00 in normal time and the rest overtime',
        () {
      // A Wednesday.
      final split = InvoiceRules.splitHours(
        DateTime(2026, 8, 26, 15, 30),
        DateTime(2026, 8, 26, 16, 45),
      );
      expect(split.normal, closeTo(0.5, 0.001));
      expect(split.overtime, closeTo(0.75, 0.001));
      expect(split.sunday, 0);
    });

    test('clock times read the way the form writes them', () {
      expect(InvoiceRules.hoursBetween('11:55', '12:25'), closeTo(0.5, 0.001));
      expect(InvoiceRules.hoursBetween('23:30', '00:15'), closeTo(0.75, 0.001));
      expect(InvoiceRules.hoursBetween('nine', '10:00'), isNull);
    });
  });
}
