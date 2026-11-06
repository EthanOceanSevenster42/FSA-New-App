import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// The RFI's clock starts when the inspector arrived, not when the visit
/// was opened on the handset (Ethan, 2026-10-09): "There is a discrepancy
/// between the actual start time of the inspection and the time indicated
/// on the RFI."
void main() {
  // Opened in the car at 07:40; the driving ended at 09:15.
  final opened = DateTime(2026, 10, 9, 7, 40);

  group('arrival', () {
    test('is the time the travelling ended, on the day of the visit', () {
      expect(InvoiceRules.arrivedAt(opened, '09:15'),
          DateTime(2026, 10, 9, 9, 15));
    });

    test('reads the forms that write a time without a colon', () {
      expect(InvoiceRules.arrivedAt(opened, '0915'),
          DateTime(2026, 10, 9, 9, 15));
      expect(InvoiceRules.arrivedAt(opened, ' 9.15 '),
          DateTime(2026, 10, 9, 9, 15));
    });

    test('is unknown when nothing was captured, so nothing changes', () {
      expect(InvoiceRules.arrivedAt(opened, ''), isNull);
      expect(InvoiceRules.arrivedAt(opened, 'on arrival'), isNull);
      expect(InvoiceRules.arrivedAt(opened, '25:00'), isNull);
    });
  });

  group('the charged window', () {
    ({DateTime start, DateTime end, bool billable}) windowFrom(DateTime from) =>
        InvoiceRules.chargeableWindow(
          members: [
            (kind: 'rawrmp', inspectedAt: DateTime(2026, 10, 9, 9, 30)),
          ],
          visitStarted: from,
          visitEnded: DateTime(2026, 10, 9, 10, 30),
        );

    test('starts at the arrival, not at the hour spent driving to it', () {
      final driving = windowFrom(opened);
      expect(InvoiceRules.clock(driving.start), '07:40',
          reason: 'what the office was shown, and complained about');

      final arrived =
          windowFrom(InvoiceRules.arrivedAt(opened, '09:15')!);
      expect(InvoiceRules.clock(arrived.start), '09:15');
    });

    test('bills the time on site, not the travelling as well', () {
      final driving = windowFrom(opened);
      final arrived = windowFrom(InvoiceRules.arrivedAt(opened, '09:15')!);
      expect(arrived.end.difference(arrived.start),
          lessThan(driving.end.difference(driving.start)),
          reason: 'the 95 minutes of driving is no longer charged for');
      expect(arrived.end.difference(arrived.start),
          const Duration(hours: 1, minutes: 15),
          reason: 'on site 09:15 to 10:30; the 95 minutes before arrival '
              'were driving, and are not the Agency attending');
    });
  });
}
