import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// The albumen rule as the office states it (2026-10-20): "Haugh value must
/// be 55, and 5 unit deviation to 50; anything below 50 is a rejection."
///
/// Checked against the real reference data the handsets sync, not against
/// hand-written rows — the band is in the code but whether a shortfall ends
/// in a rejection is decided by the deviation tolerances, and those are the
/// office's data.
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;
  late List<DeviationRef> deviations;
  late List<DeviationTolerance> tolerances;
  late EggGradeRef grade1;
  late int largeSizeId;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    deviations = await eggs.deviationRefs();
    tolerances = await eggs.deviationTolerances();
    final grades = await eggs.gradeRefs();
    grade1 = grades.firstWhere((g) => g.name == 'Grade 1');
    largeSizeId =
        (await db.select(db.eggSizes).get()).firstWhere((s) => s.name == "Large").id;
  });
  tearDown(() async => db.close());

  Set<int> ticks(double haugh) => EggRules.autoAlbumenDeviationIds(
        haughUnit: haugh,
        declaredGrade: grade1,
        pasteurised: false,
        deviations: deviations,
      );

  bool rejects(double haugh, {int eggs = 1}) {
    final ids = ticks(haugh);
    return EggRules.isQualityDirectionRequired(
      countsByDeviationId: {for (final id in ids) id: eggs},
      sizeId: largeSizeId,
      gradeId: grade1.id,
      tolerances: tolerances,
    );
  }

  test('55 and above is clean', () {
    expect(ticks(55), isEmpty);
    expect(ticks(70), isEmpty);
    expect(rejects(55), isFalse);
  });

  test('54 down to 50 is a deviation inside the 5-unit band', () {
    for (final h in [54.0, 52.0, 50.5, 50.0]) {
      final ids = ticks(h);
      expect(ids, hasLength(1), reason: 'Haugh $h should tick one row');
      expect(
        deviations.firstWhere((d) => d.id == ids.single).description,
        contains('Not more than 5 units lower'),
        reason: 'Haugh $h is within the band',
      );
    }
    // 50 exactly is still the tolerance, not a rejection.
    expect(rejects(50), isFalse);
  });

  test('below 50 is a rejection, on a single egg', () {
    for (final h in [49.9, 45.0, 20.0]) {
      final ids = ticks(h);
      expect(
        deviations.firstWhere((d) => d.id == ids.single).description,
        contains('More than 5 units lower'),
        reason: 'Haugh $h is past the band',
      );
      expect(rejects(h), isTrue,
          reason: 'Haugh $h must reject even on one egg');
    }
  });

  test('the band itself only rejects once too many eggs are in it', () {
    // Grade 1 allows six eggs inside the band; the seventh fails the
    // consignment.
    expect(rejects(52, eggs: 6), isFalse);
    expect(rejects(52, eggs: 7), isTrue);
  });
}
