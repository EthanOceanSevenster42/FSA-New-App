import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';

/// Each injector gets its own QUID report (Ethan, 2026-10-05): one file per
/// injector, not one combined sheet.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;
  late PoultryRepository poultry;
  late Directory out;
  final when = DateTime(2026, 10, 5, 9, 0);

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installFsaFormAssets);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    capture = PoultryCaptureRepository(database: db, baseUrl: '');
    poultry = PoultryRepository(database: db, baseUrl: '');
    out = await Directory.systemTemp.createTemp('fsa-quid-per-injector');
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'quid-1',
      inspectedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('ethan'),
      facilityName: const Value('Rainbow Chickens'),
      isWaterChilled: const Value(false),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
    ));
    await capture.replaceQuidInjectors('quid-1', [
      PoultryQuidInjectorsCompanion.insert(
          inspectionUuid: 'quid-1',
          position: 1,
          name: const Value('Brine A'),
          quidPercent: const Value('15')),
      PoultryQuidInjectorsCompanion.insert(
          inspectionUuid: 'quid-1',
          position: 2,
          name: const Value('Brine B'),
          quidPercent: const Value('15')),
    ]);
    await capture.replaceQuidSamples('quid-1', [
      for (final p in [1, 2])
        for (var n = 1; n <= 5; n++)
          PoultryQuidSamplesCompanion.insert(
            inspectionUuid: 'quid-1',
            carcassNumber: Value('$n'),
            assignedInjector: Value('$p'),
            injectorNumber: Value(p == 1 ? 'Brine A' : 'Brine B'),
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
    if (out.existsSync()) await out.delete(recursive: true);
  });

  test('quidReportInjectors lists each weighed injector', () async {
    final list = await poultry.quidReportInjectors('quid-1');
    expect(list.map((e) => e.name), ['Brine A', 'Brine B']);
    expect(list.map((e) => e.position), [1, 2]);
  });

  test('each injector builds its own report file', () async {
    final a = await poultry.buildQuidChecklist('quid-1',
        into: out, injectorPosition: 1, onlyThisInjector: true);
    final b = await poultry.buildQuidChecklist('quid-1',
        into: out, injectorPosition: 2, onlyThisInjector: true);
    expect(a, isNotNull);
    expect(b, isNotNull);
    // Two distinct files, each named for its injector.
    expect(a!.path, isNot(b!.path));
    expect(a.path, contains('Brine-A'));
    expect(b.path, contains('Brine-B'));
    expect(a.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);
    expect(await a.length(), greaterThan(1000));
  });

  test('an unknown injector position yields no report', () async {
    final none = await poultry.buildQuidChecklist('quid-1',
        into: out, injectorPosition: 9, onlyThisInjector: true);
    expect(none, isNull);
  });
}
