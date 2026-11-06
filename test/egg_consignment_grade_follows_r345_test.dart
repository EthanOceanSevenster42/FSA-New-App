import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// The consignment grade, worked out as R.345 regulation 5 decides it:
/// Grade 1 when every Grade 1 limit of Table 4 (counted by Table 5) is met,
/// item 12's total included, else Grade 2, else Grade 3, else none (Ethan,
/// 2026-09-29). Checked against the Agency's own tolerance table.
void main() {
  late LocalDatabase db;
  late List<DeviationRef> deviations;
  late List<DeviationTolerance> tolerances;
  late List<EggGradeRef> grades;
  late int large;

  setUpAll(() async {
    db = LocalDatabase(NativeDatabase.memory());
    final eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    deviations = await eggs.deviationRefs();
    tolerances = await eggs.deviationTolerances();
    grades = await eggs.gradeRefs();
    large = (await eggs.sizeBands()).firstWhere((s) => s.name == 'Large').id;
  });
  tearDownAll(() => db.close());

  int id(String words) =>
      deviations.firstWhere((d) => d.description.contains(words)).id;

  /// A 60-egg sample: [defects] lists, per defective egg, what it has.
  String? gradeOf(List<List<String>> defects) {
    final perEgg = [
      for (final egg in defects) {for (final w in egg) id(w)},
      for (var i = defects.length; i < 60; i++) <int>{},
    ];
    final counts = <int, int>{};
    for (final egg in perEgg) {
      for (final d in egg) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    return EggRules.consignmentGradeFor(
      countsByDeviationId: counts,
      defectiveEggs: EggRules.defectiveEggs(perEgg, deviations),
      sampleSize: 60,
      sizeId: large,
      grades: grades,
      tolerances: tolerances,
    )?.name;
  }

  List<List<String>> times(int n, String words) => [
        for (var i = 0; i < n; i++) [words]
      ];

  test('a clean sample is Grade 1', () {
    expect(gradeOf(const []), 'Grade 1');
  });

  test('cracks with leakage: 1 is Grade 1, 2 Grade 2, 4 Grade 3, 5 none', () {
    expect(gradeOf(times(1, 'result in leakage')), 'Grade 1');
    expect(gradeOf(times(2, 'result in leakage')), 'Grade 2');
    expect(gradeOf(times(4, 'result in leakage')), 'Grade 3');
    expect(gradeOf(times(5, 'result in leakage')), isNull,
        reason: 'not even Grade 3: may not be sold (reg. 4(2))');
  });

  test('cracks without leakage: 4 is Grade 1, 5 Grade 2, more Grade 3', () {
    expect(gradeOf(times(4, 'do not in leakage')), 'Grade 1');
    expect(gradeOf(times(5, 'do not in leakage')), 'Grade 2');
    expect(gradeOf(times(9, 'do not in leakage')), 'Grade 3');
  });

  test('item 12: every defect within its limit, too many eggs in total', () {
    // 1 leaking crack, 4 unleaking, 2 nesting material: each within Grade 1,
    // but 7 eggs with defects where Grade 1 allows 6.
    final sample = [
      ...times(1, 'result in leakage'),
      ...times(4, 'do not in leakage'),
      ...times(2, 'nesting material'),
    ];
    expect(gradeOf(sample), 'Grade 2');
    expect(
        EggRules.totalDefectsExceeded(
            defectiveEggs: 7, gradeName: 'Grade 1', sampleSize: 60),
        isTrue);
    expect(
        EggRules.totalDefectsExceeded(
            defectiveEggs: 12, gradeName: 'Grade 2', sampleSize: 60),
        isFalse);
  });

  test('item 12 leaves out item 6, the Haugh values within five units', () {
    final sample = [
      ...times(6, 'Haugh Value at least 55/35 units, Not more than 5'),
      ...times(4, 'discolouration'),
      ...times(2, 'nesting material'),
    ];
    // 12 eggs with something, 6 of them only item 6: 6 counted, Grade 1.
    expect(gradeOf(sample), 'Grade 1');
  });

  test('Table 5 for a sample under 60 eggs', () {
    expect(EggRules.totalDefectsAllowed(gradeName: 'Grade 1', sampleSize: 30), 3);
    expect(EggRules.totalDefectsAllowed(gradeName: 'Grade 2', sampleSize: 30), 6);
    expect(EggRules.totalDefectsAllowed(gradeName: 'Grade 3', sampleSize: 60),
        isNull, reason: 'not specified for Grade 3');
  });
}
