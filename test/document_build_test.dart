// Builds the Agency's documents the way the handset does: from records in a
// database, through the repositories' own builders.
//
//     flutter test test/document_build_test.dart
//     FSA_DOCS_OUT=C:/somewhere flutter test test/document_build_test.dart
//
// `tool/generate_all_documents.dart` renders the layouts from hand-written
// rows, which proves the paper but not the plumbing. This seeds the reference
// data and one worked record per document, then calls the same
// `build...Checklist` the handset calls when it sends an inspection up — so a
// document that fails here is one the office would not receive either.
//
// Writes to a temporary directory unless FSA_DOCS_OUT names somewhere to keep
// them, which is how the set is produced for review.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/record_documents.dart';
import 'package:fsa_app/core/documents/direction_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';

const _inspector = 'CINGA NGONGO';
final _when = DateTime(2026, 9, 1, 11, 30);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every document builds from a record', () async {
    final kept = Platform.environment['FSA_DOCS_OUT'];
    final out = Directory(kept ?? '${Directory.systemTemp.path}/fsa-documents')
      ..createSync(recursive: true);
    stdout.writeln('writing to ${out.path}');

    // The document layer is plain Dart, so it needs its fonts and logo handed
    // to it here rather than read from a Flutter asset bundle.
    FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer
            .asByteData()),
    bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
        .buffer
        .asByteData()),
    logo: pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
    letterhead: pw.MemoryImage(
        await File('assets/images/fsa_letterhead_logo.jpg').readAsBytes()),
    ));

    final db = LocalDatabase(NativeDatabase.memory());
    final results = <({String what, String how})>[];

    void note(String what, String how) {
      results.add((what: what, how: how));
      stdout.writeln('  ${how.padRight(10)}  $what');
    }

    Future<void> check(String what, Future<File?> Function() build) async {
    try {
      final file = await build();
      if (file == null) {
        note(what, 'NOT BUILT');
        return;
      }
      final size = await file.length();
      note(what, size > 1000 ? 'ok' : 'SUSPECT');
    } on Object catch (e) {
      note(what, 'FAILED');
      stdout.writeln('            $e');
    }
    }

    stdout.writeln('Poultry');
    final poultry = PoultryRepository(database: db, baseUrl: '');
    final capture = PoultryCaptureRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(jsonDecode(
          await File('assets/reference/poultry_reference.json').readAsString())
      as Map<String, dynamic>);
    final items = await poultry.checklistItems();
    String ticked(bool Function(PoultryChecklistItemRef) where) =>
      items.where(where).map((i) => i.id).join(',');
    bool isLabelKind(PoultryChecklistItemRef i) =>
      i.kind == PoultryChecklistKind.labelInner ||
      i.kind == PoultryChecklistKind.labelOuter ||
      i.kind == PoultryChecklistKind.container;

    // A grading inspection: carcasses graded, most rows met.
    await poultry.saveInspection(PoultryInspectionsCompanion.insert(
    clientUuid: 'doc-grading',
    inspectedAt: _when,
    updatedAt: _when,
    inspectorUsername: const Value(_inspector),
    status: const Value('completed'),
    facilityName: const Value('Rainbow Chickens - Hammarsdale'),
    facilityTelephone: const Value('031 736 2000'),
    contactPerson: const Value('T. Dlamini'),
    producerTradingName: const Value('Rainbow Farms'),
    productDetails: const Value('Whole Frozen Chicken'),
    sampleNumber: const Value('3'),
    compliantItemIds: Value(ticked((i) => !isLabelKind(i))),
    inspectionComments: const Value(
        'Fleshiness on the breast and broken bones found on sample 3.'),
    ));
    await check('Poultry Grading Checklist',
      () => poultry.buildGradingChecklist('doc-grading', into: out));

    // The notice served off that grading record. It is keyed on the record
    // it was raised from, which is how the form writes it.
    await capture.saveDirection(PoultryDirectionsCompanion.insert(
    clientUuid: 'doc-grading',
    issuedAt: _when,
    updatedAt: _when,
    inspectorUsername: const Value(_inspector),
    status: const Value('completed'),
    facilityName: const Value('Rainbow Chickens - Hammarsdale'),
    clientName: const Value('T. Dlamini'),
    clientEmail: const Value('quality@rainbow.co.za'),
    remarks: const Value('Re-grade and re-label before release.'),
    comments: const Value(
        'Grade claimed on the label is not met by the sampled carcasses.'),
    actionTaken: const Value('Consignment held pending re-grading.'),
    ));
    await check('Poultry Direction (served)',
      () => poultry.buildDirection('doc-grading', into: out));

    // A label/container checklist on the same premises.
    await capture.saveLabelInspection(PoultryLabelInspectionsCompanion.insert(
    clientUuid: 'doc-label',
    inspectedAt: _when,
    updatedAt: _when,
    inspectorUsername: const Value(_inspector),
    status: const Value('completed'),
    facilityName: const Value('Rainbow Chickens - Hammarsdale'),
    facilityTelephone: const Value('031 736 2000'),
    contactPerson: const Value('T. Dlamini'),
    producerTradingName: const Value('Rainbow Farms'),
    productDetails: const Value('Whole Frozen Chicken'),
    registrationNumber: const Value('ZA-PM-4471'),
    outerLabelsPresent: const Value(true),
    compliantItemIds: Value(ticked(isLabelKind)),
    nonConformanceComments:
        const Value('Packer\'s physical address not indicated.'),
    ));
    await check('Poultry Labelling Checklist',
      () => poultry.buildPoultryLabellingChecklist('doc-label', into: out));

    // QUID: a water-chilled determination over ten carcasses, five to each
    // of two injectors — the minimum set the regulation wants, so the sheet
    // carries a real finding on each rather than "not enough carcasses".
    final reasonId = (await poultry.inspectionReasons()).first.id;
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
    clientUuid: 'doc-quid',
    inspectedAt: _when,
    updatedAt: _when,
    inspectorUsername: const Value(_inspector),
    status: const Value('completed'),
    reasonId: Value(reasonId),
    facilityName: const Value('Rainbow Chickens - Hammarsdale'),
    facilityTelephone: const Value('031 736 2000'),
    contactPerson: const Value('T. Dlamini'),
    producerTradingName: const Value('Rainbow Farms'),
    productDetails: const Value('Whole Frozen Chicken'),
    companyRegNumber: const Value('ZA-PM-4471'),
    isWaterChilled: const Value(true),
    injectorName: const Value('Injector 2 - brine'),
    averageInjectorPickup: const Value('1.55'),
    isWholeCarcass: const Value(true),
    isRegulatedStandard: const Value(true),
    dispensationQuidPercent: const Value('8.0'),
    averageWaterChillPickup: const Value('10.5'),
    iterationNumber: const Value('1'),
    setupComplete: const Value(true),
    waterChillingComplete: const Value(true),
    quidDeterminationComplete: const Value(true),
    quidInitialMassG: const Value('14165'),
    quidAfterMassG: const Value('15530'),
    quidGainMassG: const Value('1365'),
    quidPercent: const Value('9.805'),
    documentDate: Value(_when),
    documentName: const Value('Brine batch record BR-2291'),
    documentVerified: const Value(true),
    documentDeviationPresent: const Value(true),
    documentDeviationComment:
        const Value('Injector 2 brine strength not recorded on 30 August.'),
    // Every record verified at the line, with its document photographed.
    verificationRecordsJson: const Value(
        '[{"date":"2026-08-30","document_name":"Brine batch record BR-2291",'
        '"verified":true,"deviation_present":true,'
        '"deviation_comment":"Injector 2 brine strength not recorded on 30 August.",'
        '"photo_path":"/photos/doc_1.jpg"},'
        '{"date":"2026-08-30","document_name":"Chiller temperature log",'
        '"verified":true,"deviation_present":false,"photo_path":"/photos/doc_2.jpg"}]'),
    // The rejection the weighing ended in: injector 2 over its limit.
    directionRequired: const Value(true),
    directionReason: const Value(
        'Injector 2 - brine: average QUID 12.108% exceeds the permitted '
        '9.000% over 5 carcasses, on the second determination.'),
    directionRemarks: const Value('• Injector running over its set QUID %'),
    directionAction: const Value('Batch BR-2291, 240 carcasses, held'),
    correctByDate: Value(_when),
    managerName: const Value('T. Dlamini'),
    managerEmail: const Value('manager@rainbow.test'),
    ));
    // The set-up's injectors. The determination is judged against what each
    // was set to, so a seed without them prints a sheet with no finding.
    await capture.replaceQuidInjectors('doc-quid', [
    PoultryQuidInjectorsCompanion.insert(
      inspectionUuid: 'doc-quid',
      position: 1,
      name: const Value('Injector 1 - brine'),
      quidPercent: const Value('8.0'),
    ),
    PoultryQuidInjectorsCompanion.insert(
      inspectionUuid: 'doc-quid',
      position: 2,
      name: const Value('Injector 2 - brine'),
      quidPercent: const Value('8.0'),
    ),
    ]);
    await capture.replaceQuidSamples('doc-quid', [
    for (var n = 1; n <= 10; n++)
      PoultryQuidSamplesCompanion.insert(
        inspectionUuid: 'doc-quid',
        carcassNumber: Value('$n'),
        initialMassG: Value('${1400 + n * 3}'),
        finalMassG: Value('${1548 + n * 4}'),
        pickupPercent: Value((10.2 + n * 0.1).toStringAsFixed(1)),
        // Injector readings too, so the sheet's injector table is actually
        // rendered. It has its own rate column, and a seed with only
        // chilling rows never printed it.
        beforeMassG: Value('${1380 + n * 3}'),
        injectorAfterMassG: Value('${1400 + n * 3}'),
        gainG: const Value('20'),
        injectorRatePercent: Value((1.4 + n * 0.05).toStringAsFixed(2)),
        // The determination itself, weighed per carcass off the process.
        // Injector 1 runs inside its setting, injector 2 over it, so the
        // sheet has one of each finding on it.
        assignedInjector: Value(n <= 5 ? '1' : '2'),
        quidFinalMassG: Value(n <= 5
            ? '${(1400 + n * 3) * 100 ~/ 93}'
            : '${(1400 + n * 3) * 100 ~/ 88}'),
        quidGainG: const Value(''),
        quidPercent: Value(n <= 5 ? '7.${500 + n}' : '12.${100 + n}'),
      ),
    ]);
    await check('Poultry QUID Determination Checklist',
      () => poultry.buildQuidChecklist('doc-quid', into: out));
    // The rejection served for it, which had no sheet at all.
    await check('Poultry QUID Rejection',
      () => poultry.buildQuidRejection('doc-quid', into: out));

    // ---------------------------------------------------- raw and processed
    stdout.writeln('Certain Raw Processed Meat Products');
    final raw = RawRmpRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await raw.writeReferenceForTest(jsonDecode(
            await File('assets/reference/rawrmp_reference.json').readAsString())
        as Map<String, dynamic>);
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'doc-raw',
            inspectedAt: _when,
            updatedAt: _when,
            inspectorUsername: const Value(_inspector),
            status: const Value('completed'),
            facilityName: const Value('Mabovula Butchery - Queenstown'),
            facilityAddress: const Value('73 Robinson Street, Queenstown'),
            contactPerson: const Value('S. Mabovula'),
            contactPersonEmail: const Value('shop@mabovula.co.za'),
            producerName: const Value('Karoo Meat Producers'),
            productItem: const Value('Boerewors'),
            batchNumber: const Value('4471'),
            markingLabelsPresent: const Value(true),
            scaleLabelsPresent: const Value(true),
            containersPresent: const Value(true),
            labelPackComplete: const Value(true),
            // Two rows left unticked in the marking section, so the sheet
            // has deviations on it and a direction follows.
            compliantItemIds: const Value('3,4,5,6,7'),
            isSampled: const Value(true),
            internalSampleNumber: const Value('RAW-2026-118'),
            testSampleSize: const Value('500 g'),
            correctByDate: Value(DateTime(2026, 9, 30)),
            compositionChecklistJson: Value(CompositionChecklist.encode([
              for (var i = 0; i < CompositionChecklist.items.length; i++)
                CompositionAnswer(
                  deviation: i == 1,
                  contributionGrams: '${120 + i * 10}',
                  remarks: i == 1 ? 'Fat above the class maximum.' : '',
                ),
            ])),
            compositionComments: const Value('Sampled for laboratory check.'),
          ),
        );
    await raw.saveDirection(RawRmpDirectionsCompanion.insert(
      clientUuid: 'doc-raw-direction',
      issuedAt: _when,
      updatedAt: _when,
      inspectorUsername: const Value(_inspector),
      sourceInspectionUuid: const Value('doc-raw'),
      referenceNumber: const Value('Mabovula Butchery/37/01/09/2026/01'),
      correctByDate: Value(DateTime(2026, 9, 30)),
      facilityName: const Value('Mabovula Butchery - Queenstown'),
      remarks: const Value('Product name absent from the marking label.'),
      comments: const Value('Re-label before the product is offered again.'),
    ));
    await check('Raw Labelling Verification Checklist',
        () => raw.buildLabellingChecklist('doc-raw', into: out));
    await check('Raw Sampling Checklist',
        () => raw.buildSamplingChecklist('doc-raw', into: out));
    await check('Raw Compositional Checklist',
        () => raw.buildCompositionChecklist('doc-raw', into: out));
    await check('Raw Direction', () => raw.buildDirection('doc-raw', into: out));

    stdout.writeln('Processed Meat Products');
    final pmp = PmpRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await pmp.writeReferenceForTest(jsonDecode(
            await File('assets/reference/pmp_reference.json').readAsString())
        as Map<String, dynamic>);
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'doc-pmp',
          inspectedAt: _when,
          updatedAt: _when,
          inspectorUsername: const Value(_inspector),
          status: const Value('completed'),
          facilityName: const Value('Shoprite - Bridge City'),
          contactPerson: const Value('N. Khumalo'),
          producerName: const Value('Eskort'),
          productItem: const Value('Russians'),
          batchNumber: const Value('PMP-2026-207'),
          markingLabelsPresent: const Value(true),
          labelPackComplete: const Value(true),
          compliantItemIds: const Value('1,2,3'),
          isSampled: const Value(true),
          internalSampleNumber: const Value('PMP-2026-207'),
        ));
    await check('PMP Labelling Verification Checklist',
        () => pmp.buildLabellingChecklist('doc-pmp', into: out));
    await check('PMP Sampling Checklist',
        () => pmp.buildSamplingChecklist('doc-pmp', into: out));
    await pmp.saveDirection(PmpDirectionsCompanion.insert(
      clientUuid: 'doc-pmp-direction',
      issuedAt: _when,
      updatedAt: _when,
      inspectorUsername: const Value(_inspector),
      status: const Value('completed'),
      sourceInspectionUuid: const Value('doc-pmp'),
      facilityName: const Value('Shoprite - Bridge City'),
      clientName: const Value('N. Khumalo'),
      remarks: const Value('Ingredient list not in descending order of mass.'),
      comments: const Value('Re-label before the product is offered again.'),
    ));
    await check('PMP Direction',
        () => pmp.buildDirection('doc-pmp', into: out));

    stdout.writeln('Direction');
    // Served from the grading record above, so the sheet carries a real
    // facility rather than invented names.
    final direction = await DirectionPdf.write(
    out: File('${out.path}/POULTRY-Direction.pdf'),
    control: FsaDocuments.poultryDirection,
    natureOfInspection: 'Poultry Meat Classification and Grading',
    facilityName: 'Rainbow Chickens - Hammarsdale',
    ownerOrRepresentative: 'T. Dlamini',
    physicalAddress: 'Old Main Road, Hammarsdale 3700',
    emailAddress: 'quality@rainbow.co.za',
    dateOfVisit: _when,
    inspectionReason: 'Inspection',
    latestReference: 'PM-2026-0184',
    originalReference: '',
    subjectFields: const [
      (label: 'Producer', value: 'Rainbow Farms'),
      (label: 'Product Details', value: 'Whole Frozen Chicken'),
      (label: 'Batch Number', value: 'PM-8841'),
    ],
    deviations: const [
      DirectionDeviation(
        product: 'Whole Frozen Chicken',
        nature: 'Fleshiness of the breast below the standard for the grade '
            'claimed on the label.',
        regulation: 'Reg. 4(1)',
      ),
      DirectionDeviation(
        product: 'Whole Frozen Chicken',
        nature: 'Broken bones and dislocation found on the sampled carcass.',
        regulation: 'Reg. 4(1)',
      ),
    ],
    correctByDate: '30/09/2026',
    actionsAndRemark:
        'Consignment held pending re-grading. Re-label to the grade the '
        'carcasses meet before release.',
    inspectorName: _inspector,
    authorisedPersonName: 'T. Dlamini',
    pleaseNote: 'Failure to rectify by the date above may result in further '
        'action under the Act.',
    );
    note('Poultry Direction', await direction.length() > 1000 ? 'ok' : 'SUSPECT');

    // What the inspector can open on the record itself. Egg and QUID both
    // fell through to `default: return const []` before, so an egg record
    // showed no documents at all and a QUID record had none to show.
    // An egg record with a deviation on it: enough for the labelling sheet
    // to exist, no samples so the weighing sheet correctly does not.
    stdout.writeln('Eggs');
    final eggs = EggsRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(jsonDecode(
            await File('assets/reference/eggs_reference.json').readAsString())
        as Map<String, dynamic>);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'doc-egg',
          inspectedAt: _when,
          updatedAt: _when,
          inspectorUsername: const Value(_inspector),
          facilityName: const Value('Nulaid - Eikenhof'),
          clientName: const Value('Nulaid - Eikenhof'),
          producerSupplier: const Value('Nulaid'),
          batchNumber: const Value('EGG-2026-0912'),
          failedRequirementIds: const Value('1,2'),
        ));
    // The rejection served off it — what the app calls a rejection is the
    // direction the client is handed, and it rendered nothing before.
    await eggs.saveDirection(EggDirectionsCompanion.insert(
      clientUuid: 'doc-egg-rejection',
      inspectionUuid: const Value('doc-egg'),
      issuedAt: _when,
      updatedAt: _when,
      inspectorUsername: const Value(_inspector),
      status: const Value('completed'),
      directionNumber: const Value('Nulaid/37/01/09/2026/01'),
      labellingPart: const Value(true),
      labelCorrectBy: Value(DateTime(2026, 9, 30)),
      clientName: const Value('Nulaid - Eikenhof'),
      producerSupplier: const Value('Nulaid'),
      additionalRemarks:
          const Value('Re-label the consignment before it is offered again.'),
    ));
    await check('Egg Rejection', () => eggs.buildDirection('doc-egg', into: out));

    for (final (kind, uuid, expected) in [
      ('egg', 'doc-egg', 'Labelling Checklist'),
      ('egg', 'doc-egg', 'Rejection'),
      ('pmp', 'doc-pmp', 'Rejection'),
      ('poultry', 'doc-grading', 'Rejection'),
      ('rawrmp', 'doc-raw', 'Labelling Verification Checklist'),
      ('rawrmp', 'doc-raw', 'Rejection'),
      ('pmp', 'doc-pmp', 'Labelling Verification Checklist'),
      ('poultry', 'doc-grading', 'Poultry Grading Checklist'),
      ('poultry_label', 'doc-label', 'Poultry Labelling Checklist'),
      ('quid', 'doc-quid', 'QUID Determination Checklist'),
    ]) {
      final offered = await documentsForRecord(db, kind, uuid);
      note('$kind offers: ${offered.map((d) => d.title).join(', ')}',
          offered.any((d) => d.title == expected) ? 'ok' : 'MISSING');
    }

    await db.close();

    final bad = results.where((r) => r.how != 'ok').toList();
    stdout.writeln('\n${results.length - bad.length}/${results.length} ok');
    expect(bad, isEmpty,
        reason: 'documents that did not build: '
            '${bad.map((b) => b.what).join(', ')}');
  });
}
