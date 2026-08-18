import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/fruitveg/domain/grading_engine.dart';

/// Bands matching the seeded backend: Decay 1/2/5%, Bruising 5/10/15%.
const _decay = 1;
const _bruising = 2;

List<Tolerance> _tolerances() => const [
      Tolerance(
        defectGroupId: _decay,
        gradeId: 1,
        gradeRank: 1,
        gradeName: 'Class 1',
        maxPercentage: 1,
      ),
      Tolerance(
        defectGroupId: _decay,
        gradeId: 2,
        gradeRank: 2,
        gradeName: 'Class 2',
        maxPercentage: 2,
      ),
      Tolerance(
        defectGroupId: _decay,
        gradeId: 3,
        gradeRank: 3,
        gradeName: 'Class 3',
        maxPercentage: 5,
      ),
      Tolerance(
        defectGroupId: _bruising,
        gradeId: 1,
        gradeRank: 1,
        gradeName: 'Class 1',
        maxPercentage: 5,
      ),
      Tolerance(
        defectGroupId: _bruising,
        gradeId: 2,
        gradeRank: 2,
        gradeName: 'Class 2',
        maxPercentage: 10,
      ),
      Tolerance(
        defectGroupId: _bruising,
        gradeId: 3,
        gradeRank: 3,
        gradeName: 'Class 3',
        maxPercentage: 15,
      ),
    ];

DefectMeasurement _counted(int groupId, int count, [String name = 'Decay']) =>
    DefectMeasurement(
      defectGroupId: groupId,
      defectGroupName: name,
      count: count,
    );

void main() {
  group('percentage conversion', () {
    test('counted defects divide by unit count', () {
      expect(
        GradingEngine.percentageFor(
          defect: _counted(_decay, 3),
          sampleUnitCount: 100,
        ),
        3.0,
      );
    });

    test('weighed defects divide by sample mass', () {
      expect(
        GradingEngine.percentageFor(
          defect: const DefectMeasurement(
            defectGroupId: 1,
            defectGroupName: 'Internal decay',
            weightG: 250,
          ),
          sampleWeightG: 5000,
        ),
        5.0,
      );
    });

    test('a missing denominator yields null, never a clean 0%', () {
      // Scoring an unmeasurable defect as 0% would pass a bad consignment.
      expect(
        GradingEngine.percentageFor(
          defect: _counted(_decay, 3),
          sampleUnitCount: null,
        ),
        isNull,
      );
      expect(
        GradingEngine.percentageFor(
          defect: _counted(_decay, 3),
          sampleUnitCount: 0,
        ),
        isNull,
      );
    });
  });

  group('grading', () {
    test('a clean sample takes the best available class', () {
      final r = GradingEngine.grade(
        defects: const [],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.gradeName, 'Class 1');
      expect(r.isDetermined, isTrue);
    });

    test('exactly on a tolerance boundary stays in that class', () {
      // 1% decay with a Class 1 limit of 1% must be Class 1, not Class 2.
      final r = GradingEngine.grade(
        defects: [_counted(_decay, 1)],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.gradeName, 'Class 1');
    });

    test('just over a boundary drops a class', () {
      final r = GradingEngine.grade(
        defects: [_counted(_decay, 2)],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.gradeName, 'Class 2');
    });

    test('the worst defect group decides the overall class', () {
      // Out of 100 units: decay 1% is Class 1, bruising 12% is Class 3
      // (over the 10% Class 2 band). The worst wins.
      final r = GradingEngine.grade(
        defects: [
          _counted(_decay, 1, 'Decay'),
          _counted(_bruising, 12, 'Bruising'),
        ],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.gradeName, 'Class 3');
    });

    test('a good group cannot pull the class back up', () {
      // Same sample at 200 units: bruising is 6%, which is Class 2.
      final r = GradingEngine.grade(
        defects: [
          _counted(_decay, 1, 'Decay'),
          _counted(_bruising, 12, 'Bruising'),
        ],
        tolerances: _tolerances(),
        sampleUnitCount: 200,
      );
      expect(r.gradeName, 'Class 2');
    });

    test('exceeding every band yields the lowest class, not an error', () {
      final r = GradingEngine.grade(
        defects: [_counted(_decay, 50)],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.gradeName, 'Class 3');
      expect(r.reasons.first.toleranceApplied, isNull);
    });

    test('no tolerance data refuses to grade rather than guessing', () {
      final r = GradingEngine.grade(
        defects: [_counted(_decay, 5)],
        tolerances: const [],
        sampleUnitCount: 100,
      );
      expect(r.isDetermined, isFalse);
      expect(r.gradeId, isNull);
    });

    test('a defect with no matching rule is reported, not ignored', () {
      final r = GradingEngine.grade(
        defects: [_counted(99, 5, 'Unmapped defect')],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.reasons.single.gradeName, 'No rule');
      // It must not silently downgrade the consignment either.
      expect(r.gradeName, 'Class 1');
    });

    test('unmeasurable defects do not affect the class', () {
      final r = GradingEngine.grade(
        defects: [_counted(_decay, 5)],
        tolerances: _tolerances(),
        sampleUnitCount: null,
      );
      expect(r.gradeName, 'Class 1');
      expect(r.percentages, isEmpty);
    });

    test('reasons are ordered worst percentage first', () {
      final r = GradingEngine.grade(
        defects: [
          _counted(_decay, 1, 'Decay'),
          _counted(_bruising, 20, 'Bruising'),
        ],
        tolerances: _tolerances(),
        sampleUnitCount: 100,
      );
      expect(r.reasons.first.defectGroupName, 'Bruising');
      expect(r.reasons.last.defectGroupName, 'Decay');
    });
  });
}
