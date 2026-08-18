import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';

/// Grading and classification rules.
///
/// Two behaviours here are worth pinning down because getting either wrong is
/// silent: a grade offered that the designation cannot carry, and a tick-list
/// whose sense is inverted.

const _chicken = 1;
const _turkey = 2;

const _broiler = 10;
const _springChicken = 11;
const _youngTurkey = 12;

const _gradeA = PoultryGradeRef(id: 1, name: 'Grade A', rank: 1);
const _gradeB = PoultryGradeRef(id: 2, name: 'Grade B', rank: 2);
const _undergrade = PoultryGradeRef(id: 3, name: 'Undergrade', rank: null);
const _grades = [_gradeA, _gradeB, _undergrade];

const _designations = [
  PoultryDesignationRef(id: _broiler, name: 'Broiler'),
  PoultryDesignationRef(id: _springChicken, name: 'Spring Chicken'),
  PoultryDesignationRef(id: _youngTurkey, name: 'Young turkey'),
];

const _links = [
  // Chicken / Broiler may be A or B, but never Undergrade.
  PoultryGradeLink(meatTypeId: _chicken, designationId: _broiler, gradeId: 1),
  PoultryGradeLink(meatTypeId: _chicken, designationId: _broiler, gradeId: 2),
  // Chicken / Spring Chicken is A only.
  PoultryGradeLink(
      meatTypeId: _chicken, designationId: _springChicken, gradeId: 1),
  // The same designation under a different meat type carries different grades.
  PoultryGradeLink(
      meatTypeId: _turkey, designationId: _youngTurkey, gradeId: 3),
];

PoultryChecklistItemRef _item(int id) => PoultryChecklistItemRef(
      id: id,
      kind: PoultryChecklistKind.grading,
      originalId: id,
      description: 'Item $id',
      regulationReference: '',
    );

final _checklist = [_item(1), _item(2), _item(3)];

void main() {
  group('which grades a designation may carry', () {
    test('only the linked grades are offered', () {
      final grades = PoultryRules.gradesFor(
        meatTypeId: _chicken,
        designationId: _broiler,
        links: _links,
        grades: _grades,
      );

      expect(grades.map((g) => g.name), ['Grade A', 'Grade B']);
      // The whole point: offering Undergrade here would let an inspector
      // record a classification the original refuses.
      expect(grades.map((g) => g.name), isNot(contains('Undergrade')));
    });

    test('the same designation differs by meat type', () {
      final asChicken = PoultryRules.gradesFor(
        meatTypeId: _chicken,
        designationId: _youngTurkey,
        links: _links,
        grades: _grades,
      );
      final asTurkey = PoultryRules.gradesFor(
        meatTypeId: _turkey,
        designationId: _youngTurkey,
        links: _links,
        grades: _grades,
      );

      expect(asChicken, isEmpty);
      expect(asTurkey.single.name, 'Undergrade');
    });

    test('an unknown pairing offers nothing rather than everything', () {
      // Falling back to the full list is how an unsupported grade gets
      // recorded; an empty picker is visible to the inspector instead.
      expect(
        PoultryRules.gradesFor(
          meatTypeId: 99,
          designationId: _broiler,
          links: _links,
          grades: _grades,
        ),
        isEmpty,
      );
      expect(
        PoultryRules.gradesFor(
          meatTypeId: null,
          designationId: null,
          links: _links,
          grades: _grades,
        ),
        isEmpty,
      );
    });

    test('grades come back in reference order, not link order', () {
      const reversed = [
        PoultryGradeLink(
            meatTypeId: _chicken, designationId: _broiler, gradeId: 2),
        PoultryGradeLink(
            meatTypeId: _chicken, designationId: _broiler, gradeId: 1),
      ];

      expect(
        PoultryRules.gradesFor(
          meatTypeId: _chicken,
          designationId: _broiler,
          links: reversed,
          grades: _grades,
        ).map((g) => g.name),
        ['Grade A', 'Grade B'],
      );
    });
  });

  group('which designations a meat type offers', () {
    test('only those that can be graded under it', () {
      final forChicken = PoultryRules.designationsFor(
        meatTypeId: _chicken,
        links: _links,
        designations: _designations,
      );

      expect(forChicken.map((d) => d.name), ['Broiler', 'Spring Chicken']);
      // Offering Young turkey under chicken would strand the inspector on the
      // grade field with an empty picker.
      expect(forChicken.map((d) => d.name), isNot(contains('Young turkey')));
    });

    test('no meat type chosen yet offers nothing', () {
      expect(
        PoultryRules.designationsFor(
          meatTypeId: null,
          links: _links,
          designations: _designations,
        ),
        isEmpty,
      );
    });
  });

  group('a tick means compliant, not a finding', () {
    test('unticked rows are the deviations', () {
      final findings = PoultryRules.findings(
        items: _checklist,
        compliantItemIds: {1, 3},
      );

      expect(findings.map((f) => f.item.id), [2]);
    });

    test('an untouched checklist is every row failing, not none', () {
      // The inversion in one sentence. An inspector who saves without working
      // through the list has recorded three deviations, and reading the empty
      // set as "nothing wrong" would pass a consignment nobody checked.
      final findings = PoultryRules.findings(
        items: _checklist,
        compliantItemIds: const {},
      );

      expect(findings, hasLength(3));
      expect(
        PoultryRules.directionRequired(
          items: _checklist,
          compliantItemIds: const {},
        ),
        isTrue,
      );
    });

    test('every row ticked is fully compliant and needs no direction', () {
      expect(
        PoultryRules.isFullyCompliant(
          items: _checklist,
          compliantItemIds: {1, 2, 3},
        ),
        isTrue,
      );
      expect(
        PoultryRules.directionRequired(
          items: _checklist,
          compliantItemIds: {1, 2, 3},
        ),
        isFalse,
      );
    });

    test('an empty checklist is not "fully compliant"', () {
      // Nothing to check is not the same as everything passing, and reporting
      // a pass on a device with no rules would be worse than reporting none.
      expect(
        PoultryRules.isFullyCompliant(
          items: const [],
          compliantItemIds: const {},
        ),
        isFalse,
      );
    });

    test('a tick for a row that is no longer on the list does not pass it', () {
      // A retired reference row leaves its id in the record. That id must not
      // make some other row count as ticked.
      final findings = PoultryRules.findings(
        items: _checklist,
        compliantItemIds: {1, 2, 3, 99},
      );

      expect(findings, isEmpty);
    });
  });
}
