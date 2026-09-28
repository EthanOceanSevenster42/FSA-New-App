import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/poultry/domain/quid_determination.dart';

/// The arithmetic the QUID inspection turns on.
///
/// Taken from the original application, which is the only statement of it
/// that the Agency has been working to: `DoCurrentSampleQUIDPercentCalulation`
/// for the per-carcass figure and `DoOverallInjectorQUIDPercentageCalculat`
/// `ionsV2` for the finding, with the limits from its `Constants`.
void main() {
  group('a carcass', () {
    test('gains over the mass it comes off at, not the mass it went on at',
        () {
      // 1403 g on, 1508 g off: 105 g over 1508, not over 1403. The
      // regulation is explicit, and the two differ by enough to turn a pass
      // into a failure near the limit.
      expect(quidPercentOf(1403, 1508), '6.963');
      expect(quidPercentOf(1403, 1508), isNot('7.484'));
    });

    test('is blank, never zero, until both masses are on it', () {
      expect(quidPercentOf(null, 1508), '');
      expect(quidPercentOf(1403, null), '');
      expect(quidPercentOf(1403, 0), '');
    });
  });

  group('an injector', () {
    QuidInjectorVerdict judge(
      List<String> percentages, {
      String setPercent = '8.0',
      bool isWholeCarcass = true,
    }) =>
        quidVerdicts(
          injectors: [(position: 1, name: 'Brine 1', quidPercent: setPercent)],
          weighings: [
            for (final p in percentages)
              (assignedInjector: 1, quidPercent: p),
          ],
          isWholeCarcass: isWholeCarcass,
        ).single;

    test('is judged on five carcasses, not fewer', () {
      final four = judge(const ['20', '20', '20', '20']);
      expect(four.hasSufficientSamples, isFalse);
      // Well over any limit, and still no finding: the original greys the
      // figure out rather than failing a plant on too little.
      expect(four.passes, isNull);
      expect(four.verdict, contains('5'));

      expect(judge(const ['20', '20', '20', '20', '20']).passes, isFalse);
    });

    test('may run one percent over its setting on whole carcasses', () {
      const five = ['8.9', '8.9', '8.9', '8.9', '8.9'];
      expect(judge(five).limitPercent, 9.0);
      expect(judge(five).passes, isTrue);
      expect(judge(const ['9.1', '9.1', '9.1', '9.1', '9.1']).passes, isFalse);
    });

    test('may run two and a half percent over on portions', () {
      final cuts = judge(
        const ['10.4', '10.4', '10.4', '10.4', '10.4'],
        isWholeCarcass: false,
      );
      expect(cuts.limitPercent, 10.5);
      expect(cuts.passes, isTrue);
    });

    test('falls back to the regulated maximum when it carries no setting', () {
      // Nothing entered against the injector, so the regulation's own figure
      // stands in — 10% whole carcass, 15% portions.
      expect(judge(const ['1'], setPercent: '').limitPercent, 10.0);
      expect(
        judge(const ['1'], setPercent: '', isWholeCarcass: false).limitPercent,
        15.0,
      );
    });

    test('counts only the carcasses that ran through it', () {
      final verdicts = quidVerdicts(
        injectors: [
          (position: 1, name: 'Brine 1', quidPercent: '8.0'),
          (position: 2, name: 'Brine 2', quidPercent: '8.0'),
        ],
        weighings: const [
          (assignedInjector: 1, quidPercent: '7.5'),
          (assignedInjector: 1, quidPercent: '7.5'),
          (assignedInjector: 2, quidPercent: '12.1'),
          // Never assigned: it cannot be traced to an injector, so it counts
          // toward neither average.
          (assignedInjector: null, quidPercent: '99.0'),
        ],
        isWholeCarcass: true,
      );
      expect(verdicts.first.sampleCount, 2);
      expect(verdicts.first.averagePercent, '7.500');
      expect(verdicts.last.sampleCount, 1);
      expect(verdicts.last.averagePercent, '12.100');
    });

    test('is not dragged down by carcasses still being weighed', () {
      // Three weighed, two blank. The mean is of the three, not of five with
      // two zeros in them.
      expect(quidMean(const ['9', '9', '9', '', '']), '9.000');
      expect(quidMean(const ['', '']), '');
    });

    test('reads a figure that carries a stray percent sign', () {
      expect(judge(const ['8.5%', '8.5', '8.5', '8.5', '8.5']).passes, isTrue);
    });
  });
}
