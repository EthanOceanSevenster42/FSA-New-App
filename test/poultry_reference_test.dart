import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';

/// The rules that ship inside the app.
///
/// A handset must be able to capture a grading inspection before it has ever
/// reached the server, so the bundled asset is not a convenience — it is the
/// only thing standing between a new device and a useless form. These read the
/// real file rather than a fixture, so a bad export fails here instead of in
/// the field.
void main() {
  late LocalDatabase db;
  late PoultryRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PoultryRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<int> loadAsset() async {
    final raw = await File('assets/reference/poultry_reference.json')
        .readAsString();
    // Same writer the network path uses, reached the way the app reaches it.
    return repo.writeReferenceForTest(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  test('the bundled asset carries every collection the form needs', () async {
    await loadAsset();

    expect(await repo.meatTypes(), hasLength(6));
    expect(await repo.grades(), hasLength(4));
    expect(await repo.portionTypes(), hasLength(2));
    expect(await repo.designationClasses(), hasLength(26));
    expect(await repo.alternativeDesignationClasses(), hasLength(13));
    expect(await repo.inspectionReasons(), hasLength(2));
    expect(await repo.inspectionLocations(), hasLength(6));
    expect(await repo.restrictedParticulars(), hasLength(4));
  });

  test('the three tick-lists arrive intact', () async {
    await loadAsset();
    final items = await repo.checklistItems();

    List<PoultryChecklistItemRef> of(PoultryChecklistKind kind) =>
        [for (final i in items) if (i.kind == kind) i];

    // 13 / 4 / 6 is what the original's XAML declares. A count that drifts
    // means the extractor stopped seeing a row.
    expect(of(PoultryChecklistKind.grading), hasLength(13));
    expect(of(PoultryChecklistKind.portion), hasLength(4));
    expect(of(PoultryChecklistKind.pack), hasLength(6));
  });

  test("wording is the original's, bar the corrections the FSA asked for",
      () async {
    await loadAsset();
    final items = await repo.checklistItems();
    final descriptions = items.map((i) => i.description).toList();

    // Wording is carried through verbatim so an inspector comparing this
    // screen against the paper form reads the same words — "Fleshiness", not
    // the "Freshness" it is often misread as.
    expect(descriptions, contains('Fleshiness: General'));

    // Two exceptions, corrected at the FSA's request on 2026-08-20 and
    // listed in the seed's SPELLING_CORRECTIONS so it stays visible that
    // these are ours rather than the original's.
    expect(descriptions, contains('Abrasions and Cuts in the Skin'));
    expect(descriptions, isNot(contains('Abarations and Custs in the Skin')));
    expect(
      descriptions.any((d) => d.contains('specififed')),
      isFalse,
      reason: 'the portions row now reads "specified"',
    );

    // Portion and pack rows cite a regulation; grading rows do not.
    final portion = items
        .firstWhere((i) => i.kind == PoultryChecklistKind.portion);
    expect(portion.regulationReference, isNotEmpty);
    final grading = items
        .firstWhere((i) => i.kind == PoultryChecklistKind.grading);
    expect(grading.regulationReference, isEmpty);
  });

  test('the grading rules resolve against the real reference data', () async {
    await loadAsset();

    final meats = await repo.meatTypes();
    final links = await repo.designationGradeLinks();
    final designations = await repo.designationClasses();
    final grades = await repo.grades();

    final chicken = meats.firstWhere((m) => m.name == 'Chicken');
    final forChicken = PoultryRules.designationsFor(
      meatTypeId: chicken.id,
      links: links,
      designations: designations,
    );

    expect(forChicken, isNotEmpty,
        reason: 'chicken must offer at least one designation');

    // Every designation offered must lead to at least one grade, or the form
    // dead-ends on the next field.
    for (final designation in forChicken) {
      expect(
        PoultryRules.gradesFor(
          meatTypeId: chicken.id,
          designationId: designation.id,
          links: links,
          grades: grades,
        ),
        isNotEmpty,
        reason: '${designation.name} offers no grade under Chicken',
      );
    }
  });

  test('loading twice does not duplicate anything', () async {
    await loadAsset();
    final first = (await repo.checklistItems()).length;
    await loadAsset();

    expect((await repo.checklistItems()).length, first);
  });
}
