import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/invoicing/data/invoice_pdf.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_form_data.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Every laboratory test a visit took has to reach the Request for Invoice,
/// not just the ones from the first inspection captured.
///
/// A visit can hold several raw-meat inspections, each sampled under its own
/// test category: a mince goes for fat only, the patty beside it goes for
/// meat content. The form bills per test, so both lines have to be on it —
/// and a visit that only sampled the mince must not carry a protein charge
/// the facility never incurred (Nelisa's Checkers RFI, 2026-10-23).
///
/// This goes the whole way: the inspections are captured in a database, put
/// through the app's own prefill, and rendered as the sheet the handset
/// produces. Set `RFI_OUT` to a directory to keep the PDFs for inspection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFsaFormAssets();

  late LocalDatabase db;
  late VisitRepository visits;
  late InvoiceRepository invoices;
  late Directory scratch;

  const visitUuid = 'visit-lab-proof';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    invoices = InvoiceRepository(db, visits);
    await visits.create(visitUuid, 'Ethan');
    for (final (id, name) in const [
      (1, 'Category A - Meat (Protein) & Fat Content'),
      (2, 'Category B - Soya Protein & Starch Content'),
      (3, 'Category C - Specie(s) Identification'),
      (4, 'Category D - Fat content only'),
    ]) {
      await db.into(db.rawRmpSampleCategories).insert(
            RawRmpSampleCategoriesCompanion.insert(
                id: Value(id), name: name),
          );
    }
    scratch = Directory.systemTemp.createTempSync('rfi-lab');
  });
  tearDown(() async {
    await db.close();
    scratch.deleteSync(recursive: true);
  });

  Future<void> sample(String product, int category) =>
      db.into(db.rawRmpInspections).insert(
            RawRmpInspectionsCompanion.insert(
              clientUuid: product,
              inspectedAt: DateTime(2026, 10, 23, 9),
              updatedAt: DateTime(2026, 10, 23, 9),
              inspectorUsername: const Value('Ethan'),
              visitUuid: const Value(visitUuid),
              isSampled: const Value(true),
              sampleCategoryId: Value(category),
            ),
          );

  int count(Value<int> v) => v.present ? v.value : 0;

  /// Renders the sheet the handset would produce from this visit and
  /// returns it with the counts that went onto it.
  Future<({File file, int fat, int protein, int soya, int starch, int dna})>
      sheet(String name) async {
    final prefilled = await invoices.prefill((await visits.byUuid(visitUuid))!);
    final form = InvoiceFormData(
      inspectorName: 'Ethan Sevenster',
      siteVisited: 'DEMO Training Store',
      siteManager: 'DEMO Manager',
      productName: 'Certain Raw Processed Meat Products',
      dateOfVisit: DateTime(2026, 10, 23),
      timeStarted: '09:00',
      timeEnded: '10:00',
      rawRmpTicked: true,
      sampleTakingTicked: true,
      normalHours: 1,
      overtimeHours: 0,
      sundayHours: 0,
      kilometres: 20,
      rawFatTests: count(prefilled.rawFatTests),
      rawProteinTests: count(prefilled.rawProteinTests),
      rawSoyaTests: count(prefilled.rawSoyaTests),
      rawStarchTests: count(prefilled.rawStarchTests),
      rawDnaTests: count(prefilled.rawDnaTests),
      managerSignaturePath: '',
      inspectorSignaturePath: '',
      signedAt: DateTime(2026, 10, 23),
    );
    final keep = Platform.environment['RFI_OUT'];
    final dir = keep == null ? scratch.path : (Directory(keep)..createSync(recursive: true)).path;
    final file = await InvoicePdf.write(form,
        outputPath: '$dir${Platform.pathSeparator}$name');
    return (
      file: file,
      fat: form.rawFatTests,
      protein: form.rawProteinTests,
      soya: form.rawSoyaTests,
      starch: form.rawStarchTests,
      dna: form.rawDnaTests,
    );
  }

  test('two raw inspections, fat only and meat content, bill both lines',
      () async {
    await sample('mince', 4); // Category D — fat content only
    await sample('patty', 1); // Category A — meat (protein) & fat content
    final rfi = await sheet('rfi_two_raw_fat_and_protein.pdf');

    expect(rfi.fat, 2, reason: 'Category D is fat, Category A is fat too');
    expect(rfi.protein, 1, reason: 'only Category A sends protein');
    expect(rfi.soya, 0);
    expect(rfi.starch, 0);
    expect(rfi.dna, 0);
    // Both lines carry a charge, so both print as money rather than as a
    // zero the office has to notice is wrong.
    expect(rfi.fat, greaterThan(0));
    expect(rfi.protein, greaterThan(0));
    expect(await rfi.file.length(), greaterThan(0));
  });

  test('one raw inspection sampled for fat bills fat and no protein',
      () async {
    await sample('mince', 4);
    final rfi = await sheet('rfi_one_raw_fat_only.pdf');

    expect(rfi.fat, 1);
    expect(rfi.protein, 0,
        reason: 'a mince sampled for fat is not charged for protein');
    expect(rfi.soya, 0);
    expect(rfi.starch, 0);
    expect(rfi.dna, 0);
    expect(await rfi.file.length(), greaterThan(0));
  });
}
