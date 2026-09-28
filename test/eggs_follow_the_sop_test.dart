import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Eggs follow FSA-SOP-APS-001 Annexure D (Ethan, 2026-09-26): each failed
/// requirement fixes the rectification period, an omission of the "Eggs"
/// expression or the best-before date is a seizure, and a sample failing
/// the size or grade standard is seized or put right at once.
EggRequirement row(int id, String kind, String description) => EggRequirement(
      id: id,
      kind: kind,
      description: description,
      regulation: '',
      screenLabel: '',
      sortOrder: id,
      isActive: true,
      updatedAt: '',
    );

void main() {
  final designation =
      row(2, 'label_pack', 'Inner Container-Indication of Sizes and Grade Designation');
  final eggs = row(3, 'label_pack',
      'Inner Container-The Expressions: Eggs, Cage, Barn or Free Range*, Pasteurised');
  final packer = row(4, 'label_pack', 'Inner Container-Indication of Packer');
  final species = row(5, 'label_pack',
      'Inner Container-Indication of the Name of the Specie of Poultry');
  final bestBefore = row(6, 'label_pack',
      'Inner Container-Indication of "Best Before", "Best Quality Before" or Abbreviation');
  final oiled = row(7, 'label_pack', 'Inner Container-Expression "oiled"');
  final origin = row(8, 'label_pack', 'Inner Container-Name of the Country Of Origin');
  final loose = row(9, 'label_pack',
      'Inner Container-Indication of Size and Grade in the Case of Sale in Loose Quantities');
  final flock = row(10, 'label_pack',
      'Inner Container-Indication that the flock has been confined');
  final restricted = row(11, 'label_pack', 'Inner Container-Restricted Particulars');
  final packing = row(22, 'packing', 'Be intact and suitable for purpose');

  EggAction action(EggRequirement r,
          {bool eggsAbsent = false, bool bestBeforeAbsent = false}) =>
      EggRules.actionForRequirement(r,
          eggsExpressionAbsent: eggsAbsent, bestBeforeAbsent: bestBeforeAbsent);

  group('Annexure D, row by row', () {
    test('container and packing rows are put right immediately', () {
      expect(action(packing), EggAction.rectifyNow);
    });

    test('"Eggs" omitted is a seizure; shown but wrong is 30 days', () {
      expect(action(eggs, eggsAbsent: true), EggAction.seize);
      expect(action(eggs), EggAction.rectify30Days);
    });

    test('best-before omitted is a seizure; shown but wrong is 30 days', () {
      expect(action(bestBefore, bestBeforeAbsent: true), EggAction.seize);
      expect(action(bestBefore), EggAction.rectify30Days);
    });

    test('country of origin (imported eggs) is 3 days', () {
      expect(action(origin), EggAction.rectify3Days);
    });

    test('loose quantities are seized or put right at once', () {
      expect(action(loose), EggAction.seizeOrRectifyNow);
      expect(EggRules.daysFor(EggAction.seizeOrRectifyNow), 0);
    });

    test('packer, species, oiled, production method, restricted particulars '
        'and the designation shown wrong are 30 days', () {
      for (final r in [packer, species, oiled, flock, restricted, designation]) {
        expect(action(r), EggAction.rectify30Days, reason: r.description);
      }
    });
  });

  group('what the rejection carries', () {
    test('the labelling period is the shortest among the failed rows', () {
      expect(
          EggRules.labellingRectificationDays(
            failed: [packer, origin],
            eggsExpressionAbsent: false,
            bestBeforeAbsent: false,
          ),
          3);
      expect(
          EggRules.labellingRectificationDays(
            failed: [packer, restricted],
            eggsExpressionAbsent: false,
            bestBeforeAbsent: false,
          ),
          30);
      expect(
          EggRules.labellingRectificationDays(
            failed: const [],
            eggsExpressionAbsent: false,
            bestBeforeAbsent: false,
          ),
          isNull);
    });

    test('a designation omitted altogether runs from today', () {
      expect(
          EggRules.labellingRectificationDays(
            failed: [packer],
            eggsExpressionAbsent: false,
            bestBeforeAbsent: false,
            designationOmitted: true,
          ),
          0);
    });

    test('quality standards are immediate', () {
      expect(EggRules.qualityRectificationDays, 0);
      expect(
          EggRules.correctBy(
              inspectedAt: DateTime(2026, 9, 26, 15, 40), days: 30),
          DateTime(2026, 10, 26));
      expect(EggRules.periodLabel(0), 'Rectify immediately');
      expect(EggRules.periodLabel(3), '3-day rectification notice');
    });
  });

  group('the seizure question', () {
    test('is raised by the new omissions and by a failed standard', () {
      expect(
          EggRules.seizureReasons(
            sizeNotIndicated: false,
            gradeNotIndicated: false,
            trayNotIndicated: false,
            eggsExpressionAbsent: true,
            bestBeforeAbsent: true,
            looseQuantityFailed: true,
            qualityStandardFailed: true,
          ),
          hasLength(4));
      expect(
          EggRules.seizureRequired(
            sizeNotIndicated: false,
            gradeNotIndicated: false,
            trayNotIndicated: false,
            bestBeforeAbsent: true,
          ),
          isTrue);
    });

    test('a wrong indication alone is not a seizure', () {
      expect(
          EggRules.seizureRequired(
            sizeNotIndicated: false,
            gradeNotIndicated: false,
            trayNotIndicated: false,
          ),
          isFalse);
    });
  });
}
