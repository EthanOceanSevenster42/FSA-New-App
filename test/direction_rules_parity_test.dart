import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Proves the direction rules answer the same as the original's own tables.
///
/// The rules that decide whether a direction must be served were never
/// reimplemented from a specification — there isn't one. They were read out of
/// a 7,000-line Xamarin code-behind, which is exactly the kind of source where
/// a rule can be transcribed plausibly and wrongly. So rather than assert a
/// handful of examples, this replays the original's whole tolerance table:
/// every deviation, at every declared size and grade, at every count either
/// side of its band.
///
/// The fixture is generated, not written:
///
///     python manage.py extract_original_rules      # in fsa_backend
///
/// The oracle below is a deliberately literal transcription of the one line
/// the original decides this on, so a disagreement means our implementation
/// has drifted from it — not that both were changed together.
///
///     int maxValue = poultryEggRules
///         .Where(o => o.DeviationTypeId == entry.DeviationId)
///         .Select(o => o.MaximumValue).FirstOrDefault();
///     …
///     if (entry.Count < minValue || entry.Count > maxValue)
///         IsNonPermissiableDeviationPresent = true;
///
/// where `poultryEggRules` was already narrowed to the consignment's declared
/// size and grade, and `FirstOrDefault()` yields 0 for a combination the table
/// does not list.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/original_direction_rules.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  List<Map<String, dynamic>> rows(String key) =>
      (fixture[key] as List<dynamic>).cast<Map<String, dynamic>>();

  final tolerances = [
    for (final t in rows('deviation_tolerances'))
      DeviationTolerance(
        deviationId: t['deviation'] as int,
        sizeId: t['size_group'] as int,
        gradeId: t['grade'] as int,
        minimum: t['minimum'] as int,
        maximum: t['maximum'] as int,
      ),
  ];

  final sizeIds = [for (final s in rows('sizes')) s['id'] as int];
  final gradeIds = [for (final g in rows('grades')) g['id'] as int];
  final deviationIds = [for (final d in rows('deviations')) d['id'] as int];

  /// The original's lookup, transcribed: narrow to size and grade, take the
  /// first row for the deviation, and treat a miss as a band of 0–0.
  ({int minimum, int maximum}) band(int deviationId, int sizeId, int gradeId) {
    for (final t in rows('deviation_tolerances')) {
      if (t['deviation'] == deviationId &&
          t['size_group'] == sizeId &&
          t['grade'] == gradeId) {
        return (minimum: t['minimum'] as int, maximum: t['maximum'] as int);
      }
    }
    return (minimum: 0, maximum: 0);
  }

  bool oracleIsPermissible(int deviationId, int count, int sizeId, int gradeId) {
    if (count <= 0) return true; // The original only tests deviations present.
    final b = band(deviationId, sizeId, gradeId);
    return !(count < b.minimum || count > b.maximum);
  }

  group('the tolerance table is intact', () {
    test('every declared size and grade is fully covered, or knowingly not',
        () {
      final keyed = {
        for (final t in tolerances) (t.sizeId, t.gradeId, t.deviationId): t,
      };
      expect(keyed.length, tolerances.length,
          reason: 'a duplicate key would make the answer depend on row order');
      expect(tolerances.length, 630);

      // 147 of the 777 possible combinations carry no rule. Those deny on any
      // occurrence, which is the safe direction to fail in — but it is a real
      // behaviour, so it is pinned rather than left to be discovered.
      final possible = sizeIds.length * gradeIds.length * deviationIds.length;
      expect(possible, 777);
      expect(possible - keyed.length, 147);
    });
  });

  group('a deviation count against its tolerance', () {
    test('agrees with the original for every combination and every count', () {
      var checked = 0;
      final disagreements = <String>[];

      for (final sizeId in sizeIds) {
        for (final gradeId in gradeIds) {
          for (final deviationId in deviationIds) {
            final b = band(deviationId, sizeId, gradeId);
            // Either side of the band, so an off-by-one cannot pass.
            for (var count = 0; count <= b.maximum + 2; count++) {
              final expected =
                  oracleIsPermissible(deviationId, count, sizeId, gradeId);
              final actual = EggRules.isDeviationPermissible(
                deviationId: deviationId,
                count: count,
                sizeId: sizeId,
                gradeId: gradeId,
                tolerances: tolerances,
              );
              checked++;
              if (actual != expected) {
                disagreements.add(
                  'deviation $deviationId size $sizeId grade $gradeId '
                  'count $count: expected $expected, got $actual',
                );
              }
            }
          }
        }
      }

      expect(disagreements, isEmpty);
      // Guards the loop itself: a bad fixture that silently produced no
      // combinations would otherwise pass this test.
      expect(checked, greaterThan(10000));
    });

    test('zero occurrences is never a finding', () {
      for (final deviationId in deviationIds) {
        expect(
          EggRules.isDeviationPermissible(
            deviationId: deviationId,
            count: 0,
            sizeId: sizeIds.first,
            gradeId: gradeIds.first,
            tolerances: tolerances,
          ),
          isTrue,
        );
      }
    });

    test('a combination with no rule denies on a single occurrence', () {
      final keyed = {
        for (final t in tolerances) (t.sizeId, t.gradeId, t.deviationId)
      };
      final uncovered = [
        for (final s in sizeIds)
          for (final g in gradeIds)
            for (final d in deviationIds)
              if (!keyed.contains((s, g, d))) (s, g, d),
      ];
      expect(uncovered, isNotEmpty);

      for (final (s, g, d) in uncovered) {
        expect(
          EggRules.isDeviationPermissible(
            deviationId: d,
            count: 1,
            sizeId: s,
            gradeId: g,
            tolerances: tolerances,
          ),
          isFalse,
          reason: 'size $s grade $g deviation $d has no rule, so any '
              'occurrence must be a finding',
        );
      }
    });
  });

  group('the quality part of a direction', () {
    test('is not required when every deviation is inside its band', () {
      final within = <int, int>{};
      for (final t in tolerances) {
        if (t.sizeId == 1 && t.gradeId == 1) within[t.deviationId] = t.maximum;
      }
      expect(within, isNotEmpty);

      expect(
        EggRules.isQualityDirectionRequired(
          countsByDeviationId: within,
          sizeId: 1,
          gradeId: 1,
          tolerances: tolerances,
        ),
        isFalse,
      );
    });

    test('is required as soon as one deviation exceeds its band', () {
      final counts = <int, int>{};
      for (final t in tolerances) {
        if (t.sizeId == 1 && t.gradeId == 1) counts[t.deviationId] = t.maximum;
      }
      final first = counts.keys.first;
      counts[first] = counts[first]! + 1;

      expect(
        EggRules.isQualityDirectionRequired(
          countsByDeviationId: counts,
          sizeId: 1,
          gradeId: 1,
          tolerances: tolerances,
        ),
        isTrue,
      );
    });

    test('an inspection with no deviations at all needs no direction', () {
      expect(
        EggRules.isQualityDirectionRequired(
          countsByDeviationId: const {},
          sizeId: 1,
          gradeId: 1,
          tolerances: tolerances,
        ),
        isFalse,
      );
    });
  });

  group('the labelling part of a direction', () {
    final groups = fixture['label_groups'] as Map<String, dynamic>;
    final members = groups['members'] as Map<String, dynamic>;

    Set<int> ids(String key) =>
        {for (final v in members[key] as List<dynamic>) v as int};

    final checklists = {
      LabelChecklist.innerLabel: ids('inner_label'),
      LabelChecklist.outerLabel: ids('outer_label'),
      LabelChecklist.container: ids('container'),
    };

    test('each checklist holds exactly as many boxes as its mask has bits', () {
      final masks = groups['pass_masks'] as Map<String, dynamic>;
      for (final entry in {
        'inner_label': LabelChecklist.innerLabel,
        'outer_label': LabelChecklist.outerLabel,
        'container': LabelChecklist.container,
      }.entries) {
        final mask = int.parse(
          (masks[entry.key] as String).replaceFirst('0x', ''),
          radix: 16,
        );
        final bits = mask.toRadixString(2).split('').where((c) => c == '1').length;
        expect(bits, checklists[entry.value]!.length,
            reason: 'the original passes ${entry.key} only on mask '
                '${masks[entry.key]}, which is $bits ticked boxes');
      }
    });

    test('an untouched inspection needs no labelling direction', () {
      // The original starts every box ticked — "set this to initial pass
      // conditions" — so silence is compliance, not an unanswered question.
      expect(
        EggRules.isLabelDirectionRequired(
          failedRequirementIds: const {},
          checklists: checklists,
        ),
        isFalse,
      );
    });

    test('any one failed requirement requires it, on every checklist', () {
      for (final list in checklists.values) {
        for (final id in list) {
          expect(
            EggRules.isLabelDirectionRequired(
              failedRequirementIds: {id},
              checklists: checklists,
            ),
            isTrue,
            reason: 'requirement $id failing must raise a direction',
          );
        }
      }
    });

    test('a requirement outside every checklist does not raise one', () {
      expect(
        EggRules.isLabelDirectionRequired(
          failedRequirementIds: const {9999},
          checklists: checklists,
        ),
        isFalse,
      );
    });
  });

  group('both parts together', () {
    final groups = fixture['label_groups'] as Map<String, dynamic>;
    final members = groups['members'] as Map<String, dynamic>;
    Set<int> ids(String key) =>
        {for (final v in members[key] as List<dynamic>) v as int};
    final checklists = {
      LabelChecklist.innerLabel: ids('inner_label'),
      LabelChecklist.outerLabel: ids('outer_label'),
      LabelChecklist.container: ids('container'),
    };

    test('a clean inspection serves no direction', () {
      final result = EggRules.directionRequired(
        countsByDeviationId: const {},
        sizeId: 1,
        gradeId: 1,
        tolerances: tolerances,
        failedRequirementIds: const {},
        checklists: checklists,
      );

      expect(result.quality, isFalse);
      expect(result.labelling, isFalse);
      expect(result.any, isFalse);
    });

    test('failing both is one direction carrying both parts', () {
      // The distinction that matters: this is a single document with two
      // deadlines, not two directions.
      final result = EggRules.directionRequired(
        countsByDeviationId: {deviationIds.first: 999},
        sizeId: 1,
        gradeId: 1,
        tolerances: tolerances,
        failedRequirementIds: {ids('outer_label').first},
        checklists: checklists,
      );

      expect(result.quality, isTrue);
      expect(result.labelling, isTrue);
      expect(result.any, isTrue);
    });
  });
}
