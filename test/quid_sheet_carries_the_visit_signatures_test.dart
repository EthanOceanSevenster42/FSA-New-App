import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The QUID sheet carries the visit's two signatures (Ethan, 2026-10-04).
///
/// A grouped inspection signs once at the end, and that pair of signatures
/// is stamped onto every record in it. The QUID Determination Checklist
/// built afterwards — for upload, or to view — must print both; a sheet
/// with empty signature rules is a record nobody signed for.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  late PoultryCaptureRepository capture;
  late PoultryRepository poultry;
  late Directory scratch;
  final when = DateTime(2026, 10, 4, 9, 30);
  const visitUuid = 'visit-1';
  const quidUuid = 'quid-1';

  TestWidgetsFlutterBinding.ensureInitialized();
  installFsaFormAssets();

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    capture = PoultryCaptureRepository(database: db, baseUrl: '');
    poultry = PoultryRepository(database: db, baseUrl: '');
    scratch = await Directory.systemTemp.createTemp('fsa-quid-signatures');
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
        ));
    // A determination weighed through on one injector, waiting on the
    // group's sign-off.
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: quidUuid,
      inspectedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('ethan'),
      visitUuid: const Value(visitUuid),
      facilityName: const Value('Rainbow Chickens - Hammarsdale'),
      isWaterChilled: const Value(false),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
      status: const Value('ready'),
    ));
    await capture.replaceQuidInjectors(quidUuid, [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: quidUuid,
        position: 1,
        name: const Value('Brine 1'),
        quidPercent: const Value('15'),
      ),
    ]);
    await capture.replaceQuidSamples(quidUuid, [
      for (var n = 1; n <= 5; n++)
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: quidUuid,
          carcassNumber: Value('$n'),
          injectorNumber: const Value('Brine 1'),
          assignedInjector: const Value('1'),
          initialMassG: const Value('1000'),
          beforeMassG: const Value('1000'),
          injectorAfterMassG: const Value('1100'),
          gainG: const Value('100'),
          injectorRatePercent: const Value('10.000'),
          quidFinalMassG: const Value('1120'),
          quidPercent: const Value('10.714'),
        ),
    ]);
  });
  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) await scratch.delete(recursive: true);
  });

  /// A signing pad's PNG: a stroke of ink on a transparent box.
  Future<String> pad(String name) async {
    final canvas = img.Image(width: 300, height: 100, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0));
    img.drawLine(canvas,
        x1: 20, y1: 70, x2: 280, y2: 30,
        color: img.ColorRgba8(20, 30, 90, 255), thickness: 4);
    final file = File('${scratch.path}/$name.png');
    await file.writeAsBytes(img.encodePng(canvas));
    return file.path;
  }

  /// How many images a PDF embeds — the letterhead's on every build, and
  /// the signatures' once the visit is signed.
  Future<int> imagesIn(File pdf) async {
    final text = latin1.decode(await pdf.readAsBytes(), allowInvalid: true);
    return RegExp(r'/Subtype\s*/Image').allMatches(text).length;
  }

  test('both signatures are printed on the QUID sheet after the sign-off',
      () async {
    final unsignedDir = await Directory('${scratch.path}/unsigned').create();
    final unsigned = await poultry.buildQuidChecklist(quidUuid,
        into: unsignedDir);
    expect(unsigned, isNotNull);
    final before = await imagesIn(unsigned!);

    await visits.complete(
      visitUuid: visitUuid,
      managerSignaturePath: await pad('manager'),
      inspectorSignaturePath: await pad('inspector'),
      managerName: 'T. Dlamini',
      inspectorName: 'CINGA NGONGO',
    );

    final signedDir = await Directory('${scratch.path}/signed').create();
    final signed = await poultry.buildQuidChecklist(quidUuid, into: signedDir);
    expect(signed, isNotNull);
    // A pad signature is a PNG with transparency, which the PDF embeds as
    // the picture and its alpha mask — so more than one image per
    // signature, never the same count as the unsigned sheet.
    expect(await imagesIn(signed!), greaterThanOrEqualTo(before + 2),
        reason: 'the inspector\'s and the manager\'s signatures');
  });
}
