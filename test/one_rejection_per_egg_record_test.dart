import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/widgets.dart' as pw;

/// On 2 October 2026 two inspectors' grouped inspections never left their
/// phones: the sync said "Bad state: Too many elements". Each egg record
/// carried two rejections — the Rejection Form minted a new one every time
/// it was opened — and the one-rejection lookup the upload makes threw.
/// The lookup takes the newest and never throws, so the group goes up.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final when = DateTime.utc(2026, 10, 2, 7);

  Future<void> seed() async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('Omphile'),
          startedAt: when,
          facilityName: const Value('New Egg Producer'),
          completedAt: Value(when.add(const Duration(hours: 1))),
        ));
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: const Value('visit-1'),
          status: const Value('completed'),
          facilityName: const Value('New Egg Producer'),
        ));
    for (final (uuid, minutes) in [('dir-old', 10), ('dir-new', 20)]) {
      await db.into(db.eggDirections).insert(EggDirectionsCompanion.insert(
            clientUuid: uuid,
            inspectionUuid: const Value('egg-1'),
            issuedAt: when.add(Duration(minutes: minutes)),
            updatedAt: when.add(Duration(minutes: minutes)),
            status: const Value('completed'),
            qualityPart: const Value(true),
            clientName: const Value('New Egg Producer'),
          ));
    }
  }

  Future<void> paperAssets() async {
    FsaForm.useAssets(FsaFormAssets(
      regular: pw.Font.ttf(
          (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
              .buffer
              .asByteData()),
      bold: pw.Font.ttf(
          (await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
              .buffer
              .asByteData()),
      logo: pw.MemoryImage(
          await File('assets/images/FSA_Logo.png').readAsBytes()),
    ));
  }

  test('a record with two rejections answers with the newest, not an error',
      () async {
    await seed();
    final repository = EggsRepository(database: db, baseUrl: '');
    final direction = await repository.directionForInspection('egg-1');
    expect(direction?.clientUuid, 'dir-new');
  });

  test('the grouped inspection still goes up, with the rejection sheet',
      () async {
    await seed();
    await paperAssets();
    var body = '';
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        body = utf8.decode(request.bodyBytes, allowMalformed: true);
        return http.Response('{"id": 1}', 201);
      }),
    );
    final sent = await repository.upload(
        (await repository.pendingUploads()).single,
        token: 'jwt');
    expect(sent, isTrue);
    expect('"document_type":"direction"'.allMatches(body).length, 1);
  });

  test('a photo caption is cut to what the server keeps; an empty photo '
      'file is dropped rather than refused for ever', () async {
    await seed();
    final folder = Directory.systemTemp.createTempSync('fsa_egg_photos_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final full = File('${folder.path}/full.jpg')
      ..writeAsBytesSync(List<int>.filled(16, 1));
    final empty = File('${folder.path}/empty.jpg')..writeAsBytesSync([]);
    final long = 'Egg 12: ${List.filled(5, 'Soundness of Egg - Eggs with '
        'cracks that result in leakage').join('; ')}';
    expect(long.length, greaterThan(EggsRepository.maxCaptionLength));
    await db.into(db.eggPhotos).insert(EggPhotosCompanion.insert(
          inspectionUuid: 'egg-1',
          kind: 'egg',
          filePath: full.path,
          capturedAt: when,
          caption: Value(long),
        ));
    await db.into(db.eggPhotos).insert(EggPhotosCompanion.insert(
          inspectionUuid: 'egg-1',
          kind: 'egg',
          filePath: empty.path,
          capturedAt: when,
        ));

    final captions = <String>[];
    final repository = EggsRepository(
      database: db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        final text = utf8.decode(request.bodyBytes, allowMalformed: true);
        final m = RegExp(r'name="caption"\r\n\r\n([^\r]*)').firstMatch(text);
        if (m != null) captions.add(m.group(1)!);
        return http.Response('{"id": 1}', 201);
      }),
    );
    await repository.uploadAttachments('egg-1', token: 'jwt');

    expect(captions, hasLength(1), reason: 'the empty file is not sent');
    expect(captions.single.length, EggsRepository.maxCaptionLength);
    expect(captions.single, startsWith('Egg 12: Soundness'));
    final left = await repository.photosFor('egg-1');
    expect(left.map((p) => p.filePath), [full.path]);
    expect(left.single.isUploaded, isTrue);
  });
}
