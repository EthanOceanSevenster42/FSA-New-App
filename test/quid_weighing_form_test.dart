import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/eggs/presentation/date_field.dart';
import 'package:fsa_app/features/poultry/domain/quid_flow.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_quid_continue_page.dart';

/// A one-pixel PNG: what the fake camera hands back.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==';

/// The QUID weighing screen, walked the way the original walks it: one
/// carcass at a time, chilling → injector → determination, each stage
/// checked and confirmed before the next opens, a failure repeated once and
/// then rejected.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;
  late Directory shots;
  late Directory store;
  var shotCount = 0;
  final when = DateTime(2026, 9, 1, 9, 30);

  /// Stands in for the camera: writes a picture and hands its path back.
  Future<String?> fakeCamera(BuildContext context,
      {required String title}) async {
    final file = File('${shots.path}/shot_${shotCount++}.png');
    file.writeAsBytesSync(base64Decode(_onePixelPng));
    return file.path;
  }

  setUp(() async {
    shots = Directory.systemTemp.createTempSync('quid_shots_');
    store = Directory.systemTemp.createTempSync('quid_store_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'quid-1',
      inspectedAt: when,
      updatedAt: when,
      facilityName: const Value('Rainbow Chickens - Hammarsdale'),
      isWaterChilled: const Value(true),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
    ));
    // Set to 8%: whole carcass, so the limit is 9%.
    await capture.replaceQuidInjectors('quid-1', [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: 'quid-1',
        position: 1,
        name: const Value('Brine 1'),
        quidPercent: const Value('8'),
      ),
    ]);
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    for (final d in [shots, store]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> setStage({
    int iteration = 1,
    bool chilling = false,
    bool injector = false,
    bool determination = false,
    String visit = '',
  }) =>
      (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(PoultryQuidInspectionsCompanion(
        iterationNumber: Value('$iteration'),
        waterChillingComplete: Value(chilling),
        injectorSamplingComplete: Value(injector),
        quidDeterminationComplete: Value(determination),
        visitUuid: Value(visit),
      ));

  /// Five carcasses in [iteration]: 1000 g in, [waterFinal] off the
  /// chiller, 1020 → 1100 g on the injector, [quidFinal] off the process.
  Future<void> seedFive({
    int iteration = 1,
    String waterFinal = '1020',
    String injector = '',
    String quidFinal = '',
  }) async {
    final existing = await capture.quidSamples('quid-1');
    await capture.replaceQuidSamples('quid-1', [
      for (final s in existing) s.toCompanion(false).copyWith(id: const Value.absent()),
      for (var n = 0; n < 5; n++)
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: 'quid-1',
          iteration: Value(iteration),
          initialMassG: const Value('1000'),
          finalMassG: Value(waterFinal),
          assignedInjector: Value(injector),
          beforeMassG: Value(injector.isEmpty ? '' : '1020'),
          injectorAfterMassG: Value(injector.isEmpty ? '' : '1100'),
          quidFinalMassG: Value(quidFinal),
        ),
    ]);
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final inspection =
        (await db.select(db.poultryQuidInspections).get()).single;
    await tester.pumpWidget(MaterialApp(
      home: PoultryQuidWeighingForm(
        repository:
            PoultryRepository(database: db, baseUrl: 'http://example.test'),
        captureRepository: capture,
        inspection: inspection,
        takePhoto: fakeCamera,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder labelled(String label) => find.byWidgetPredicate(
      (w) => w is RequiredLabel && w.label == label);

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final field = find.descendant(
      of: find.ancestor(of: labelled(label), matching: find.byType(LabelledField)),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  /// Turns a YES/NO question on, as the inspector slides it.
  Future<void> yes(WidgetTester tester, String label) async {
    final target = find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(YesNoQuestion)),
      matching: find.text('YES'),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Presses Take Photo. The picture is moved into the photo store for
  /// real, which only the real event loop can do, so the press runs there
  /// and the test waits for the form to say the photograph is in.
  Future<void> photograph(WidgetTester tester) async {
    await tester.runAsync(() async {
      await press(tester, 'Take Photo');
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .text('Photograph taken for this document.')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });
    await tester.pumpAndSettle();
  }

  group('chilling', () {
    testWidgets('opens on the carcass set, not the injector or the QUID',
        (tester) async {
      await open(tester);
      expect(find.text('Sample # 1'), findsOneWidget);
      expect(find.text('CREATE SAMPLE SET'), findsOneWidget);
      expect(find.text('WATER CHILLING RESULTS'), findsOneWidget);
      expect(find.text('INJECTOR INFO'), findsNothing);
      expect(find.text('DETERMINATION OF QUID'), findsNothing);
    });

    testWidgets('Next asks for the initial mass first', (tester) async {
      await open(tester);
      await press(tester, 'Next');
      expect(find.text('No Initial Mass has been inputted.'), findsOneWidget);
    });

    testWidgets('Next after the initial mass moves to the next carcass',
        (tester) async {
      await open(tester);
      await enter(tester, 'Initial Carcass Weight (g)', '1000');
      await press(tester, 'Next');
      expect(find.text('Sample # 2'), findsOneWidget);
    });

    testWidgets('the pick-up is worked out over the final mass, red over 7%',
        (tester) async {
      await open(tester);
      await enter(tester, 'Initial Carcass Weight (g)', '1000');
      await enter(tester, 'Final Mass (g)', '1100');
      // (1100 − 1000) / 1100 × 100
      expect(find.text('9.091 %'), findsWidgets);
      final chip = tester.widget<Text>(find.text('9.091 %').first);
      expect(chip.style?.color, const Color(0xFFC62828));
    });

    testWidgets('a final mass under the initial is refused', (tester) async {
      await open(tester);
      await enter(tester, 'Initial Carcass Weight (g)', '1000');
      await enter(tester, 'Final Mass (g)', '990');
      expect(find.textContaining('cannot be less than that of the initial'),
          findsOneWidget);
    });

    testWidgets('will not close with fewer than five carcasses',
        (tester) async {
      await open(tester);
      await yes(tester, 'Water Chilling for Samples Complete');
      expect(find.text('Insufficient Sample Size'), findsOneWidget);
    });

    testWidgets('closes with five, confirmed, and opens the injector stage',
        (tester) async {
      await seedFive();
      await open(tester);
      await yes(tester, 'Water Chilling for Samples Complete');
      expect(find.text('Confirm Completion'), findsOneWidget);
      await press(tester, 'Confirm');
      expect(find.text('INJECTOR INFO'), findsOneWidget);
      expect(find.text('CREATE SAMPLE SET'), findsNothing);
      expect(find.textContaining('Water chilling complete'), findsOneWidget);
    });

    testWidgets('over 7% on the first round: the sample set is weighed again',
        (tester) async {
      await seedFive(waterFinal: '1100');
      await open(tester);
      await yes(tester, 'Water Chilling for Samples Complete');
      await press(tester, 'Confirm');
      expect(find.text('Redo Inspection'), findsOneWidget);
      await press(tester, 'Ok');
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('CREATE SAMPLE SET'), findsOneWidget);
      // The first round stays on the record.
      final saved = await capture.quidSamples('quid-1');
      expect(saved.where((s) => s.iteration == 1), hasLength(5));
    });

    testWidgets('over 7% on the second round: a rejection', (tester) async {
      await setStage(iteration: 2);
      await seedFive(iteration: 2, waterFinal: '1100');
      await open(tester);
      await yes(tester, 'Water Chilling for Samples Complete');
      await press(tester, 'Confirm');
      expect(find.text('Rejection Issued'), findsOneWidget);
      await press(tester, 'Ok');
      // FSA-SOP-APS-001 Annexure C seizes on a QUID deviation, so the
      // question is put the moment the rejection is issued.
      expect(find.text('This consignment must be seized'), findsOneWidget);
      await press(tester, 'Carry on inspecting');
      expect(find.text('REJECTION FORM'), findsOneWidget);
      expect(find.textContaining('above the 7% allowed'), findsWidgets);
      expect(find.textContaining('Seizure declined'), findsOneWidget);
      final row = (await db.select(db.poultryQuidInspections).get()).single;
      expect(row.directionRequired, isTrue);
      expect(row.seizureDecision, 'inspect');
      final today = DateTime.now();
      expect(row.correctByDate, DateTime(today.year, today.month, today.day));
    });
  });

  group('injector', () {
    testWidgets('will not close until every injector has five',
        (tester) async {
      await setStage(chilling: true);
      await seedFive();
      await open(tester);
      await yes(tester, 'Injector(s) Sampling Complete');
      await press(tester, 'Confirm to QUID Determination');
      expect(find.text('Incomplete min. sample set'), findsOneWidget);
    });

    testWidgets('closes with five and opens the determination',
        (tester) async {
      await setStage(chilling: true);
      await seedFive(injector: '1');
      await open(tester);
      await yes(tester, 'Injector(s) Sampling Complete');
      await press(tester, 'Confirm to QUID Determination');
      expect(find.text('DETERMINATION OF QUID'), findsOneWidget);
      expect(find.text('INJECTOR INFO'), findsNothing);
    });
  });

  group('determination', () {
    testWidgets('within the limit: complete, no rejection', (tester) async {
      await setStage(chilling: true, injector: true);
      // (1080 − 1000) / 1080 = 7.407%, under 8 + 1.
      await seedFive(injector: '1', quidFinal: '1080');
      await open(tester);
      await yes(tester, 'QUID Determintion Complete');
      await press(tester, 'Proceed');
      expect(find.textContaining('QUID determination complete'), findsOneWidget);
      expect(find.text('REJECTION FORM'), findsNothing);
    });

    testWidgets('over the limit on the first round: repeated',
        (tester) async {
      await setStage(chilling: true, injector: true);
      // (1120 − 1000) / 1120 = 10.714%, over 9.
      await seedFive(injector: '1', quidFinal: '1120');
      await open(tester);
      await yes(tester, 'QUID Determintion Complete');
      await press(tester, 'Proceed');
      expect(find.text('QUID Deviation Present'), findsOneWidget);
      await press(tester, 'Ok');
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('CREATE SAMPLE SET'), findsOneWidget);
    });

    testWidgets('over the limit on the second round: a rejection',
        (tester) async {
      await setStage(iteration: 2, chilling: true, injector: true);
      await seedFive(iteration: 2, injector: '1', quidFinal: '1120');
      await open(tester);
      await yes(tester, 'QUID Determintion Complete');
      await press(tester, 'Proceed');
      expect(find.text('This consignment must be seized'), findsOneWidget);
      await press(tester, 'Proceed with seizure');
      // Seizing asks the Annexure E particulars before anything is written.
      expect(find.text('Seizure particulars'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('seizure-quantity')), '12 carcasses');
      await press(tester, 'Record seizure');
      expect(find.text('REJECTION FORM'), findsOneWidget);
      expect(find.textContaining('Brine 1: average QUID 10.714%'),
          findsWidgets);
      expect(find.textContaining('Seizure under section 8'), findsOneWidget);
      final row = (await db.select(db.poultryQuidInspections).get()).single;
      expect(row.seizureDecision, 'seize');
      final seizure = (await db.select(db.seizures).get()).single;
      expect(seizure.recordKind, 'quid');
      expect(seizure.quantity, '12 carcasses');
    });

    testWidgets('a repeat is allowed once', (tester) async {
      await setStage(iteration: 2, chilling: true, injector: true);
      await seedFive(iteration: 2, injector: '1', quidFinal: '1080');
      await open(tester);
      expect(find.text('Repeat QUID Determine Vertification'), findsNothing);
    });
  });

  group('lists as the original draws them', () {
    testWidgets('the chilling list grows with each carcass weighed in',
        (tester) async {
      await seedFive();
      await open(tester);
      expect(find.text('Chill Method'), findsOneWidget);
      expect(find.text('Initial Weight (g)'), findsOneWidget);
      // Five rows say Water, and the QUID Info line makes six.
      expect(find.text('Water'), findsNWidgets(6));
    });

    testWidgets('each injector lists its carcasses with the average rate',
        (tester) async {
      await setStage(chilling: true);
      await seedFive(injector: '1');
      await open(tester);
      expect(find.text('Brine 1'), findsWidgets);
      expect(find.text('Inj. Rate'), findsOneWidget);
      expect(find.text('Average Injector Rate (%)'), findsOneWidget);
      // 80 g on 1100 g, five times and once as the average.
      expect(find.text('7.273'), findsNWidgets(6));
    });

    testWidgets('the determination lists set against calculated per injector',
        (tester) async {
      await setStage(chilling: true, injector: true);
      await seedFive(injector: '1', quidFinal: '1100');
      await open(tester);
      expect(find.text('Injector: Brine 1'), findsOneWidget);
      expect(find.text('Set QUID (%)'), findsOneWidget);
      expect(find.text('Calc. QUID (%)'), findsOneWidget);
      expect(find.text('Average QUID %'), findsOneWidget);
      expect(find.text('9.091'), findsWidgets);
    });

    testWidgets('the regulated standard is stated on the record',
        (tester) async {
      await open(tester);
      expect(
          find.text('10% for whole carcasses, judged with a 1.0% tolerance'),
          findsOneWidget);
    });

    testWidgets('the verification date starts as today', (tester) async {
      await open(tester);
      final today = DateTime.now();
      final field = tester.widget<DateField>(find.byWidgetPredicate(
          (w) => w is DateField && w.label == 'Date'));
      expect(field.value, isNotNull);
      expect(
          [field.value!.year, field.value!.month, field.value!.day],
          [today.year, today.month, today.day]);
    });
  });

  group('verification of records', () {
    testWidgets('a document is not added without its photograph',
        (tester) async {
      await open(tester);
      await enter(tester, 'Name/Document Number', 'Injector log 14');
      await press(tester, 'Add');
      expect(find.text('Document photograph'), findsOneWidget);
    });

    testWidgets('keeps a list, one Add at a time, each with its photograph',
        (tester) async {
      await open(tester);
      await enter(tester, 'Name/Document Number', 'Injector log 14');
      await photograph(tester);
      expect(find.text('Photograph taken for this document.'), findsOneWidget);
      await press(tester, 'Add');
      await press(tester, 'Proceed');
      await enter(tester, 'Name/Document Number', 'Chiller log 3');
      await photograph(tester);
      await press(tester, 'Add');
      await press(tester, 'Proceed');
      expect(find.textContaining('1. Injector log 14'), findsOneWidget);
      expect(find.textContaining('2. Chiller log 3'), findsOneWidget);

      // Each keeps its photograph, stored as a document photo of the
      // record — not as one of the rejection's.
      await press(tester, 'Temporary Save');
      final saved = (await db.select(db.poultryQuidInspections).get()).single;
      final records =
          QuidVerificationRecord.decode(saved.verificationRecordsJson);
      expect(records.map((r) => r.hasPhoto), [true, true]);
      final documents = await capture.photosFor('quid-1', kind: 'document');
      expect(documents.length, 2);
      expect(documents.map((p) => p.filePath), records.map((r) => r.photoPath));
      expect(documents.every((p) => File(p.filePath).existsSync()), isTrue);
      expect(await capture.photosFor('quid-1', kind: 'quid'), isEmpty);
    });

    testWidgets('Clear List takes the photographs with it', (tester) async {
      await open(tester);
      await enter(tester, 'Name/Document Number', 'Injector log 14');
      await photograph(tester);
      await press(tester, 'Add');
      await press(tester, 'Proceed');
      await press(tester, 'Clear List');
      await press(tester, 'Clear');
      expect(find.textContaining('1. Injector log 14'), findsNothing);
      expect(await capture.photosFor('quid-1', kind: 'document'), isEmpty);
    });
  });

  group('submitting', () {
    testWidgets('refused until the determination is complete',
        (tester) async {
      await open(tester);
      await press(tester, 'Submit Checklist');
      expect(find.text('Checklist not complete'), findsOneWidget);
    });

    testWidgets('a rejection asks for its remarks and batch first',
        (tester) async {
      await setStage(chilling: true, injector: true, determination: true);
      await (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(const PoultryQuidInspectionsCompanion(
              directionRequired: Value(true),
              directionReason: Value('Brine 1 over.')));
      await open(tester);
      await press(tester, 'Submit Checklist');
      expect(find.text('Rejection details missing'), findsOneWidget);
    });

    testWidgets('a rejection asks for two photographs', (tester) async {
      await setStage(chilling: true, injector: true, determination: true);
      await (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(const PoultryQuidInspectionsCompanion(
              directionRequired: Value(true),
              directionReason: Value('Brine 1 over.'),
              directionRemarks: Value('• Over the set QUID'),
              directionAction: Value('Batch 12 removed')));
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: 'quid-1',
        kind: 'quid',
        filePath: '/nowhere/one.jpg',
        capturedAt: when,
      ));
      await open(tester);
      // Taken from the rejection block, as "Add Photo [0/2]" is.
      expect(find.text('REJECTION PHOTOGRAPHS'), findsOneWidget);
      expect(find.text('Add Photo'), findsOneWidget);
      await press(tester, 'Submit Checklist');
      expect(find.text('Rejection photographs'), findsOneWidget);
      expect(find.textContaining('1 of 2 taken'), findsWidgets);
    });

    testWidgets('without a rejection, no photographs are asked for',
        (tester) async {
      await setStage(chilling: true, injector: true, determination: true);
      await open(tester);
      expect(find.text('REJECTION PHOTOGRAPHS'), findsNothing);
      await press(tester, 'Submit Checklist');
      expect(find.text('Submit Confirmation'), findsOneWidget);
    });
  });

  group('abandoning', () {
    testWidgets('Abandon Checklist removes the determination and all under it',
        (tester) async {
      await seedFive();
      await capture.addPhoto(PoultryPhotosCompanion.insert(
        recordUuid: 'quid-1',
        kind: 'quid',
        filePath: '/nowhere/one.jpg',
        capturedAt: when,
      ));
      await capture.saveSignature(PoultrySignaturesCompanion.insert(
        recordUuid: 'quid-1',
        role: 'inspector',
        signedAt: when,
      ));
      await open(tester);
      await press(tester, 'Abandon Checklist');
      expect(find.text('Abandon QUID Determination'), findsOneWidget);
      await press(tester, 'Proceed to abandon');
      expect(find.text('Removed Data'), findsOneWidget);
      await press(tester, 'Ok');
      expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
      expect(await capture.quidSamples('quid-1'), isEmpty);
      expect(await capture.quidInjectors('quid-1'), isEmpty);
      expect(await capture.photosFor('quid-1'), isEmpty);
      expect(await capture.signaturesFor('quid-1'), isEmpty);
    });

    testWidgets('backing out keeps everything', (tester) async {
      await seedFive();
      await open(tester);
      await press(tester, 'Abandon Checklist');
      await press(tester, 'Return to inspection');
      expect((await capture.quidSamples('quid-1')).length, 5);
      expect(await db.select(db.poultryQuidInspections).get(), hasLength(1));
    });

    testWidgets('a determination already on the server cannot be abandoned',
        (tester) async {
      await (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(const PoultryQuidInspectionsCompanion(
              isUploaded: Value(true)));
      await open(tester);
      final button = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Abandon Checklist'),
          matching: find.byType(OutlinedButton)));
      expect(button.onPressed, isNull);
      expect(find.textContaining('already on the server'), findsOneWidget);
    });
  });

  group('signatures', () {
    testWidgets('asks for its own only when it stands alone', (tester) async {
      await open(tester);
      expect(find.text('SIGNATURES CONTROL'), findsOneWidget);
    });

    testWidgets('inside a visit it signs with the group', (tester) async {
      await setStage(visit: 'visit-1');
      await open(tester);
      expect(find.text('SIGNATURES CONTROL'), findsNothing);
      expect(find.textContaining('part of a grouped inspection'),
          findsOneWidget);
    });
  });

  testWidgets('what is weighed is saved against its carcass and round',
      (tester) async {
    await open(tester);
    await enter(tester, 'Initial Carcass Weight (g)', '1000');
    await enter(tester, 'Final Mass (g)', '1020');
    await press(tester, 'Temporary Save');
    final saved = (await capture.quidSamples('quid-1')).single;
    expect(saved.initialMassG, '1000');
    expect(saved.finalMassG, '1020');
    expect(saved.pickupPercent, '1.961');
    expect(saved.iteration, 1);
  });
}
