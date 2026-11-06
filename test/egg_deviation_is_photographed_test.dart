import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// Egg deviations are photographed from one row at the foot of the
/// deviation list, not a prompt on every deviation ticked. Six are kept at
/// most, and with six taken a less important one can be removed to make
/// room (Ethan, 2026-09-29).
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;
  late Directory folder;

  // A 1×1 PNG, so the thumbnails have something real to draw.
  final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    folder = Directory.systemTemp.createTempSync('egg-deviation-photos');
    PhotoStorage.overrideForTesting(folder);

    final large = (await db.select(db.eggSizes).get())
        .firstWhere((s) => s.name == 'Large');
    final grade1 = (await db.select(db.eggGrades).get())
        .firstWhere((g) => g.name == 'Grade 1');
    final tray = (await db.select(db.eggTraySizes).get())
        .firstWhere((t) => t.name == '12-Pack');
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-photos',
          inspectedAt: DateTime(2026, 9, 29, 9),
          updatedAt: DateTime(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          batchNumber: const Value('B123'),
          bestBefore: Value(DateTime(2026, 10, 20)),
          declaredSizeId: Value(large.id),
          declaredGradeId: Value(grade1.id),
          traySizeId: Value(tray.id),
          haughNotRequired: const Value(true),
        ));
    // Three weighed eggs; the form opens on the last.
    for (var i = 1; i <= 3; i++) {
      await db.into(db.eggSamples).insert(EggSamplesCompanion.insert(
            inspectionUuid: 'egg-photos',
            eggNumber: i,
            massG: const Value(55.0),
          ));
    }
  });
  tearDown(() async {
    PhotoStorage.resetForTesting();
    await db.close();
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  Future<void> seedDeviationPhotos(int count) async {
    for (var i = 1; i <= count; i++) {
      final file = File('${folder.path}/shot_$i.png')..writeAsBytesSync(pixel);
      await db.into(db.eggPhotos).insert(EggPhotosCompanion.insert(
            inspectionUuid: 'egg-photos',
            kind: 'egg',
            filePath: file.path,
            caption: Value('Egg $i: Blood Spot'),
            capturedAt: DateTime(2026, 9, 29, 9, i),
          ));
    }
  }

  Future<void> openAndTickBloodSpot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        resumeUuid: 'egg-photos',
        visit: const VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Kroon Foods',
          facilityAddress: '',
          facilityPhone: '',
          contactPerson: '',
          contactEmail: '',
          representative: '',
          managerName: '',
          managerEmail: '',
          facilityType: 'Packhouse',
          inspectionReason: 'Inspection',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final row = find.text('Blood Spot - Light intensity, ≤ 1mm diameter');
    await tester.scrollUntilVisible(row, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final slider = tester.widget<ComplianceSlider>(find.descendant(
      of: find.ancestor(of: row, matching: find.byType(Row)).first,
      matching: find.byType(ComplianceSlider),
    ));
    slider.onChanged(false);
    await tester.pumpAndSettle();
  }

  /// The Capture button on the "Deviation photos" row under the list.
  Future<void> captureFromTheRow(WidgetTester tester) async {
    final row = find.text('Deviation photos');
    await tester.scrollUntilVisible(row, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final capture = find
        .descendant(
          of: find.ancestor(of: row, matching: find.byType(Column)).first,
          // One wording on every form (Ethan, 2026-09-30).
          matching: find.text('Take photo'),
        )
        .first;
    await tester.ensureVisible(capture);
    await tester.pumpAndSettle();
    await tester.tap(capture);
    await tester.pumpAndSettle();
  }

  testWidgets('ticking a deviation does not stop for a photo',
      (tester) async {
    await openAndTickBloodSpot(tester);

    expect(find.text('Photograph this deviation'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    // The photo is taken from the row under the list instead.
    await tester.scrollUntilVisible(find.text('Deviation photos'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Deviation photos'), findsOneWidget);
    expect(find.textContaining('maximum of 6'), findsWidgets);
  });

  testWidgets('with six taken, one can be removed to make room',
      (tester) async {
    await tester.runAsync(() => seedDeviationPhotos(6));
    await openAndTickBloodSpot(tester);
    await captureFromTheRow(tester);

    expect(find.text('All 6 deviation photos taken'), findsOneWidget);
    final takePhoto = find.widgetWithText(FilledButton, 'Take photo');
    expect(tester.widget<FilledButton>(takePhoto).onPressed, isNull,
        reason: 'no room until one is removed');

    await tester.tap(find
        .descendant(
            of: find.byType(AlertDialog),
            matching: find.byTooltip('Remove photo'))
        .first);
    // The file comes off the disk for real; let it.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Room for one more photo'), findsOneWidget);
    expect(tester.widget<FilledButton>(takePhoto).onPressed, isNotNull);
    final left = await tester.runAsync(() => (db.select(db.eggPhotos)
          ..where((t) => t.kind.equals('egg')))
        .get());
    expect(left, hasLength(5));

    await tester.tap(find.text('Keep these'));
    await tester.pumpAndSettle();
  });
}
