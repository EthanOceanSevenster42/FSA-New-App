import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// Where an inspection is reckoned to have begun and ended.
///
/// The handset used to offer the visit record's own creation time as the
/// start. The facility details are routinely captured well before the drive,
/// so that is the day the paperwork was begun, not the day the inspection
/// happened: of the visits signed off on 2026-10-12, one record had been
/// opened on 7 October and another on 22 September. The confirmation screen
/// offered "12:00" for an inspection worked at 11:20 that morning — a start
/// half an hour *after* the finish it showed alongside it (Ethan,
/// 2026-10-12).
///
/// The first commodity form opened is the first moment the inspector was on
/// the job; the signature is the last.
void main() {
  group('the inspection begins at the first form opened', () {
    // The record was created five days before the inspector ever drove out.
    final recordOpened = DateTime(2026, 10, 7, 12, 0);
    final firstForm = DateTime(2026, 10, 12, 11, 20);
    final secondForm = DateTime(2026, 10, 12, 11, 48);
    final signed = DateTime(2026, 10, 12, 12, 10);

    test('not at the day the facility details were filled in', () {
      final w = InvoiceRules.workedWindow(
        captures: [firstForm],
        visitStarted: recordOpened,
        signedAt: signed,
      );
      expect(w.start, firstForm);
      expect(w.end, signed);
    });

    test('the earliest form wins, whatever order they come back in', () {
      for (final order in [
        [firstForm, secondForm],
        [secondForm, firstForm],
      ]) {
        final w = InvoiceRules.workedWindow(
          captures: order,
          visitStarted: recordOpened,
          signedAt: signed,
        );
        expect(w.start, firstForm, reason: 'order $order');
      }
    });

    test('a form still being filled in counts, done or not', () {
      // inspectedAt is set when the form is opened, so a draft carries one.
      final w = InvoiceRules.workedWindow(
        captures: [null, secondForm, null, firstForm],
        visitStarted: recordOpened,
        signedAt: signed,
      );
      expect(w.start, firstForm);
    });

    test('an occurrence report has no form, so the record is all there is',
        () {
      final w = InvoiceRules.workedWindow(
        captures: const [],
        visitStarted: recordOpened,
        signedAt: signed,
      );
      expect(w.start, recordOpened);
      expect(w.end, signed);
    });
  });

  group('the inspection ends at the signature', () {
    final form = DateTime(2026, 10, 12, 11, 20);

    test('the finish is the moment of signing, not the record closing', () {
      final signed = DateTime(2026, 10, 12, 12, 10);
      final w = InvoiceRules.workedWindow(
        captures: [form],
        visitStarted: DateTime(2026, 10, 7, 12, 0),
        signedAt: signed,
      );
      expect(w.end, signed);
      expect(w.end.isAfter(w.start), isTrue);
    });

    test('a finish is never offered before the start it is shown beside', () {
      // The defect as it appeared on the tablet: started 12:00, ended 11:30.
      final w = InvoiceRules.workedWindow(
        captures: [form],
        visitStarted: DateTime(2026, 10, 7, 12, 0),
        signedAt: DateTime(2026, 10, 12, 11, 0),
      );
      expect(w.end.isBefore(w.start), isFalse);
    });
  });

  group('what the office is then billed', () {
    test('a fifty-minute inspection bills the one-hour minimum', () {
      final w = InvoiceRules.workedWindow(
        captures: [DateTime(2026, 10, 12, 11, 20)],
        visitStarted: DateTime(2026, 9, 22, 11, 28),
        signedAt: DateTime(2026, 10, 12, 12, 10),
      );
      final measured = InvoiceRules.splitHours(w.start, w.end);
      final bands = InvoiceRules.chargeableBands(
        normal: measured.normal,
        overtime: measured.overtime,
        sunday: measured.sunday,
      );
      expect(bands.normal + bands.overtime + bands.sunday, 1.0);
    });

    test('the twenty-day-old record no longer bills twenty days', () {
      // Shamika Supermarket 2: record opened 22 September, signed off
      // 12 October, and the office was invoiced 23 hours.
      final w = InvoiceRules.workedWindow(
        captures: [DateTime(2026, 10, 12, 10, 55)],
        visitStarted: DateTime(2026, 9, 22, 11, 28),
        signedAt: DateTime(2026, 10, 12, 11, 22),
      );
      expect(w.end.difference(w.start), const Duration(minutes: 27));
      final measured = InvoiceRules.splitHours(w.start, w.end);
      final bands = InvoiceRules.chargeableBands(
        normal: measured.normal,
        overtime: measured.overtime,
        sunday: measured.sunday,
      );
      expect(bands.normal + bands.overtime + bands.sunday, 1.0);
    });
  });
}
