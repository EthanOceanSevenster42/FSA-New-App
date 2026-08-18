import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// South African mass bands, matching the seeded backend.
const _bands = [
  EggSizeBand(id: 1, name: 'Small', minMassG: 35, maxMassG: 42.99, sortOrder: 1),
  EggSizeBand(id: 2, name: 'Medium', minMassG: 43, maxMassG: 50.99, sortOrder: 2),
  EggSizeBand(id: 3, name: 'Large', minMassG: 51, maxMassG: 58.99, sortOrder: 3),
  EggSizeBand(
      id: 4, name: 'Extra Large', minMassG: 59, maxMassG: 65.99, sortOrder: 4),
  EggSizeBand(id: 5, name: 'Jumbo', minMassG: 66, maxMassG: null, sortOrder: 5),
];

const _gradeA = EggGradeRef(id: 1, name: 'Grade A', rank: 1);
const _gradeB = EggGradeRef(id: 2, name: 'Grade B', rank: 2);
const _gradeC = EggGradeRef(id: 3, name: 'Grade C', rank: 3);
const _grades = [_gradeA, _gradeB, _gradeC];

const _deviations = [
  // Recorded but harmless.
  DeviationRef(
      id: 10, categoryId: 1, description: 'No swimmers', downgradesToGradeId: null),
  DeviationRef(
      id: 11, categoryId: 2, description: 'Blood spot light', downgradesToGradeId: 2),
  DeviationRef(
      id: 12, categoryId: 2, description: 'Blood spot strong', downgradesToGradeId: 3),
  DeviationRef(
      id: 13, categoryId: 4, description: 'Irregular shell', downgradesToGradeId: 2),
];

void main() {
  group('size banding', () {
    test('picks the band containing the mass', () {
      expect(EggRules.sizeFor(45, _bands)?.name, 'Medium');
      expect(EggRules.sizeFor(55, _bands)?.name, 'Large');
      expect(EggRules.sizeFor(60, _bands)?.name, 'Extra Large');
    });

    test('band boundaries are inclusive at both ends', () {
      expect(EggRules.sizeFor(43, _bands)?.name, 'Medium');
      expect(EggRules.sizeFor(50.99, _bands)?.name, 'Medium');
      expect(EggRules.sizeFor(51, _bands)?.name, 'Large');
    });

    test('the top band has no upper limit', () {
      expect(EggRules.sizeFor(66, _bands)?.name, 'Jumbo');
      expect(EggRules.sizeFor(120, _bands)?.name, 'Jumbo');
    });

    test('a mass below every band is unclassified, not forced to Small', () {
      // Calling a 20g egg "Small" would misreport the consignment.
      expect(EggRules.sizeFor(20, _bands), isNull);
    });

    test('a declaration is never derived for an individual egg', () {
      // "Mixed Size" is on the pack, not on the scale: it describes a
      // consignment of assorted sizes. The original carries it as a size and
      // keys 90 tolerance rules to it, so it has to exist — but deriving it
      // for a single egg would report a mass band that egg does not occupy.
      //
      // It is excluded by flag, not by where it sorts. Mixed Size shares its
      // 33 g floor with Small, so an ordering argument would hold only while
      // the ladder's floor stayed at 33 — this fixture starts Small at 35, and
      // a 33 g egg fell straight through to the declaration until the flag
      // existed.
      const withDeclaration = [
        ..._bands,
        EggSizeBand(
          id: 9,
          name: 'Mixed Size',
          minMassG: 33,
          maxMassG: null,
          sortOrder: 9,
          isMassBand: false,
        ),
      ];

      for (final mass in [33.0, 34.0, 35.0, 45.0, 55.0, 60.0, 66.0, 120.0, 500.0]) {
        expect(
          EggRules.sizeFor(mass, withDeclaration)?.name,
          isNot('Mixed Size'),
          reason: '${mass}g resolved to the declaration',
        );
      }

      // And it does not disturb the bands it sits behind.
      expect(EggRules.sizeFor(45, withDeclaration)?.name, 'Medium');
      expect(EggRules.sizeFor(120, withDeclaration)?.name, 'Jumbo');
      // Still unclassified below the ladder, rather than falling through to it.
      expect(EggRules.sizeFor(20, withDeclaration), isNull);
      // The gap between the declaration's floor and the ladder's is the case
      // that used to fail.
      expect(EggRules.sizeFor(34, withDeclaration), isNull);
    });

    test('missing or nonsense masses are unclassified', () {
      expect(EggRules.sizeFor(null, _bands), isNull);
      expect(EggRules.sizeFor(0, _bands), isNull);
      expect(EggRules.sizeFor(-5, _bands), isNull);
      expect(EggRules.sizeFor(50, const []), isNull);
    });
  });

  group('Haugh unit', () {
    test('matches the published formula for known eggs', () {
      // HU = 100 * log10(h - 1.7*w^0.37 + 7.6), cross-checked against Python.
      expect(
        EggRules.haughUnit(albumenHeightMm: 6.2, massG: 57)!,
        closeTo(79.3237, 0.001),
      );
      expect(
        EggRules.haughUnit(albumenHeightMm: 4.0, massG: 57)!,
        closeTo(60.3370, 0.001),
      );
      expect(
        EggRules.haughUnit(albumenHeightMm: 8.0, massG: 57)!,
        closeTo(90.3745, 0.001),
      );
    });

    test('a taller albumen on the same egg scores higher', () {
      final low = EggRules.haughUnit(albumenHeightMm: 4.0, massG: 57)!;
      final high = EggRules.haughUnit(albumenHeightMm: 8.0, massG: 57)!;
      expect(high, greaterThan(low));
    });

    test('returns null rather than 0 when not measured', () {
      // 0 would read as "worst possible albumen", a different claim.
      expect(EggRules.haughUnit(albumenHeightMm: null, massG: 57), isNull);
      expect(EggRules.haughUnit(albumenHeightMm: 6.2, massG: null), isNull);
      expect(EggRules.haughUnit(albumenHeightMm: 0, massG: 57), isNull);
    });

    test('returns null when the log argument would be non-positive', () {
      // A very flat albumen on a very large egg makes the inner term <= 0.
      expect(EggRules.haughUnit(albumenHeightMm: 0.1, massG: 200), isNull);
    });
  });

  group('per-egg grading', () {
    EggGradeRef? grade(Set<int> ticked) => EggRules.gradeForEgg(
          tickedDeviationIds: ticked,
          deviations: _deviations,
          grades: _grades,
        );

    test('no deviations means the best grade', () {
      expect(grade({})?.name, 'Grade A');
    });

    test('a harmless deviation does not downgrade', () {
      expect(grade({10})?.name, 'Grade A');
    });

    test('a downgrading deviation applies', () {
      expect(grade({11})?.name, 'Grade B');
    });

    test('the worst ticked deviation wins', () {
      expect(grade({11, 12, 13})?.name, 'Grade C');
    });

    test('an unknown deviation id is ignored, not fatal', () {
      expect(grade({999})?.name, 'Grade A');
    });

    test('no grades defined yields null rather than a guess', () {
      expect(
        EggRules.gradeForEgg(
          tickedDeviationIds: {11},
          deviations: _deviations,
          grades: const [],
        ),
        isNull,
      );
    });
  });

  group('Haugh additional-sample rule (below 70 HU needs 6 more)', () {
    test('mean is null when nothing was measured, not 0', () {
      // 0 would trip the "below 70" rule on an unmeasured sample.
      expect(EggRules.meanHaughUnit([null, null]), isNull);
    });

    test('mean ignores unmeasured eggs', () {
      expect(EggRules.meanHaughUnit([80.0, null, 60.0]), 70.0);
    });

    test('no extra samples required when the mean is at or above 70', () {
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [75.0, 80.0],
          sampledCount: 2,
        ),
        0,
      );
      // Exactly 70 is acceptable — the rule is "below 70".
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [70.0],
          sampledCount: 1,
        ),
        0,
      );
    });

    test('six more required when the mean falls below 70', () {
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [60.0, 65.0],
          sampledCount: 2,
        ),
        6,
      );
    });

    test('requirement shrinks as the extra eggs are captured', () {
      // Two measured below 70 needs 8 total; 5 captured leaves 3 outstanding.
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [60.0, 65.0],
          sampledCount: 5,
          baselineCount: 2,
        ),
        3,
      );
    });

    test('the requirement can actually be satisfied', () {
      // The bug this pins down: deriving the target from the *current*
      // measured count meant every egg added and measured pushed the target
      // six further away, and the inspection could never be saved.
      const baseline = 2;
      var sampled = baseline;
      final readings = <double?>[60.0, 65.0];

      // Capture and measure the six extra eggs the rule asked for.
      for (var i = 0; i < EggRules.haughAdditionalSampleCount; i++) {
        sampled++;
        readings.add(62.0); // still low — the mean stays under 70
      }

      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: readings,
          sampledCount: sampled,
          baselineCount: baseline,
        ),
        0,
        reason: 'six more eggs must clear the requirement',
      );
    });

    test('the target does not move as more eggs are measured', () {
      // Same baseline, one further egg captured each time: the outstanding
      // count must fall by one each time, never hold steady.
      final outstanding = [
        for (var sampled = 2; sampled <= 8; sampled++)
          EggRules.additionalSamplesRequired(
            haughUnits: [for (var i = 0; i < sampled; i++) 60.0],
            sampledCount: sampled,
            baselineCount: 2,
          ),
      ];

      expect(outstanding, [6, 5, 4, 3, 2, 1, 0]);
    });

    test('without a baseline the eggs on hand become the baseline', () {
      // First evaluation: six more than what is already captured.
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [60.0, 65.0],
          sampledCount: 2,
        ),
        6,
      );
    });

    test('never negative once the requirement is met', () {
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [60.0, 65.0],
          sampledCount: 20,
          baselineCount: 2,
        ),
        0,
      );
    });

    test('nothing required when no Haugh readings were taken', () {
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [null, null],
          sampledCount: 2,
        ),
        0,
      );
    });
  });

  group('field validation', () {
    test('deviations need a mass first', () {
      expect(EggValidation.canRecordDeviations(null), isFalse);
      expect(EggValidation.canRecordDeviations(0), isFalse);
      expect(EggValidation.canRecordDeviations(-1), isFalse);
      expect(EggValidation.canRecordDeviations(55), isTrue);
    });

    test('Haugh meter value cannot be zero or less', () {
      expect(EggValidation.albumenHeight(null), isNull);
      expect(EggValidation.albumenHeight(6.2), isNull);
      expect(EggValidation.albumenHeight(0), contains('cannot be 0 or less'));
      expect(EggValidation.albumenHeight(-3), contains('cannot be 0 or less'));
    });

    test('egg mass is bounded, catching a mis-keyed scale reading', () {
      expect(EggValidation.eggMass(null), isNull);
      expect(EggValidation.eggMass(62.5), isNull);
      expect(EggValidation.eggMass(0), contains('zero or less'));
      expect(EggValidation.eggMass(-5), contains('zero or less'));
      // 625 instead of 62.5 — the classic decimal slip.
      expect(EggValidation.eggMass(625), contains('too high'));
    });

    test('email format is checked but blank is allowed', () {
      expect(EggValidation.email(''), isNull);
      expect(EggValidation.email('   '), isNull);
      expect(EggValidation.email('inspector@fsa.co.za'), isNull);
      expect(EggValidation.email('first.last+tag@sub.fsa.co.za'), isNull);
      expect(EggValidation.email('not-an-email'), isNotNull);
      expect(EggValidation.email('missing@domain'), isNotNull);
      expect(EggValidation.email('@nolocal.co.za'), isNotNull);
    });

    test('best before must be after today', () {
      final now = DateTime(2026, 7, 31);
      expect(
        EggValidation.bestBefore(DateTime(2026, 7, 30), now: now),
        contains('prior to'),
      );
      expect(
        EggValidation.bestBefore(DateTime(2026, 7, 31), now: now),
        contains("today's date"),
      );
      expect(EggValidation.bestBefore(DateTime(2026, 8, 1), now: now), isNull);
      expect(EggValidation.bestBefore(null, now: now), isNull);
    });
  });

  group('consignment grading', () {
    test('takes the worst egg', () {
      expect(
        EggRules.consignmentGrade([_gradeA, _gradeC, _gradeB])?.name,
        'Grade C',
      );
    });

    test('ungraded eggs are skipped, never counted as best', () {
      expect(
        EggRules.consignmentGrade([null, _gradeB, null])?.name,
        'Grade B',
      );
    });

    test('all ungraded yields null', () {
      expect(EggRules.consignmentGrade([null, null]), isNull);
      expect(EggRules.consignmentGrade([]), isNull);
    });
  });
}
