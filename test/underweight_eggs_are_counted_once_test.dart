// Hellen, 2026-10-21: "only 5 eggs underweight but 7 is showing — 3 eggs in
// the 2 g deviation and 2 eggs more than 2 g deviation ... It is counting of
// all the eggs in 2 g deviation."
//
// The claim is that an egg more than 2 g under the minimum is tallied on the
// "<= 2g of Min. Weight" row as well as on "Egg Weight Difference >= 2g", so
// five underweight eggs show as seven ticks. The two rows must be exclusive:
// each underweight egg lands on exactly one of them.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late EggsRepository eggs;
  late List<EggSizeBand> bands;
  late List<DeviationRef> deviations;
  late List<EggGradeRef> grades;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    bands = await eggs.sizeBands();
    deviations = await eggs.deviationRefs();
    grades = await eggs.gradeRefs();
  });
  tearDown(() async => db.close());

  String descriptionOf(int id) =>
      deviations.firstWhere((d) => d.id == id).description;

  /// The tally the form builds: one count per deviation, per egg.
  Map<String, int> tally(List<double> masses, String sizeName) {
    final size = bands.firstWhere((b) => b.name == sizeName);
    final grade1 = grades.firstWhere((g) => g.name == 'Grade 1');
    final counts = <String, int>{};
    for (final mass in masses) {
      final ids = EggRules.autoWeightDeviationIds(
        massG: mass,
        declaredSize: size,
        declaredGrade: grade1,
        deviations: deviations,
      );
      for (final id in ids) {
        counts[descriptionOf(id)] = (counts[descriptionOf(id)] ?? 0) + 1;
      }
    }
    return counts;
  }

  test('three eggs within 2 g and two beyond are five ticks, not seven', () {
    // Extra Large: minimum 59 g.
    final masses = <double>[
      58.0, 57.5, 57.0, // within 2 g of the minimum
      55.0, 54.0, //       more than 2 g under
      ...List<double>.filled(55, 62.0), // the rest are fine
    ];
    final counts = tally(masses, 'Extra Large');

    expect(counts['Extra Large - <= 2g of Min. Weight'], 3,
        reason: 'only the eggs inside the band');
    expect(counts['Egg Weight Difference >= 2g'], 2);
    expect(counts.values.fold<int>(0, (a, b) => a + b), 5,
        reason: 'five underweight eggs, five ticks');
  });

  test('an egg beyond the band is not also on the within-band row', () {
    final size = bands.firstWhere((b) => b.name == 'Extra Large');
    final ids = EggRules.autoWeightDeviationIds(
      massG: 54.0, // 5 g under
      declaredSize: size,
      declaredGrade: grades.firstWhere((g) => g.name == 'Grade 1'),
      deviations: deviations,
    );
    expect(ids, hasLength(1));
    expect(descriptionOf(ids.single), 'Egg Weight Difference >= 2g');
  });

  test('exactly 2 g under stays on the within-band row', () {
    final size = bands.firstWhere((b) => b.name == 'Extra Large');
    final ids = EggRules.autoWeightDeviationIds(
      massG: 57.0, // exactly 2 g under
      declaredSize: size,
      declaredGrade: grades.firstWhere((g) => g.name == 'Grade 1'),
      deviations: deviations,
    );
    expect(ids, hasLength(1));
    expect(descriptionOf(ids.single), 'Extra Large - <= 2g of Min. Weight');
  });

  // Her screen read "5 of 2 allowed" on the band row and "2 of 0 allowed" on
  // the over-band row. That is seven *eggs*, not five eggs and two double
  // counts: five between 57.00 and 59.00 g inclusive, two under 57.00 g.
  test("the screen's 5 and 2 are seven separate eggs", () {
    final masses = <double>[
      58.34, 58.03, 57.13, 57.77, 59.00, // five within 2 g (59.00 included)
      56.86, 55.20, //                      two more than 2 g under
      ...List<double>.filled(52, 61.0),
    ];
    final counts = tally(masses, 'Extra Large');
    expect(counts['Extra Large - <= 2g of Min. Weight'], 5);
    expect(counts['Egg Weight Difference >= 2g'], 2);
    expect(counts.values.fold<int>(0, (a, b) => a + b), 7,
        reason: 'seven eggs, seven ticks — one row each');
  });

  // R.345 Table 2, gazette 43108 p.28, reads "Extra large — More than 59 g".
  // An egg of exactly 59.00 g is therefore NOT Extra Large, and ticking it is
  // the regulation, not a fault. This is the likeliest reason an inspector
  // counts five underweight eggs where the app counts seven.
  test('an egg exactly on the minimum is a deviation, per R.345 Table 2', () {
    final counts = tally([59.00, 59.01, 61.0], 'Extra Large');
    expect(counts['Extra Large - <= 2g of Min. Weight'], 1,
        reason: '"More than 59 g" — 59.00 g does not make the size, '
            'but 59.01 g does');
  });

  test('every size keeps the two rows exclusive', () {
    for (final size in bands) {
      if (size.name == 'Small') continue; // excluded from the band by design
      final min = size.minMassG;
      final counts = tally([min - 1, min - 1.5, min - 3, min - 4], size.name);
      expect(counts['Egg Weight Difference >= 2g'], 2,
          reason: '${size.name}: two eggs beyond the band');
      final within = counts.entries
          .where((e) => e.key.contains('<= 2g of Min. Weight'))
          .fold<int>(0, (a, e) => a + e.value);
      expect(within, 2, reason: '${size.name}: two eggs inside the band');
    }
  });
}
