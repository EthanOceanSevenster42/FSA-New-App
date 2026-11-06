import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The laboratory lines on the Request for Invoice come from the test
/// category the inspector chose on each sampled raw-meat inspection.
///
/// Category A is meat (protein) and fat content, B is soya and starch, C is
/// species identification, D is fat only. Before this the counts sat at zero
/// until somebody typed them, so a sampled visit invoiced as if nothing had
/// gone to the laboratory.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  late InvoiceRepository invoices;

  const visitUuid = 'visit-lab-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    invoices = InvoiceRepository(db, visits);
    await visits.create(visitUuid, 'Armand');
    for (final (id, name) in const [
      (1, 'Category A - Meat (Protein) & Fat Content'),
      (2, 'Category B - Soya Protein & Starch Content'),
      (3, 'Category C - Specie(s) Identification'),
      (4, 'Category D - Fat content only'),
    ]) {
      await db.into(db.rawRmpSampleCategories).insert(
            RawRmpSampleCategoriesCompanion.insert(
              id: Value(id),
              name: name,
            ),
          );
    }
  });
  tearDown(() async => db.close());

  Future<void> sampledRaw(String uuid, int? category, {bool sampled = true}) =>
      db.into(db.rawRmpInspections).insert(
            RawRmpInspectionsCompanion.insert(
              clientUuid: uuid,
              inspectedAt: DateTime(2026, 8, 26, 10),
              updatedAt: DateTime(2026, 8, 26, 10),
              inspectorUsername: const Value('Armand'),
              visitUuid: const Value(visitUuid),
              isSampled: Value(sampled),
              sampleCategoryId: Value(category),
            ),
          );

  Future<InvoiceRequestsCompanion> form() async =>
      invoices.prefill((await visits.byUuid(visitUuid))!);

  test('category A bills one fat and one protein test', () async {
    await sampledRaw('r1', 1);
    final f = await form();
    expect(f.rawFatTests.value, 1);
    expect(f.rawProteinTests.value, 1);
    expect(f.rawSoyaTests.value, 0);
    expect(f.rawDnaTests.value, 0);
  });

  test('category B bills soya and starch', () async {
    await sampledRaw('r1', 2);
    final f = await form();
    expect(f.rawSoyaTests.value, 1);
    expect(f.rawStarchTests.value, 1);
    expect(f.rawFatTests.value, 0);
  });

  test('category C bills one DNA test, D bills fat only', () async {
    await sampledRaw('r1', 3);
    await sampledRaw('r2', 4);
    final f = await form();
    expect(f.rawDnaTests.value, 1);
    expect(f.rawFatTests.value, 1);
    expect(f.rawProteinTests.value, 0);
  });

  test('an inspection that was not sampled sends nothing to the lab',
      () async {
    await sampledRaw('r1', 1, sampled: false);
    final f = await form();
    expect(f.rawFatTests.value, 0);
    expect(f.rawProteinTests.value, 0);
  });

  test('two sampled inspections in one visit are two sets of tests', () async {
    await sampledRaw('r1', 1);
    await sampledRaw('r2', 1);
    final f = await form();
    expect(f.rawFatTests.value, 2);
    expect(f.rawProteinTests.value, 2);
  });

  // What a visit with two different raw products bills, which is how an
  // inspector meets this: a mince sampled for fat only, and a second
  // product sampled for meat content. Both laboratory lines have to reach
  // the form - a visit used to bill whichever one the office typed in
  // (Ethan, 2026-10-23).
  group('two raw inspections with different categories', () {
    test('fat only and meat content bill both lines', () async {
      await sampledRaw('mince', 4);
      await sampledRaw('patty', 1);
      final f = await form();
      // Both of them are fat: Category D is fat, and Category A is fat and
      // protein together. There is no protein-only category to pick.
      expect(f.rawFatTests.value, 2);
      expect(f.rawProteinTests.value, 1);
      expect(f.rawSoyaTests.value, 0);
      expect(f.rawStarchTests.value, 0);
      expect(f.rawDnaTests.value, 0);
    });

    test('the order they were captured in makes no difference', () async {
      await sampledRaw('patty', 1);
      await sampledRaw('mince', 4);
      final f = await form();
      expect(f.rawFatTests.value, 2);
      expect(f.rawProteinTests.value, 1);
    });

    test('soya and fat bill their own lines and nothing else', () async {
      await sampledRaw('mince', 4);
      await sampledRaw('boerewors', 2);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawSoyaTests.value, 1);
      expect(f.rawStarchTests.value, 1);
      expect(f.rawProteinTests.value, 0);
      expect(f.rawDnaTests.value, 0);
    });
  });

  // The complaint that started this: a mince sample is charged for fat and
  // the facility was invoiced for protein as well (Nelisa, 2026-10-23).
  test('one raw inspection sampled for fat bills fat and nothing else',
      () async {
    await sampledRaw('mince', 4);
    final f = await form();
    expect(f.rawFatTests.value, 1);
    expect(f.rawProteinTests.value, 0, reason: 'no protein on a fat-only sample');
    expect(f.rawSoyaTests.value, 0);
    expect(f.rawStarchTests.value, 0);
    expect(f.rawDnaTests.value, 0);
    // And nothing lands on the processed-meat lines either: no PMP
    // inspection was captured.
    expect(f.pmpFatTests.value, 0);
    expect(f.pmpProteinTests.value, 0);
  });

  test('a sampled inspection with no category chosen bills nothing',
      () async {
    await sampledRaw('r1', null);
    final f = await form();
    expect(f.rawFatTests.value, 0);
    expect(f.rawProteinTests.value, 0);
  });
}
