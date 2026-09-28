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

    test('a size is "more than" its floor — the floor itself is not in it',
        () {
      expect(EggRules.sizeFor(43.01, _bands)?.name, 'Medium');
      expect(EggRules.sizeFor(50.99, _bands)?.name, 'Medium');
      expect(EggRules.sizeFor(51.5, _bands)?.name, 'Large');
      // Exactly 51 g is not "more than 51 g"; this fixture's Large ceiling
      // is 50.99, so it falls between bands.
      expect(EggRules.sizeFor(51, _bands), isNull);
    });

    test('the top band has no upper limit', () {
      expect(EggRules.sizeFor(66.5, _bands)?.name, 'Jumbo');
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

    test('nothing in the reference can lower a grade: not determined', () {
      // How the Agency's list actually ships - no deviation carries a
      // downgrade, because the original never determined a grade at all,
      // only counted deviations against their bands. The form used to fall
      // through to the best grade, so a decayed sample read "Grade 1".
      final undowngradeable = [
        for (final d in _deviations)
          DeviationRef(
            id: d.id,
            categoryId: d.categoryId,
            description: d.description,
            downgradesToGradeId: null,
          ),
      ];
      expect(
        EggRules.gradeForEgg(
          tickedDeviationIds: {11, 12},
          deviations: undowngradeable,
          grades: _grades,
        ),
        isNull,
      );
      expect(
        EggRules.gradeForEgg(
          tickedDeviationIds: {},
          deviations: undowngradeable,
          grades: _grades,
        ),
        isNull,
        reason: 'with no way to lower a grade, no egg can be graded at all',
      );
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

    test('any best-before date is accepted - past, today or future', () {
      // The original refused anything before tomorrow, which made a pack
      // already past its date impossible to record. The inspector writes
      // down what the label says; that it has passed is a finding.
      final now = DateTime(2026, 7, 31);
      for (final date in [
        DateTime(2026, 7, 30),
        DateTime(2026, 7, 31),
        DateTime(2026, 8, 1),
        DateTime(2019, 1, 1),
      ]) {
        expect(EggValidation.bestBefore(date, now: now), isNull,
            reason: '$date must be accepted as written on the pack');
      }
      expect(EggValidation.bestBefore(null, now: now), isNull);
    });

    test('a date up to and including today counts as passed', () {
      final now = DateTime(2026, 7, 31);
      expect(EggValidation.bestBeforeHasPassed(DateTime(2026, 7, 30), now: now),
          isTrue);
      expect(EggValidation.bestBeforeHasPassed(DateTime(2026, 7, 31), now: now),
          isTrue, reason: 'a best-before is the last day the claim holds');
      expect(EggValidation.bestBeforeHasPassed(DateTime(2026, 8, 1), now: now),
          isFalse);
      expect(EggValidation.bestBeforeHasPassed(null, now: now), isFalse);
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

  group('boundary weights take the lighter band', () {
    // R.345 Table 2: every size is "more than" its floor. A weight sitting
    // exactly on a boundary has not reached the band above. Display order
    // must not influence this — the picker reads light-to-heavy.
    const ladder = [
      EggSizeBand(id: 1, name: 'Small', minMassG: 33, maxMassG: 43, sortOrder: 1),
      EggSizeBand(
          id: 2, name: 'Medium', minMassG: 43, maxMassG: 51, sortOrder: 2),
      EggSizeBand(id: 3, name: 'Large', minMassG: 51, maxMassG: 59, sortOrder: 3),
      EggSizeBand(
          id: 6, name: 'Super Jumbo', minMassG: 72, maxMassG: null, sortOrder: 6),
      EggSizeBand(
          id: 7,
          name: 'Mixed Size',
          minMassG: 33,
          maxMassG: null,
          sortOrder: 7,
          isMassBand: false),
    ];

    test('43 g is Small, not Medium — Medium is more than 43 g', () {
      expect(EggRules.sizeFor(43, ladder)?.name, 'Small');
      expect(EggRules.sizeFor(43.1, ladder)?.name, 'Medium');
    });

    test('51 g is Medium, not Large', () {
      expect(EggRules.sizeFor(51, ladder)?.name, 'Medium');
    });

    test('33 g is not Small — Small is more than 33 g', () {
      expect(EggRules.sizeFor(33, ladder), isNull);
      expect(EggRules.sizeFor(33.1, ladder)?.name, 'Small');
    });

    test('mid-band and open-topped weights are unchanged', () {
      expect(EggRules.sizeFor(47, ladder)?.name, 'Medium');
      expect(EggRules.sizeFor(90, ladder)?.name, 'Super Jumbo');
    });

    test('a declaration is never derived from a weight', () {
      expect(EggRules.sizeFor(35, ladder)?.name, 'Small');
    });
  });

  group('automatic deviations (the original grading engine)', () {
    const sj = EggSizeBand(
        id: 21, name: 'Super Jumbo', minMassG: 72, maxMassG: null, sortOrder: 6);
    const jumbo = EggSizeBand(
        id: 22, name: 'Jumbo', minMassG: 66, maxMassG: 72, sortOrder: 5);
    const small = EggSizeBand(
        id: 23, name: 'Small', minMassG: 33, maxMassG: 43, sortOrder: 1);
    const g1 = EggGradeRef(id: 31, name: 'Grade 1', rank: 1);
    const g2 = EggGradeRef(id: 32, name: 'Grade 2', rank: 2);
    const g3 = EggGradeRef(id: 33, name: 'Grade 3', rank: 3);
    const devs = [
      DeviationRef(
          id: 1,
          categoryId: 1,
          description: 'Super Jumbo - <= 2g of Min. Weight',
          downgradesToGradeId: null),
      DeviationRef(
          id: 2,
          categoryId: 1,
          description: 'Jumbo - <= 2g of Min. Weight',
          downgradesToGradeId: null),
      DeviationRef(
          id: 6,
          categoryId: 1,
          description: 'Small - <= 2g of Min. Weight',
          downgradesToGradeId: null),
      DeviationRef(
          id: 34,
          categoryId: 1,
          description: 'Egg Weight Difference >= 2g',
          downgradesToGradeId: null),
      DeviationRef(
          id: 29,
          categoryId: 15,
          description:
              'Pasteurised 65 units, Not more than 5 units lower than minimum',
          downgradesToGradeId: null),
      DeviationRef(
          id: 30,
          categoryId: 15,
          description:
              'Haugh Value at least 55/35 units, Not more than 5 units lower '
              'than minimum',
          downgradesToGradeId: null),
      DeviationRef(
          id: 36,
          categoryId: 15,
          description:
              'Haugh Value at least 55/35 units, More than 5 units lower than '
              'minimum',
          downgradesToGradeId: null),
      DeviationRef(
          id: 37,
          categoryId: 15,
          description:
              'Pasteurised 65 units, More than 5 units lower than minimum',
          downgradesToGradeId: null),
    ];

    Set<int> weight(double mass, EggSizeBand size, EggGradeRef grade) =>
        EggRules.autoWeightDeviationIds(
          massG: mass,
          declaredSize: size,
          declaredGrade: grade,
          deviations: devs,
        );

    Set<int> albumen(double hu, EggGradeRef grade, {bool past = false}) =>
        EggRules.autoAlbumenDeviationIds(
          haughUnit: hu,
          declaredGrade: grade,
          pasteurised: past,
          deviations: devs,
        );

    test("within 2 g under the declared minimum ticks that size's own row",
        () {
      // "Jumbo" also matches "Super Jumbo - ..." by Contains; the original's
      // LastOrDefault over the id order resolves it to the Jumbo row.
      expect(weight(65, jumbo, g1), {2});
    });

    test('an egg exactly at the minimum is still ticked — weightDiff <= 0',
        () {
      expect(weight(66, jumbo, g1), {2});
    });

    test('more than 2 g under ticks "Egg Weight Difference >= 2g"', () {
      expect(weight(63, jumbo, g1), {34});
    });

    test('above the minimum ticks nothing', () {
      expect(weight(67, jumbo, g1), isEmpty);
    });

    test('Small is excluded from the within-2 g band, as the original excludes it',
        () {
      // PoultryEggManager.cs:1270 guards the within-band branch with
      // `SmallId != model.SelectedPoultryEggSizeTypeId`, so a Small egg within
      // 2 g of the minimum falls between the two branches and ticks nothing.
      // This reverses the 2026-08-28 reading of R.345 Table 4 item 9(a);
      // restored to the original's behaviour on Ethan's instruction,
      // 2026-09-14.
      expect(weight(33, small, g1), isEmpty);
      expect(weight(32, small, g1), isEmpty);
      expect(weight(31, small, g1), isEmpty);
      // More than 2 g under still ticks the over-band row, for Small as for
      // every other size.
      expect(weight(30.9, small, g1), {34});
      expect(weight(30, small, g1), {34});
      expect(weight(33.1, small, g1), isEmpty);
    });

    test('Grade 3 skips the weight checks — except for Super Jumbo', () {
      expect(weight(60, jumbo, g3), isEmpty);
      expect(weight(71, sj, g3), {1});
    });

    test('fresh eggs compare against 55/35 with a 5-unit band', () {
      expect(albumen(51, g1), {30}); // 4 under 55
      expect(albumen(49, g1), {36}); // 6 under 55
      expect(albumen(55, g1), isEmpty);
      expect(albumen(31, g2), {30}); // 4 under 35
      expect(albumen(20, g3), isEmpty); // Grade 3 reference is 0
    });

    test(
        "pasteurised eggs compare against 65 — and exactly 5 under ticks "
        "neither row, as the original's strict inequalities do", () {
      expect(albumen(61, g1, past: true), {29});
      expect(albumen(59, g1, past: true), {37});
      expect(albumen(60, g1, past: true), isEmpty);
    });

    test('every automatic id is managed, so stale ticks get cleared', () {
      expect(EggRules.autoManagedDeviationIds(devs),
          {1, 2, 6, 34, 29, 30, 36, 37});
    });

    test('the below-70 average needs two readings before it can escalate',
        () {
      expect(
        EggRules.additionalSamplesRequired(haughUnits: [60], sampledCount: 1),
        0,
      );
      expect(
        EggRules.additionalSamplesRequired(
            haughUnits: [60, 62], sampledCount: 2),
        6,
      );
    });
  });

  group('weighing at a retailer', () {
    test('an ordinary inspection must carry weighed eggs', () {
      expect(EggValidation.samplesRequired(weighingNotRequired: false), isTrue);
    });

    test('recording that no weighing was possible drops that demand', () {
      // Without this the form asked for an egg from a block it had just taken
      // off the screen, and the inspection could not be saved at all.
      expect(EggValidation.samplesRequired(weighingNotRequired: true), isFalse);
    });
  });

  group('what the count column says', () {
    const tolerances = [
      DeviationTolerance(
          deviationId: 1, sizeId: 3, gradeId: 4, minimum: 0, maximum: 4),
      DeviationTolerance(
          deviationId: 2, sizeId: 3, gradeId: 4, minimum: 0, maximum: 100),
      DeviationTolerance(
          deviationId: 3, sizeId: 3, gradeId: 4, minimum: 60, maximum: 60),
    ];
    String label(int deviation, int count) => EggRules.toleranceLabel(
          count: count,
          deviationId: deviation,
          sizeId: 3,
          gradeId: 4,
          tolerances: tolerances,
        );

    test('a band is named beside the count', () {
      expect(label(1, 2), '2 of 4 allowed');
    });
    test('a band wider than the sample is no limit', () {
      expect(label(2, 7), '7 - no limit');
    });
    test('a band pinned to one value says so', () {
      expect(label(3, 1), '1 - exactly 60 allowed');
    });
    test('no band at all means any occurrence is a finding', () {
      expect(label(99, 1), '1 - not permitted');
      expect(
        EggRules.isDeviationPermissible(
            deviationId: 99, count: 1, sizeId: 3, gradeId: 4,
            tolerances: tolerances),
        isFalse,
      );
    });
  });
}
