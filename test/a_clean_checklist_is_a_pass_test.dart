import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/visits/domain/inspection_outcome.dart';

/// A finished checklist with nothing wrong on it is a pass.
///
/// `checklistWorked` is there so an untouched checklist is never read as a
/// pass: every row on one is unticked, and counting those as met would put
/// a verdict on the record that no inspector gave.
///
/// What it was given as evidence of "worked", though, was evidence of
/// something being wrong or something being weighed — eggs looked for
/// weighed samples or failed rows, poultry for ticks. So the cleanest
/// possible inspection looked exactly like one nobody opened, and went to
/// the office with neither a pass nor a fail. Two thirds of every egg
/// inspection and two thirds of every poultry one reached APS that way,
/// against none of the labelling inspections, which happen to record their
/// ticks.
///
/// The caller now passes the record's own completion as the evidence. These
/// hold the rule from both sides: a finished clean checklist passes, and an
/// untouched one still says nothing.
void main() {
  const requirements = <ChecklistRequirement>[
    (id: 1, section: 'packing', description: 'Packing area clean',
      regulation: 'R.345 3(1)'),
    (id: 2, section: 'packing', description: 'Date mark legible',
      regulation: 'R.345 5(2)'),
    (id: 3, section: 'label_pack', description: 'Grade shown on pack',
      regulation: 'R.345 6(1)'),
    // Belongs to a section this inspection did not cover, so it must never
    // be judged either way.
    (id: 9, section: 'label_outer', description: 'Outer label present',
      regulation: 'R.345 7(1)'),
  ];
  const present = {'packing', 'label_pack'};

  test('a finished checklist with nothing wrong is COMPLIANT', () {
    // The case that was being lost: every applicable row met, nothing
    // weighed, no deviation written. The inspector did the work and the
    // record said nothing at all.
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: present,
      compliantIds: {1, 2, 3},
      checklistWorked: true,
    );
    expect(outcome.isCompliant, isTrue);
    expect(outcome.findings, isEmpty);
  });

  test('a checklist nobody opened still records NO verdict', () {
    // The guard this rule exists for. Unticked rows on an untouched sheet
    // are not deviations the inspector saw.
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: present,
      compliantIds: const {},
      checklistWorked: false,
    );
    expect(outcome.isCompliant, isNull);
    expect(outcome.findings, isEmpty);
  });

  test('a worked checklist with an unticked row FAILS on that row', () {
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: present,
      compliantIds: {1, 3},          // 2 left unticked
      checklistWorked: true,
    );
    expect(outcome.isCompliant, isFalse);
    expect(outcome.findings, hasLength(1));
    expect(outcome.findings.single, contains('Date mark legible'));
  });

  test('a row outside the sections covered is never judged', () {
    // Requirement 9 is label_outer; this inspection covered packing and
    // label_pack only. It must not fail the product.
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: present,
      compliantIds: {1, 2, 3},
      checklistWorked: true,
    );
    expect(outcome.isCompliant, isTrue,
        reason: 'the outer-label row does not apply to this inspection');
  });

  test('a deviation written in the inspector\'s own words fails it', () {
    // They saw it, so it counts whatever the ticks say — and it is proof
    // the sheet was worked even when nothing else is.
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: present,
      compliantIds: {1, 2, 3},
      checklistWorked: false,
      extraFindings: const ['Cracked eggs beyond the allowed band'],
    );
    expect(outcome.isCompliant, isFalse);
    expect(outcome.findings.single,
        'Cracked eggs beyond the allowed band');
  });

  test('a worked checklist with no applicable rows records NO verdict', () {
    // Nothing applied to this product, so there was nothing to pass.
    final outcome = InspectionFindings.fromChecklist(
      requirements: requirements,
      sectionsPresent: const {'container'},
      compliantIds: const {},
      checklistWorked: true,
    );
    expect(outcome.isCompliant, isNull);
  });
}
