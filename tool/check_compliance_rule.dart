// Exercises the compliance rule the office reads off every record.
//
//     dart run tool/check_compliance_rule.dart
//
// The rule decides what APS shows as Compliant / Non-Compliant / Not
// assessed, so it is worth being able to run it on its own — particularly
// on a machine where the Flutter test runner will not start. Same
// assertions as a unit test; no engine required.

import 'dart:io';

import 'package:fsa_app/features/visits/domain/inspection_outcome.dart';

int _failures = 0;

void check(String what, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (!ok) _failures++;
  stdout.writeln('${ok ? "  ok  " : "  FAIL"}  $what'
      '${ok ? "" : "\n         expected: $expected\n         actual:   $actual"}');
}

/// A small checklist: two marking rows and one scale row.
const requirements = <ChecklistRequirement>[
  (
    id: 1,
    section: 'marking',
    description: 'Country of Origin',
    regulation: '[Reg. 7(1)(e) & 11]'
  ),
  (
    id: 2,
    section: 'marking',
    description: 'Date Marking/Batch Code',
    regulation: '[Reg. 7(1)(d) & 10]'
  ),
  (
    id: 3,
    section: 'scale',
    description: 'Prescribed Particulars',
    regulation: '[Reg. 7(2) & (a)]'
  ),
];

void main() {
  stdout.writeln('compliance rule\n');

  final everything = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: {1, 2, 3},
    checklistWorked: true,
  );
  check('every requirement met reads compliant', everything.isCompliant, true);
  check('  with nothing listed', everything.findings.length, 0);

  final oneMissed = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: {1, 3},
    checklistWorked: true,
  );
  check('an unticked requirement is a deviation', oneMissed.isCompliant, false);
  check('  and is named in full', oneMissed.findings.first,
      'Date Marking/Batch Code [Reg. 7(1)(d) & 10]');

  // The block that was not at the premises must not fail the inspection.
  final scaleAbsent = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking'},
    compliantIds: {1, 2},
    checklistWorked: true,
  );
  check('a block that was not present is not judged',
      scaleAbsent.isCompliant, true);
  check('  so its rows are not listed', scaleAbsent.findings.length, 0);

  // Nobody worked the checklist: that is not a pass.
  final untouched = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: const {},
    checklistWorked: false,
  );
  check('an unworked checklist is not assessed', untouched.isCompliant, null);

  // ...and an unworked checklist must never read as compliant.
  check('  and never as compliant', untouched.isCompliant == true, false);
  check('  and invents no deviations of its own', untouched.findings.length, 0);

  // A deviation the inspector wrote down is one they saw, whatever state
  // the tick-boxes are in.
  final writtenOnly = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: const {},
    checklistWorked: false,
    extraFindings: const ['Product not marked at all'],
  );
  check('a written deviation fails the product on its own',
      writtenOnly.isCompliant, false);
  check('  and is the only thing listed', writtenOnly.findings.length, 1);

  final written = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: {1, 2, 3},
    checklistWorked: true,
    extraFindings: const ['Mechanically recovered meat, not declared'],
  );
  check("the inspector's own words count as a deviation",
      written.isCompliant, false);
  check('  and travel with the rest', written.findings.last,
      'Mechanically recovered meat, not declared');

  final repeated = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking'},
    compliantIds: {1},
    checklistWorked: true,
    extraFindings: const ['Date Marking/Batch Code [Reg. 7(1)(d) & 10]'],
  );
  check('the same deviation is not listed twice', repeated.findings.length, 1);

  final asText = InspectionFindings.fromChecklist(
    requirements: requirements,
    sectionsPresent: {'marking', 'scale'},
    compliantIds: {1},
    checklistWorked: true,
  );
  check('findings travel one per line',
      asText.findingsText.split('\n').length, 2);

  stdout.writeln(_failures == 0
      ? '\nall checks passed'
      : '\n$_failures check(s) FAILED');
  if (_failures > 0) exitCode = 1;
}
