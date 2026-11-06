import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Which eggs carry the Haugh reading is the app's choice, not the
/// inspector's.
///
/// Six eggs picked by hand are the easy six — the front of the tray, or six
/// that look sound — and that is not a sample of the consignment. Six drawn
/// across the whole set is. The number required is unchanged at six
/// (Ethan, 2026-10-23).
void main() {
  group('the draw', () {
    test('takes exactly the six the rule asks for', () {
      final eggs = EggRules.haughSample(sampleSize: 60, seed: 1);
      expect(eggs, hasLength(EggRules.haughReadingsRequired));
      expect(eggs.toSet(), hasLength(6), reason: 'no egg twice');
    });

    test('every egg is inside the set', () {
      for (var seed = 0; seed < 200; seed++) {
        final eggs = EggRules.haughSample(sampleSize: 60, seed: seed);
        expect(eggs.every((e) => e >= 1 && e <= 60), isTrue,
            reason: 'seed $seed produced $eggs');
        expect(eggs.toSet(), hasLength(6), reason: 'seed $seed');
      }
    });

    test('comes back in tray order, so the inspector works forwards', () {
      for (var seed = 0; seed < 50; seed++) {
        final eggs = EggRules.haughSample(sampleSize: 60, seed: seed);
        final sorted = [...eggs]..sort();
        expect(eggs, sorted, reason: 'seed $seed');
      }
    });

    test('spreads across the tray instead of clustering', () {
      // One egg per tenth of the set: the first below 11, the last above 50.
      for (var seed = 0; seed < 50; seed++) {
        final eggs = EggRules.haughSample(sampleSize: 60, seed: seed);
        expect(eggs.first, lessThanOrEqualTo(11), reason: 'seed $seed');
        expect(eggs.last, greaterThan(50), reason: 'seed $seed');
      }
    });

    test('the same seed draws the same eggs, so a reopened record is '
        'asked the same question', () {
      expect(EggRules.haughSample(sampleSize: 60, seed: 77),
          EggRules.haughSample(sampleSize: 60, seed: 77));
    });

    test('different seeds generally draw different eggs', () {
      final draws = {
        for (var seed = 0; seed < 40; seed++)
          EggRules.haughSample(sampleSize: 60, seed: seed).join(',')
      };
      expect(draws.length, greaterThan(20),
          reason: 'the draw should actually vary');
    });
  });

  group('small or odd sets', () {
    test('a set no bigger than six is taken whole', () {
      expect(EggRules.haughSample(sampleSize: 6, seed: 3), [1, 2, 3, 4, 5, 6]);
      expect(EggRules.haughSample(sampleSize: 4, seed: 3), [1, 2, 3, 4]);
    });

    test('nothing to draw from yields nothing', () {
      expect(EggRules.haughSample(sampleSize: 0, seed: 1), isEmpty);
      expect(EggRules.haughSample(sampleSize: 60, count: 0, seed: 1), isEmpty);
    });

    test('an extra six can be asked for', () {
      final eggs = EggRules.haughSample(sampleSize: 60, count: 12, seed: 5);
      expect(eggs, hasLength(12));
      expect(eggs.toSet(), hasLength(12));
    });
  });

  group('what is still owed', () {
    test('names only the chosen eggs that have no reading', () {
      expect(
        EggRules.haughOutstanding(
          selected: [3, 14, 25, 36, 47, 58],
          readings: {3: 78.0, 14: null, 25: 0.0, 36: 81.2},
        ),
        [14, 25, 36, 47, 58].where((e) => e != 36).toList(),
      );
    });

    test('a full set owes nothing', () {
      expect(
        EggRules.haughOutstanding(
          selected: [1, 2],
          readings: {1: 70.0, 2: 65.5},
        ),
        isEmpty,
      );
    });
  });
}
