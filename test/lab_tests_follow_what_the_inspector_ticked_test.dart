import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The laboratory charges follow what the inspector said the sample is
/// being tested for.
///
/// The raw form used to ask twice: a "Laboratory Testing Category" picker
/// (A/B/C/D) and, right under it, "What are you testing for?" with
/// Fat/Protein/Calcium/DNA. They could disagree, and the category won
/// silently — Kabelo ticked Fat on two samples at N1 Factory Clayville and
/// the Request for Invoice billed 2 x fat AND 2 x protein, R1 066.36 the
/// facility never ordered (2026-10-23). The category question is off the
/// form; soya and starch, which only it could reach, are answers here now.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  late InvoiceRepository invoices;

  const visitUuid = 'visit-tested-for';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    invoices = InvoiceRepository(db, visits);
    await visits.create(visitUuid, 'Kabelo');
    for (final (id, name) in const [
      (1, 'Category A - Meat (Protein) & Fat Content'),
      (2, 'Category B - Soya Protein & Starch Content'),
      (3, 'Category C - Specie(s) Identification'),
      (4, 'Category D - Fat content only'),
    ]) {
      await db.into(db.rawRmpSampleCategories).insert(
            RawRmpSampleCategoriesCompanion.insert(id: Value(id), name: name),
          );
    }
  });
  tearDown(() async => db.close());

  Future<void> sampled(
    String product, {
    bool fat = false,
    bool protein = false,
    bool calcium = false,
    bool dna = false,
    bool soya = false,
    bool starch = false,
    List<int> legacyCategories = const [],
  }) =>
      db.into(db.rawRmpInspections).insert(
            RawRmpInspectionsCompanion.insert(
              clientUuid: product,
              inspectedAt: DateTime(2026, 10, 23, 9),
              updatedAt: DateTime(2026, 10, 23, 9),
              inspectorUsername: const Value('Kabelo'),
              visitUuid: const Value(visitUuid),
              isSampled: const Value(true),
              testFat: Value(fat),
              testProtein: Value(protein),
              calciumTestRequired: Value(calcium),
              testDna: Value(dna),
              testSoya: Value(soya),
              testStarch: Value(starch),
              sampleCategoryId: Value(
                  legacyCategories.isEmpty ? null : legacyCategories.first),
              sampleCategoryIds: Value(legacyCategories.join(',')),
            ),
          );

  Future<InvoiceRequestsCompanion> form() async =>
      invoices.prefill((await visits.byUuid(visitUuid))!);

  group('what the inspector ticked', () {
    test('fat alone bills fat and nothing else', () async {
      await sampled('mince', fat: true);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawProteinTests.value, 0);
      expect(f.rawSoyaTests.value, 0);
      expect(f.rawStarchTests.value, 0);
      expect(f.rawDnaTests.value, 0);
    });

    test('fat and protein bill both', () async {
      await sampled('patty', fat: true, protein: true);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawProteinTests.value, 1);
    });

    test('soya and starch are reachable without a category', () async {
      await sampled('boerewors', soya: true, starch: true);
      final f = await form();
      expect(f.rawSoyaTests.value, 1);
      expect(f.rawStarchTests.value, 1);
      expect(f.rawFatTests.value, 0);
      expect(f.rawProteinTests.value, 0);
    });

    test('species identification bills the DNA line', () async {
      await sampled('wors', dna: true);
      final f = await form();
      expect(f.rawDnaTests.value, 1);
      expect(f.rawFatTests.value, 0);
    });

    test('every box ticked bills every line once', () async {
      await sampled('everything',
          fat: true, protein: true, soya: true, starch: true, dna: true);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawProteinTests.value, 1);
      expect(f.rawSoyaTests.value, 1);
      expect(f.rawStarchTests.value, 1);
      expect(f.rawDnaTests.value, 1);
    });
  });

  // The complaint itself. Two samples, fat ticked on both, and a Category A
  // still sitting on the record from the picker that used to be there.
  test('a stale category cannot add a test the inspector did not ask for',
      () async {
    await sampled('sample one', fat: true, legacyCategories: [1]);
    await sampled('sample two', fat: true, legacyCategories: [1]);
    final f = await form();
    expect(f.rawFatTests.value, 2);
    expect(f.rawProteinTests.value, 0,
        reason: 'he ticked fat; Category A must not add protein');
  });

  test('two samples, one fat and one meat content, bill both lines',
      () async {
    await sampled('mince', fat: true);
    await sampled('patty', fat: true, protein: true);
    final f = await form();
    expect(f.rawFatTests.value, 2);
    expect(f.rawProteinTests.value, 1);
  });

  group('records captured before the question existed', () {
    test('still bill off their category', () async {
      await sampled('old', legacyCategories: [1]);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawProteinTests.value, 1);
    });

    test('and every category they went for counts, not just the first',
        () async {
      // The picker was a multi-select but only the first ticked category
      // was ever billed, so a species identification taken alongside
      // anything else was invoiced at R0 — R2 761.30 the Agency pays for
      // and never charged (found 2026-10-23).
      await sampled('old', legacyCategories: [4, 3]);
      final f = await form();
      expect(f.rawFatTests.value, 1);
      expect(f.rawDnaTests.value, 1, reason: 'the DNA test used to vanish');
    });

    test('all four categories bill all five lines', () async {
      await sampled('old', legacyCategories: [1, 2, 3, 4]);
      final f = await form();
      expect(f.rawFatTests.value, 2, reason: 'Category A and Category D');
      expect(f.rawProteinTests.value, 1);
      expect(f.rawSoyaTests.value, 1);
      expect(f.rawStarchTests.value, 1);
      expect(f.rawDnaTests.value, 1);
    });
  });

  test('an inspection that was not sampled bills nothing', () async {
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'not-sampled',
            inspectedAt: DateTime(2026, 10, 23, 9),
            updatedAt: DateTime(2026, 10, 23, 9),
            inspectorUsername: const Value('Kabelo'),
            visitUuid: const Value(visitUuid),
            isSampled: const Value(false),
            testFat: const Value(true),
            testProtein: const Value(true),
          ),
        );
    final f = await form();
    expect(f.rawFatTests.value, 0);
    expect(f.rawProteinTests.value, 0);
  });
}
