import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// What the RFI *sends* must match what it *prints*.
///
/// `InvoiceRules.chargeableBands` has always rounded the hours for the
/// printed form — a minimum of one hour, then half-hour segments, as the
/// tariff says. The record kept the raw clock reading instead, and that raw
/// value was what travelled to APS: the inspector's own RFI said one hour
/// while the office received 0.48, and every invoice line had to be
/// corrected by hand (Ethan, 2026-10-12).
///
/// The measured time is not lost — the form still prints the real start and
/// finish, and those now travel alongside the billed figure.
void main() {
  group('hours as the tariff charges them', () {
    test('anything up to the minimum bills the minimum', () {
      for (final measured in [0.03, 0.3, 0.48, 0.78, 0.8, 0.99, 1.0]) {
        expect(InvoiceRules.chargeableHours(measured),
            InvoiceRates.minimumChargeableHours,
            reason: '$measured should bill the one-hour minimum');
      }
    });

    test('nothing worked bills nothing', () {
      expect(InvoiceRules.chargeableHours(0), 0);
    });

    test('above the minimum it goes up in half hours, never minutes', () {
      expect(InvoiceRules.chargeableHours(1.1), 1.5);
      expect(InvoiceRules.chargeableHours(1.5), 1.5);
      expect(InvoiceRules.chargeableHours(1.6), 2.0);
      expect(InvoiceRules.chargeableHours(2.4), 2.5);
    });
  });

  group('the times the inspector confirmed', () {
    final day = DateTime(2026, 10, 12, 7, 0);

    test('are used when given, in place of the handset reading', () {
      final w = InvoiceRules.confirmedWindow('09:15', '10:30', on: day);
      expect(w, isNotNull);
      expect(w!.start, DateTime(2026, 10, 12, 9, 15));
      expect(w.end, DateTime(2026, 10, 12, 10, 30));
      expect(w.billable, isTrue);
    });

    test('are ignored when the inspector was never asked', () {
      expect(InvoiceRules.confirmedWindow('', '', on: day), isNull);
      expect(InvoiceRules.confirmedWindow('09:00', '', on: day), isNull);
      expect(InvoiceRules.confirmedWindow('rubbish', '10:00', on: day), isNull);
    });

    test('a finish before the start is read as running past midnight', () {
      final w = InvoiceRules.confirmedWindow('23:30', '00:30', on: day);
      expect(w!.end.difference(w.start), const Duration(hours: 1));
    });

    test('a confirmed twenty minutes still bills the one-hour minimum', () {
      final w = InvoiceRules.confirmedWindow('09:00', '09:20', on: day)!;
      final measured = InvoiceRules.splitHours(w.start, w.end);
      final bands = InvoiceRules.chargeableBands(
          normal: measured.normal,
          overtime: measured.overtime,
          sunday: measured.sunday);
      expect(bands.normal + bands.overtime + bands.sunday, 1.0);
    });
  });

  group('what the form sends', () {
    // A Wednesday.
    DateTime at(int h, int m) => DateTime(2026, 10, 7, h, m);

    ({double normal, double overtime, double sunday}) sent(
        DateTime start, DateTime end) {
      final measured = InvoiceRules.splitHours(start, end);
      return InvoiceRules.chargeableBands(
        normal: measured.normal,
        overtime: measured.overtime,
        sunday: measured.sunday,
      );
    }

    test('a twenty-minute visit sends one hour, not 0.33', () {
      final bands = sent(at(9, 0), at(9, 20));
      expect(bands.normal, 1.0);
      expect(bands.overtime, 0.0);
    });

    test('the handset readings that reached APS as fractions', () {
      // 0.03 h is the 2 minutes a record was open at SPAR - Wilck; 0.48 h
      // the 29 minutes at Roots Butchery. Both must send a full hour.
      for (final minutes in [2, 8, 18, 29, 47]) {
        final bands = sent(at(10, 0), at(10, 0).add(Duration(minutes: minutes)));
        final total = bands.normal + bands.overtime + bands.sunday;
        expect(total, 1.0, reason: '$minutes minutes should send one hour');
      }
    });

    test('every band sent is a whole or half hour, never minutes', () {
      for (var startHour = 6; startHour < 20; startHour++) {
        for (final mins in [2, 29, 47, 95, 140, 200]) {
          final bands =
              sent(at(startHour, 0), at(startHour, 0).add(Duration(minutes: mins)));
          for (final band in [bands.normal, bands.overtime, bands.sunday]) {
            expect((band * 2) % 1, 0,
                reason: '$startHour:00 for $mins min sent $band');
          }
        }
      }
    });

    test('a visit never sends less than the minimum', () {
      for (final mins in [1, 5, 15, 30, 59]) {
        final bands =
            sent(at(11, 0), at(11, 0).add(Duration(minutes: mins)));
        expect(bands.normal + bands.overtime + bands.sunday,
            greaterThanOrEqualTo(InvoiceRates.minimumChargeableHours));
      }
    });

    test('a Sunday visit sends Sunday hours', () {
      final sunday = DateTime(2026, 10, 11, 9, 0);
      final measured = InvoiceRules.splitHours(
          sunday, sunday.add(const Duration(minutes: 20)));
      final bands = InvoiceRules.chargeableBands(
          normal: measured.normal,
          overtime: measured.overtime,
          sunday: measured.sunday);
      expect(bands.sunday, 1.0);
      expect(bands.normal, 0.0);
    });
  });
}
