import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// The egg form said "Consignment grade: Not determined" on every
/// inspection: no deviation in the Agency's list names a grade it drops an
/// egg to, so none was ever worked out. It now says whether the sample meets
/// the size and grade it is sold as, and names the deviations over their
/// limit (Ethan, 2026-09-29).
void main() {
  const tolerances = [
    DeviationTolerance(
        deviationId: 1, sizeId: 3, gradeId: 4, minimum: 0, maximum: 4),
    DeviationTolerance(
        deviationId: 2, sizeId: 3, gradeId: 4, minimum: 0, maximum: 100),
  ];

  List<({int deviationId, int count, int? allowed})> over(Map<int, int> counts) =>
      EggRules.overLimit(
        countsByDeviationId: counts,
        sizeId: 3,
        gradeId: 4,
        tolerances: tolerances,
      );

  test('a sample within every band has nothing over the limit', () {
    expect(over({1: 4, 2: 30}), isEmpty);
  });

  test('a deviation past its band is named, with what is allowed', () {
    expect(over({1: 5, 2: 30}), [(deviationId: 1, count: 5, allowed: 4)]);
  });

  test('a deviation with no band allows none', () {
    expect(over({9: 1}), [(deviationId: 9, count: 1, allowed: null)]);
  });

  test('the causes agree with whether a rejection is required', () {
    for (final counts in [
      {1: 4},
      {1: 5},
      {9: 1},
      {2: 100},
    ]) {
      expect(
        over(counts).isNotEmpty,
        EggRules.isQualityDirectionRequired(
          countsByDeviationId: counts,
          sizeId: 3,
          gradeId: 4,
          tolerances: tolerances,
        ),
        reason: '$counts',
      );
    }
  });
}
