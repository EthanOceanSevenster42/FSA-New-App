// Exercises the Request for Invoice arithmetic against the published tariff
// (SOP-APS-002 V8), so the money on a signed form can be checked without a
// device. Run with: dart run tool/check_invoice_pricing.dart
import '../lib/features/invoicing/domain/invoice_rules.dart';

int _failures = 0;

/// Money is checked as the form prints it. A binary double carries dust —
/// 1.5 x 540.60 lands on 810.9000000000001 — which never reaches the page,
/// so comparing raw doubles would fail on arithmetic that is in fact exact
/// to the cent.
void money(String what, double got, String want) =>
    check(what, InvoiceRules.rand(got), want);

void check(String what, Object? got, Object? want) {
  final ok = got.toString() == want.toString();
  if (!ok) _failures++;
  print('${ok ? "  ok  " : "  FAIL"}  $what\n'
      '${ok ? "" : "        got $got, want $want\n"}');
}

void main() {
  print('\n=== Hours: minimum one hour, then half hours or part thereof ===');
  check('30 minutes bills 1 h', InvoiceRules.chargeableHours(0.5), 1.0);
  check('exactly 1 h bills 1 h', InvoiceRules.chargeableHours(1.0), 1.0);
  // Gladys and Cinga's case: 10:20 to 11:21.
  final reported = const Duration(hours: 1, minutes: 1).inMinutes / 60;
  check('1 h 1 min (10:20-11:21) bills 1.5 h',
      InvoiceRules.chargeableHours(reported), 1.5);
  check('1 h 30 min bills 1.5 h', InvoiceRules.chargeableHours(1.5), 1.5);
  check('1 h 31 min bills 2 h',
      InvoiceRules.chargeableHours(1 + 31 / 60), 2.0);
  check('no time bills nothing', InvoiceRules.chargeableHours(0), 0.0);

  print('=== The published rates ===');
  check('normal hour', InvoiceRates.normalHour, 540.60);
  check('overtime hour', InvoiceRates.overtimeHour, 601.02);
  check('Sunday hour', InvoiceRates.sundayHour, 720.80);
  check('per kilometre', InvoiceRates.perKilometre, 6.50);
  check('half hour is half the hourly rate',
      InvoiceRates.normalHour / 2, 270.30);

  print('=== A plain inspection: 1 h 1 min, 40 km, nothing sampled ===');
  var t = InvoiceRules.totals(
    normalHours: reported,
    overtimeHours: 0,
    sundayHours: 0,
    kilometres: 40,
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
  money('time  1.5 x R540.60', t.normal, 'R810.90');
  check('travel 40 x R6.50', t.travel, 260.0);
  money('inspection total', t.inspection, 'R1 070.90');
  money('grand total', t.grand, 'R1 070.90');

  print('=== Two PMP samples (fat + protein each) — the M3 case ===');
  t = InvoiceRules.totals(
    normalHours: 2,
    overtimeHours: 0,
    sundayHours: 0,
    kilometres: 0,
    pmpFatTests: 2,
    pmpProteinTests: 2,
    pmpCalciumTests: 0,
    pmpPhysicalTests: 0,
    rawFatTests: 0,
    rawProteinTests: 0,
    rawSoyaTests: 0,
    rawStarchTests: 0,
    rawDnaTests: 0,
    rawCalciumTests: 0,
  );
  money('PMP laboratory  2x875.56 + 2x533.18', t.pmpLab, 'R2 817.48');
  money('time 2 x R540.60', t.normal, 'R1 081.20');
  money('grand total', t.grand, 'R3 898.68');

  print('=== One raw Category A sample (fat + protein) ===');
  t = InvoiceRules.totals(
    normalHours: 1,
    overtimeHours: 0,
    sundayHours: 0,
    kilometres: 0,
    pmpFatTests: 0,
    pmpProteinTests: 0,
    pmpCalciumTests: 0,
    pmpPhysicalTests: 0,
    rawFatTests: 1,
    rawProteinTests: 1,
    rawSoyaTests: 0,
    rawStarchTests: 0,
    rawDnaTests: 0,
    rawCalciumTests: 0,
  );
  money('raw laboratory 875.56 + 533.18', t.rawLab, 'R1 408.74');
  money('grand total', t.grand, 'R1 949.34');

  print('=== Category B and C, and MRM calcium ===');
  t = InvoiceRules.totals(
    normalHours: 0,
    overtimeHours: 0,
    sundayHours: 0,
    kilometres: 0,
    pmpFatTests: 0,
    pmpProteinTests: 0,
    pmpCalciumTests: 0,
    pmpPhysicalTests: 0,
    rawFatTests: 0,
    rawProteinTests: 0,
    rawSoyaTests: 1,
    rawStarchTests: 1,
    rawDnaTests: 1,
    rawCalciumTests: 1,
  );
  money('soya + starch + DNA + calcium', t.rawLab, 'R6 488.26');

  print('=== The one-hour minimum applies to the visit, not each band ===');
  // 15:30 to 16:45: half an hour normal, three quarters overtime.
  final bands = InvoiceRules.chargeableBands(
      normal: 0.5, overtime: 0.75, sunday: 0);
  check('normal band', bands.normal, 0.5);
  check('overtime band', bands.overtime, 1.0);
  check('not billed as two full hours',
      bands.normal + bands.overtime < 2.0, true);

  print('=== Only the raw and processed-meat time is charged ===');
  // A Tuesday visit: eggs 09:00, poultry 09:30, raw 10:00, PMP 10:40,
  // signed off 11:20. Two and a half hours on site, one hour twenty of it
  // chargeable, and the visit's own opening at 08:50 belongs to the eggs.
  DateTime at(int hour, int minute) => DateTime(2026, 9, 8, hour, minute);
  var window = InvoiceRules.chargeableWindow(
    members: [
      (kind: 'egg', inspectedAt: at(9, 0)),
      (kind: 'poultry', inspectedAt: at(9, 30)),
      (kind: 'rawrmp', inspectedAt: at(10, 0)),
      (kind: 'pmp', inspectedAt: at(10, 40)),
    ],
    visitStarted: at(8, 50),
    visitEnded: at(11, 20),
  );
  check('starts at the raw inspection, not the visit',
      InvoiceRules.clock(window.start), '10:00');
  check('runs the raw and PMP stretches only',
      InvoiceRules.clock(window.end), '11:20');
  check('the visit is chargeable', window.billable, true);

  // The same visit with the eggs done in the middle: 80 minutes of raw and
  // PMP either side of them, and the eggs in between are not charged.
  window = InvoiceRules.chargeableWindow(
    members: [
      (kind: 'rawrmp', inspectedAt: at(10, 0)),
      (kind: 'egg', inspectedAt: at(10, 40)),
      (kind: 'pmp', inspectedAt: at(11, 20)),
    ],
    visitStarted: at(10, 0),
    visitEnded: at(12, 0),
  );
  check('the egg stretch in the middle drops out',
      InvoiceRules.clock(window.end), '11:20');

  // An eggs-and-poultry visit charges no time at all — the form still shows
  // when the inspector was there, and bills the kilometres.
  window = InvoiceRules.chargeableWindow(
    members: [
      (kind: 'egg', inspectedAt: at(9, 0)),
      (kind: 'poultry_label', inspectedAt: at(9, 40)),
    ],
    visitStarted: at(8, 55),
    visitEnded: at(10, 30),
  );
  check('nothing chargeable on an eggs-and-poultry visit',
      window.billable, false);
  check('but the visit is still shown, from',
      InvoiceRules.clock(window.start), '08:55');
  check('and to', InvoiceRules.clock(window.end), '10:30');

  // One commodity on its own bills the whole visit, exactly as before.
  window = InvoiceRules.chargeableWindow(
    members: [(kind: 'rawrmp', inspectedAt: at(10, 5))],
    visitStarted: at(10, 0),
    visitEnded: at(11, 0),
  );
  check('a raw-only visit still bills its whole hour',
      '${InvoiceRules.clock(window.start)}-${InvoiceRules.clock(window.end)}',
      '10:00-11:00');

  // One minute on site is still an hour: the tariff's minimum is owed the
  // moment a chargeable inspection is opened.
  window = InvoiceRules.chargeableWindow(
    members: [(kind: 'pmp', inspectedAt: at(10, 0))],
    visitStarted: at(10, 0),
    visitEnded: at(10, 1),
  );
  var oneMinute = InvoiceRules.splitHours(window.start, window.end);
  check('one minute of PMP still bills an hour',
      InvoiceRules.chargeableBands(
              normal: oneMinute.normal,
              overtime: oneMinute.overtime,
              sunday: oneMinute.sunday)
          .normal,
      1.0);

  // Opened and signed off on the same instant — the clock says nothing, the
  // inspection still happened.
  window = InvoiceRules.chargeableWindow(
    members: [(kind: 'rawrmp', inspectedAt: at(10, 0))],
    visitStarted: at(10, 0),
    visitEnded: at(10, 0),
  );
  oneMinute = InvoiceRules.splitHours(window.start, window.end);
  check('a zero-length raw inspection still bills an hour',
      InvoiceRules.chargeableBands(
              normal: oneMinute.normal,
              overtime: oneMinute.overtime,
              sunday: oneMinute.sunday)
          .normal,
      1.0);
  check('and the eggs-only visit still bills nothing',
      InvoiceRules.chargeableWindow(
        members: [(kind: 'egg', inspectedAt: at(10, 0))],
        visitStarted: at(10, 0),
        visitEnded: at(11, 0),
      ).billable,
      false);

  print('=== Against forms the Agency actually signed and sent ===');
  // Three Food Lovers Market invoices from the current tariff, read off the
  // signed scans. Each is billed for one hour, whatever the clock said.
  void signed({
    required String what,
    required double kilometres,
    required int rawFat,
    required int rawProtein,
    required String inspection,
    required String lab,
    required String grand,
  }) {
    final t = InvoiceRules.totals(
      normalHours: 1,
      overtimeHours: 0,
      sundayHours: 0,
      kilometres: kilometres,
      pmpFatTests: 0,
      pmpProteinTests: 0,
      pmpCalciumTests: 0,
      pmpPhysicalTests: 0,
      rawFatTests: rawFat,
      rawProteinTests: rawProtein,
      rawSoyaTests: 0,
      rawStarchTests: 0,
      rawDnaTests: 0,
      rawCalciumTests: 0,
    );
    money('$what — time and travel', t.inspection, inspection);
    money('$what — laboratory', t.rawLab, lab);
    money('$what — total invoice amount', t.grand, grand);
  }

  signed(
    what: 'Park Meadows 07/05/2026',
    kilometres: 40,
    rawFat: 1,
    rawProtein: 1,
    inspection: 'R800.60',
    lab: 'R1 408.74',
    // The signed form adds these to R2 209.04. R800.60 + R1 408.74 is
    // R2 209.34; the thirty cents is the inspector's addition, not the
    // tariff, and the other two forms below add up exactly.
    grand: 'R2 209.34',
  );
  signed(
    what: 'Inland DC 19/06/2026',
    kilometres: 40,
    rawFat: 2,
    rawProtein: 2,
    inspection: 'R800.60',
    lab: 'R2 817.48',
    grand: 'R3 618.08',
  );
  signed(
    what: 'Whale Coast Mall 20/08/2026',
    kilometres: 62,
    rawFat: 1,
    rawProtein: 1,
    inspection: 'R943.60',
    lab: 'R1 408.74',
    grand: 'R2 352.34',
  );

  print('=== Formatting, as the form writes it ===');
  check('thousands separated by a space', InvoiceRules.rand(1234.5),
      'R1 234.50');
  check('under a thousand', InvoiceRules.rand(810.9), 'R810.90');

  print(_failures == 0
      ? '\nAll pricing checks passed.\n'
      : '\n$_failures CHECK(S) FAILED.\n');
}
