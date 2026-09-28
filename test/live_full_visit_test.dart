@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uuid/uuid.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/domain/quid_flow.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// One whole grouped inspection, captured and sent the way the handset sends
/// it — against a real server.
///
/// Every commodity the app can capture goes into one visit at one facility:
/// a poultry grading with a direction on it, the label/container checklist,
/// a QUID determination with an injector running over what it is set to, a
/// raw processed meat inspection that is sampled and directed, and an egg
/// inspection with its weighed sample set. Photographs and signatures are
/// real image files, the documents are rendered by the app's own builders,
/// and the group goes up through `VisitRepository.upload` — which is what
/// files the record in APS.
///
/// Nothing here is a fixture for the test's own benefit: it is the same
/// sequence `ServerSyncRunner` walks, so what the office receives is what an
/// inspector's handset would have sent.
///
///     FSA_LIVE_BASE_URL=http://10.0.0.203:8010 \
///     FSA_LIVE_USER=Ethan1 FSA_LIVE_PASSWORD=... \
///     FSA_DEMO_PHOTOS=C:/…/demo \
///     flutter test test/live_full_visit_test.dart --tags live
/// path_provider has no platform under `flutter test`, and the Request for
/// Invoice is written through PhotoStorage, which asks it where the app's
/// documents live. Every folder it asks about is one scratch directory here.
class _Scratch extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Scratch(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
  @override
  Future<String?> getTemporaryPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs an HttpOverrides that answers every
  // request with a 400 and never touches the network. This suite is
  // deliberately the opposite: it talks to a real server.
  HttpOverrides.global = null;
  PathProviderPlatform.instance = _Scratch(
      Directory.systemTemp.createTempSync('fsa_live_visit_').path);

  final baseUrl = Platform.environment['FSA_LIVE_BASE_URL'];
  final username = Platform.environment['FSA_LIVE_USER'];
  final password = Platform.environment['FSA_LIVE_PASSWORD'];
  // An access token may stand in for the password, for a run against a
  // server whose account passwords are not to hand.
  final presetToken = Platform.environment['FSA_LIVE_TOKEN'];
  final photoDir = Platform.environment['FSA_DEMO_PHOTOS'];

  if (baseUrl == null ||
      username == null ||
      (password == null && presetToken == null) ||
      photoDir == null) {
    test('a whole visit reaches the office', () {},
        skip: 'FSA_LIVE_* / FSA_DEMO_PHOTOS not set.');
    return;
  }

  test('a whole visit reaches the office', () async {
    // ------------------------------------------------------------ sign in
    String token;
    if (presetToken != null && presetToken.isNotEmpty) {
      token = presetToken;
    } else {
      final login = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login/'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'device_id': 'demo-visit-harness',
              'device_model': 'flutter test',
            }),
          )
          .timeout(const Duration(seconds: 30));
      expect(login.statusCode, 200, reason: 'login transport failed');
      final session = jsonDecode(login.body) as Map<String, dynamic>;
      expect(session['outcome'], 'success',
          reason: 'login rejected: ${login.body}');
      token = session['access'] as String;
    }

    // The document layer is plain Dart: outside the app it is handed its
    // fonts and letterhead rather than reading a Flutter asset bundle.
    FsaForm.useAssets(FsaFormAssets(
      regular: pw.Font.ttf(
          (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
              .buffer
              .asByteData()),
      bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
          .buffer
          .asByteData()),
      logo:
          pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
      letterhead: pw.MemoryImage(
          await File('assets/images/fsa_letterhead_logo.jpg').readAsBytes()),
    ));

    final db = LocalDatabase(NativeDatabase.memory());
    await db.writeSyncState(EggsRepository.sessionUserKey, username);
    await db.writeSyncState('auth.accessToken', token);

    final eggs = EggsRepository(database: db, baseUrl: baseUrl);
    final poultry = PoultryRepository(database: db, baseUrl: baseUrl);
    final capture = PoultryCaptureRepository(database: db, baseUrl: baseUrl);
    final raw = RawRmpRepository(database: db, baseUrl: baseUrl);
    final visits = VisitRepository(db, baseUrl: baseUrl);
    final invoices = InvoiceRepository(db, visits);

    // The server's own rules, so every id this record carries is one the
    // server already knows. A bundled copy would be a guess.
    stdout.writeln('reference: eggs ${await eggs.syncReference(full: true)}, '
        'poultry ${await poultry.syncReference(fromScratch: true)}, '
        'raw ${await raw.syncReference(fromScratch: true)} rows');

    final photos = Directory(photoDir);
    String shot(String name) {
      final file = File('${photos.path}/$name');
      expect(file.existsSync(), isTrue, reason: 'missing demo image: $name');
      return file.path;
    }

    // --------------------------------------------------------------- visit
    const id = Uuid();
    final visitUuid = id.v4();
    final gradingUuid = id.v4();
    final labelUuid = id.v4();
    final quidUuid = id.v4();
    final rawUuid = id.v4();
    final rawDirectionUuid = id.v4();
    final eggUuid = id.v4();

    final startedAt = DateTime.now().subtract(const Duration(hours: 4));
    final at = DateTime.now().subtract(const Duration(hours: 1));

    const facility = 'Rainbow Chickens - Hammarsdale';
    const address = '1 Old Main Road, Hammarsdale, KwaZulu-Natal';
    const manager = 'T. Dlamini';
    const inspectorName = 'C. Ngongo';
    const clientEmail = 'quality@rainbow.test';

    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          startedAt: startedAt,
          facilityName: const Value(facility),
          facilityAddress: const Value(address),
          facilityPhone: const Value('031 736 2000'),
          contactPerson: const Value(manager),
          contactEmail: const Value(clientEmail),
          managerName: const Value(manager),
          managerEmail: const Value('manager@rainbow.test'),
          additionalEmail1: const Value('headoffice@rainbow.test'),
          facilityType: const Value('Abattoir'),
          inspectionReason: const Value('Inspection'),
          inspectorUsername: Value(username),
          distanceTravelledKm: const Value(45),
          plannedPoultry: const Value(1),
          plannedLabels: const Value(1),
          plannedRaw: const Value(1),
          plannedEggs: const Value(1),
          planOrder: const Value('poultry,poultry_label,quid,rawrmp,egg'),
        ));

    // ------------------------------------------------------ poultry grading
    final items = await poultry.checklistItems();
    bool isLabelKind(PoultryChecklistItemRef i) =>
        i.kind == PoultryChecklistKind.labelInner ||
        i.kind == PoultryChecklistKind.labelOuter ||
        i.kind == PoultryChecklistKind.container;
    final gradingIds =
        items.where((i) => !isLabelKind(i)).map((i) => i.id).toList();
    final labelIds = items.where(isLabelKind).map((i) => i.id).toList();
    // Two rows in each list left unticked, so both records carry real
    // deviations and the directions have something to name.
    List<int> allBarLastTwo(List<int> ids) =>
        ids.length > 2 ? ids.sublist(0, ids.length - 2) : ids;

    final meatTypes = await db.select(db.poultryMeatTypes).get();
    final grades = await db.select(db.poultryGrades).get();
    final reasons = await poultry.inspectionReasons();
    final locations = await db.select(db.poultryInspectionLocations).get();

    await poultry.saveInspection(PoultryInspectionsCompanion.insert(
      clientUuid: gradingUuid,
      inspectedAt: at,
      updatedAt: at,
      visitUuid: Value(visitUuid),
      inspectorUsername: Value(username),
      status: const Value('ready'),
      facilityName: const Value(facility),
      facilityAddress: const Value(address),
      facilityTelephone: const Value('031 736 2000'),
      companyRegNumber: const Value('ZA-PM-4471'),
      contactPerson: const Value(manager),
      contactPersonEmail: const Value(clientEmail),
      managerName: const Value(manager),
      managerEmail: const Value('manager@rainbow.test'),
      producerTradingName: const Value('Rainbow Farms'),
      productDetails: const Value('Whole Frozen Chicken'),
      sampleNumber: const Value('3'),
      meatTypeId: Value(meatTypes.isEmpty ? null : meatTypes.first.id),
      gradeId: Value(grades.isEmpty ? null : grades.first.id),
      reasonId: Value(reasons.isEmpty ? null : reasons.first.id),
      locationId: Value(locations.isEmpty ? null : locations.first.id),
      compliantItemIds: Value(allBarLastTwo(gradingIds).join(',')),
      inspectionComments: const Value(
          'Fleshiness of the breast below the grade claimed on the label, and '
          'broken bones found on carcass 3 of the sample.'),
      directionComments: const Value(
          'Consignment held pending re-grading. Re-label to the grade the '
          'carcasses meet before release.'),
      directionRemarks: const Value('Re-grade and re-label before release.'),
      latitude: const Value(-29.8011),
      longitude: const Value(30.6423),
    ));
    await capture.saveDirection(PoultryDirectionsCompanion.insert(
      clientUuid: gradingUuid,
      issuedAt: at,
      updatedAt: at,
      inspectorUsername: Value(username),
      status: const Value('completed'),
      facilityName: const Value(facility),
      clientName: const Value(manager),
      clientEmail: const Value(clientEmail),
      remarks: const Value('Re-grade and re-label before release.'),
      comments: const Value(
          'Grade claimed on the label is not met by the sampled carcasses.'),
      actionTaken: const Value('Consignment held pending re-grading.'),
      latitude: const Value(-29.8011),
      longitude: const Value(30.6423),
    ));
    for (final shotOf in [
      ('poultry_grading_1.jpg', 'Sampled carcasses on the grading table'),
      ('poultry_grading_2.jpg', 'Carcass 3 - broken bone and dislocation'),
    ]) {
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: gradingUuid,
        kind: 'grading',
        filePath: shot(shotOf.$1),
        caption: Value(shotOf.$2),
        capturedAt: at,
      ));
    }

    // -------------------------------------------------- label / container
    await capture.saveLabelInspection(PoultryLabelInspectionsCompanion.insert(
      clientUuid: labelUuid,
      inspectedAt: at,
      updatedAt: at,
      visitUuid: Value(visitUuid),
      inspectorUsername: Value(username),
      status: const Value('ready'),
      facilityName: const Value(facility),
      facilityTelephone: const Value('031 736 2000'),
      contactPerson: const Value(manager),
      producerTradingName: const Value('Rainbow Farms'),
      productDetails: const Value('Whole Frozen Chicken'),
      registrationNumber: const Value('ZA-PM-4471'),
      outerLabelsPresent: const Value(true),
      compliantItemIds: Value(allBarLastTwo(labelIds).join(',')),
      nonConformanceComments: const Value(
          'Packer physical address not indicated on the inner label.'),
    ));
    for (final shotOf in [
      ('poultry_label_1.jpg', 'Outer carton marking label'),
      ('poultry_label_2.jpg', 'Inner label - packer address absent'),
    ]) {
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: labelUuid,
        kind: 'label',
        filePath: shot(shotOf.$1),
        caption: Value(shotOf.$2),
        capturedAt: at,
      ));
    }

    // ------------------------------------------------------------- QUID
    final remarks = await poultry.directionRemarks();
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: quidUuid,
      inspectedAt: at,
      updatedAt: at,
      visitUuid: Value(visitUuid),
      inspectorUsername: Value(username),
      status: const Value('ready'),
      reasonId: Value(reasons.isEmpty ? null : reasons.first.id),
      facilityName: const Value(facility),
      facilityTelephone: const Value('031 736 2000'),
      contactPerson: const Value(manager),
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
      // Two rounds: the first found injector 2 over, the repeat confirmed
      // it, and a rejection followed — every stage the weighing screen
      // records on the way there.
      iterationNumber: const Value('2'),
      repeatQuidDetermination: const Value(true),
      setupComplete: const Value(true),
      waterChillingComplete: const Value(true),
      injectorSamplingComplete: const Value(true),
      quidDeterminationComplete: const Value(true),
      directionRequired: const Value(true),
      directionReason: const Value(
          'Injector 2 - brine: average QUID 12.108% exceeds the permitted '
          '9.000% over 5 carcasses, on the second determination.'),
      directionRemarkTypeId: Value(remarks.isEmpty ? null : remarks.first.id),
      directionRemarks: const Value('• Injector running over its set QUID %'),
      directionAction: const Value('Batch BR-2291, 240 carcasses, held'),
      correctByDate: Value(at.add(const Duration(days: 7))),
      // The records verified at the line, each with its document photographed.
      verificationRecordsJson: Value(QuidVerificationRecord.encode([
        QuidVerificationRecord(
          date: at,
          documentName: 'Brine batch record BR-2291',
          verified: true,
          deviationPresent: true,
          deviationComment:
              'Injector 2 brine strength not recorded on 30 August.',
          photoPath: shot('quid_doc_1.jpg'),
        ),
        QuidVerificationRecord(
          date: at,
          documentName: 'Chiller temperature log',
          verified: true,
          deviationPresent: false,
          photoPath: shot('quid_doc_2.jpg'),
        ),
      ])),
      documentDate: Value(at),
      documentName: const Value('Brine batch record BR-2291'),
      documentVerified: const Value(true),
      documentDeviationPresent: const Value(true),
      documentDeviationComment:
          const Value('Injector 2 brine strength not recorded on 30 August.'),
      generalComments: const Value(
          'Injector 2 is running over the QUID it is set to; the plant was '
          'directed to re-calibrate before the next run.'),
      latitude: const Value(-29.8011),
      longitude: const Value(30.6423),
    ));
    await capture.replaceQuidInjectors(quidUuid, [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: quidUuid,
        position: 1,
        name: const Value('Injector 1 - brine'),
        quidPercent: const Value('8.0'),
      ),
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: quidUuid,
        position: 2,
        name: const Value('Injector 2 - brine'),
        quidPercent: const Value('8.0'),
      ),
    ]);
    await capture.replaceQuidSamples(quidUuid, [
      // Both rounds stay on the record; the second is the one judged.
      for (final round in [1, 2])
      for (var n = 1; n <= 10; n++)
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: quidUuid,
          iteration: Value(round),
          carcassNumber: Value('$n'),
          initialMassG: Value('${1400 + n * 3}'),
          finalMassG: Value('${1548 + n * 4}'),
          pickupPercent: Value((10.2 + n * 0.1).toStringAsFixed(1)),
          beforeMassG: Value('${1380 + n * 3}'),
          injectorAfterMassG: Value('${1400 + n * 3}'),
          gainG: const Value('20'),
          injectorRatePercent: Value((1.4 + n * 0.05).toStringAsFixed(2)),
          // Injector 1 runs inside its setting, injector 2 over it, so the
          // office sees one of each finding on the same determination.
          assignedInjector: Value(n <= 5 ? '1' : '2'),
          quidFinalMassG: Value(n <= 5
              ? '${(1400 + n * 3) * 100 ~/ 93}'
              : '${(1400 + n * 3) * 100 ~/ 88}'),
          quidGainG: const Value(''),
          quidPercent: Value(n <= 5 ? '7.${500 + n}' : '12.${100 + n}'),
        ),
    ]);
    for (final shotOf in [
      ('quid_1.jpg', 'Brine injector 2 - set QUID 8.0 percent'),
      ('quid_2.jpg', 'Carcass off the water chiller on the verified scale'),
    ]) {
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: quidUuid,
        kind: 'quid',
        filePath: shot(shotOf.$1),
        caption: Value(shotOf.$2),
        capturedAt: at,
      ));
    }

    for (final doc in [
      ('quid_doc_1.jpg', 'Verification record: Brine batch record BR-2291'),
      ('quid_doc_2.jpg', 'Verification record: Chiller temperature log'),
    ]) {
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: quidUuid,
        kind: 'document',
        filePath: shot(doc.$1),
        caption: Value(doc.$2),
        capturedAt: at,
      ));
    }

    // ------------------------------------------- certain raw processed meat
    final storage = await db.select(db.rawRmpStorageTypes).get();
    final labs = await db.select(db.rawRmpLaboratories).get();
    final categories = await db.select(db.rawRmpSampleCategories).get();
    final rawReasons = await db.select(db.rawRmpInspectionReasons).get();
    final rawItems = await (db.select(db.rawRmpChecklistItems)
          ..where((t) => t.isActive.equals(true)))
        .get();
    final marking =
        rawItems.where((i) => i.section == 'marking').map((i) => i.id).toList();
    final unmet = marking.length > 2
        ? marking.sublist(marking.length - 2).toSet()
        : <int>{};
    final metRaw = [
      for (final i in rawItems)
        if (!unmet.contains(i.id)) i.id,
    ];

    await raw.saveInspection(RawRmpInspectionsCompanion.insert(
      clientUuid: rawUuid,
      inspectedAt: at,
      updatedAt: at,
      visitUuid: Value(visitUuid),
      inspectorUsername: Value(username),
      status: const Value('ready'),
      facilityName: const Value(facility),
      facilityAddress: const Value(address),
      facilityTelephone: const Value('031 736 2000'),
      contactPerson: const Value(manager),
      contactPersonEmail: const Value(clientEmail),
      managerName: const Value(manager),
      managerEmail: const Value('manager@rainbow.test'),
      producerName: const Value('Karoo Meat Producers'),
      productItem: const Value('Boerewors'),
      batchNumber: const Value('4471'),
      reasonId: Value(rawReasons.isEmpty ? null : rawReasons.first.id),
      storageTypeId: Value(storage.isEmpty ? null : storage.first.id),
      markingLabelsPresent: const Value(true),
      scaleLabelsPresent: const Value(true),
      containersPresent: const Value(true),
      labelPackComplete: const Value(true),
      compliantItemIds: Value(metRaw.join(',')),
      isSampled: const Value(true),
      laboratoryId: Value(labs.isEmpty ? null : labs.first.id),
      sampleCategoryId: Value(categories.isEmpty ? null : categories.first.id),
      internalSampleNumber: const Value('RAW-2026-118'),
      testSampleSize: const Value('500 g'),
      calciumTestRequired: const Value(true),
      dnaSpeciesText: const Value('Beef / pork'),
      labInfoComplete: const Value(true),
      correctByDate: Value(at.add(const Duration(days: 8))),
      nonConformanceComments: const Value(
          'Product name absent from the marking label and no date of '
          'manufacture on the scale label.'),
      compositionChecklistJson: Value(CompositionChecklist.encode([
        for (var i = 0; i < CompositionChecklist.items.length; i++)
          CompositionAnswer(
            deviation: i == 1,
            contributionGrams: '${120 + i * 10}',
            remarks: i == 1 ? 'Fat above the class maximum.' : '',
          ),
      ])),
      compositionComments: const Value('Sampled for laboratory check.'),
      distanceTravelledKm: const Value(45),
      latitude: const Value(-29.8011),
      longitude: const Value(30.6423),
    ));
    await raw.saveDirection(RawRmpDirectionsCompanion.insert(
      clientUuid: rawDirectionUuid,
      issuedAt: at,
      updatedAt: at,
      inspectorUsername: Value(username),
      status: const Value('completed'),
      sourceInspectionUuid: Value(rawUuid),
      referenceNumber: Value(await raw.nextDirectionReference(
        inspectorUsername: username,
        clientName: facility,
        at: at,
      )),
      correctByDate: Value(at.add(const Duration(days: 8))),
      facilityName: const Value(facility),
      clientName: const Value(manager),
      clientEmail: const Value(clientEmail),
      producerName: const Value('Karoo Meat Producers'),
      batchNumber: const Value('4471'),
      remarks: const Value('Product name absent from the marking label.'),
      comments:
          const Value('Re-label the batch before it is offered for sale again.'),
      actionTaken: const Value('Batch withdrawn from the display cabinet.'),
      latitude: const Value(-29.8011),
      longitude: const Value(30.6423),
    ));
    for (final shotOf in [
      ('raw_1.jpg', 'Boerewors batch 4471 in the display cabinet'),
      ('raw_2.jpg', 'Scale label - product name absent'),
      ('raw_3.jpg', 'Sample RAW-2026-118 sealed for the laboratory'),
    ]) {
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: rawUuid,
        kind: 'rawrmp',
        filePath: shot(shotOf.$1),
        caption: Value(shotOf.$2),
        capturedAt: at,
      ));
    }

    // -------------------------------------------------------------- eggs
    final sizes = await db.select(db.eggSizes).get();
    final eggGrades = await db.select(db.eggGrades).get();
    final trays = await db.select(db.eggTraySizes).get();
    final facilityTypes = await db.select(db.eggFacilityTypes).get();
    final eggReasons = await db.select(db.eggInspectionReasons).get();
    final requirements = await (db.select(db.eggRequirements)
          ..where((t) => t.isActive.equals(true)))
        .get();
    final deviations = await db.select(db.eggDeviations).get();
    final failedRequirements = requirements.take(2).map((r) => r.id).toList();
    final dirty = deviations.isEmpty ? null : deviations.first.id;

    await eggs.saveInspection(
      EggInspectionsCompanion.insert(
        clientUuid: eggUuid,
        inspectedAt: at,
        updatedAt: at,
        visitUuid: Value(visitUuid),
        inspectorUsername: Value(username),
        status: const Value('ready'),
        facilityName: const Value(facility),
        facilityAddress: const Value(address),
        facilityPhone: const Value('031 736 2000'),
        facilityTypeId:
            Value(facilityTypes.isEmpty ? null : facilityTypes.first.id),
        reasonId: Value(eggReasons.isEmpty ? null : eggReasons.first.id),
        clientName: const Value(facility),
        clientAddress: const Value(address),
        clientContactPerson: const Value(manager),
        clientContactNumber: const Value('031 736 2000'),
        clientEmail: const Value(clientEmail),
        managerName: const Value(manager),
        managerEmail: const Value('manager@rainbow.test'),
        producerSupplier: const Value('Nulaid'),
        batchNumber: const Value('EGG-2026-0912'),
        bestBefore: Value(at.add(const Duration(days: 21))),
        traySizeId: Value(trays.isEmpty ? null : trays.first.id),
        declaredSizeId: Value(sizes.isEmpty ? null : sizes.first.id),
        declaredGradeId: Value(eggGrades.isEmpty ? null : eggGrades.first.id),
        sampleSize: const Value(60),
        outerLabellingAvailable: const Value(true),
        labelChecklistComplete: const Value(true),
        failedRequirementIds: Value(failedRequirements.join(',')),
        generalComments: const Value(
            'Sample of 60 eggs drawn from the consignment and weighed on the '
            'premises.'),
        nonConformanceComments: const Value(
            'Dirty and cracked shells above the permitted tolerance.'),
        latitude: const Value(-29.8011),
        longitude: const Value(30.6423),
      ),
      [
        for (var n = 1; n <= 60; n++)
          EggSamplesCompanion.insert(
            inspectionUuid: eggUuid,
            eggNumber: n,
            massG: Value(52.0 + (n % 11) * 1.4),
            // The Haugh unit is read on every tenth egg, as the form asks.
            albumenHeightMm: n % 10 == 0
                ? Value(5.4 + (n % 5) * 0.3)
                : const Value(null),
            haughUnit: n % 10 == 0
                ? Value(EggRules.haughUnit(
                    albumenHeightMm: 5.4 + (n % 5) * 0.3,
                    massG: 52.0 + (n % 11) * 1.4))
                : const Value(null),
            // A handful of the sample carries a shell deviation, which is
            // what puts the consignment outside the tolerance.
            deviationIds: Value(dirty != null && n % 17 == 0 ? '$dirty' : ''),
          ),
      ],
    );
    for (final shotOf in [
      ('egg', 'egg_tray.jpg', 'Sample trays drawn from the consignment'),
      ('label', 'egg_label.jpg', 'Tray label - large, grade A'),
      ('numbering', 'egg_numbering.jpg', 'Eggs numbered 1-60 before weighing'),
      ('deviation', 'egg_deviation.jpg', 'Dirty and cracked shells'),
    ]) {
      await eggs.addPhoto(EggPhotosCompanion.insert(
        inspectionUuid: eggUuid,
        kind: shotOf.$1,
        filePath: shot(shotOf.$2),
        caption: Value(shotOf.$3),
        capturedAt: at,
      ));
    }

    // ------------------------------------------------------ one sign-off
    final members = await visits.members(visitUuid);
    stdout.writeln('members: ${members.map((m) => m.kind).join(', ')}');
    expect(members.length, 5, reason: 'every commodity must be in the group');

    await visits.complete(
      visitUuid: visitUuid,
      managerSignaturePath: shot('sig_manager.png'),
      inspectorSignaturePath: shot('sig_inspector.png'),
      managerName: manager,
      inspectorName: inspectorName,
      latitude: -29.8011,
      longitude: 30.6423,
    );

    // ---------------------------------------------------------- send it up
    await poultry.upload((await poultry.inspectionByUuid(gradingUuid))!,
        token: token);
    await capture.uploadEvidenceFor(gradingUuid, token: token);
    await capture.uploadDirection((await capture.directionByUuid(gradingUuid))!,
        token: token);

    await capture.uploadLabelInspection(
        (await capture.labelInspectionByUuid(labelUuid))!,
        token: token);
    await capture.uploadEvidenceFor(labelUuid, token: token);

    await capture.uploadQuidInspection(
        (await capture.quidInspectionByUuid(quidUuid))!,
        token: token);
    await capture.uploadEvidenceFor(quidUuid, token: token);
    // What the office now holds for the determination, read back whole.
    final quidBack = jsonDecode((await http.get(
      Uri.parse('$baseUrl/api/poultry/quid-inspections/$quidUuid/'),
      headers: {'Authorization': 'Bearer $token'},
    ))
        .body) as Map<String, dynamic>;
    final backSamples = quidBack['samples'] as List;
    final backInjectors = quidBack['injectors'] as List;
    final backRecords = QuidVerificationRecord.decode(
        quidBack['verification_records_json'] as String);
    expect(quidBack['iteration_number'], '2');
    expect(quidBack['direction_required'], isTrue);
    expect(quidBack['injector_sampling_complete'], isTrue);
    expect(quidBack['quid_determination_complete'], isTrue);
    expect(quidBack['direction_action'], 'Batch BR-2291, 240 carcasses, held');
    expect(backSamples.length, 20, reason: 'both rounds, ten carcasses each');
    expect(backSamples.where((s) => s['iteration'] == 2).length, 10);
    expect(backSamples.where((s) => s['assigned_injector'] == '2').length, 10);
    expect(backInjectors.map((i) => i['name']),
        ['Injector 1 - brine', 'Injector 2 - brine']);
    expect(backRecords.map((r) => r.documentName),
        ['Brine batch record BR-2291', 'Chiller temperature log']);
    expect(backRecords.every((r) => r.hasPhoto), isTrue);
    stdout.writeln('quid read back: ${backSamples.length} carcasses, '
        '${backInjectors.length} injectors, ${backRecords.length} '
        'verification records, rejection ${quidBack['direction_required']}');

    await raw.upload((await raw.inspectionByUuid(rawUuid))!, token: token);
    await capture.uploadEvidenceFor(rawUuid, token: token);
    final rawDirection = (await raw.directions(username))
        .firstWhere((d) => d.clientUuid == rawDirectionUuid);
    await raw.uploadDirection(rawDirection, token: token);

    await eggs.upload((await eggs.inspectionByUuid(eggUuid))!, token: token);
    await eggs.uploadAttachments(eggUuid, token: token);

    // The group itself, with its Request for Invoice and every checklist the
    // members produced. This is what files the record in APS.
    final visit = (await visits.byUuid(visitUuid))!;
    final form = await invoices.formFor(visit);
    final rfi = await invoices.renderPdf(form);
    stdout.writeln('RFI ${await rfi.length()} bytes, '
        '${form.kilometres} km, ${form.normalHours} h');

    final sent = await visits.upload(
      visit,
      token: token,
      invoicePdf: rfi,
      kilometres: form.kilometres,
      hours: form.normalHours + form.overtimeHours + form.sundayHours,
    );
    expect(sent, isTrue, reason: 'the group did not reach the server');

    stdout.writeln('visit $visitUuid');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
