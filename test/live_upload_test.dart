@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// End-to-end upload against a real running backend.
///
/// This exercises the shipping `EggsRepository.upload()` — the same code the
/// handset runs — over real HTTP, including the multipart image post. Mocked
/// tests prove the client builds the right request; only this proves the
/// server accepts it and gives it back.
///
/// Skipped unless a server is named, so the normal suite stays hermetic:
///
///     FSA_LIVE_BASE_URL=http://192.168.2.2:8010 \
///     FSA_LIVE_USER=Ethan FSA_LIVE_PASSWORD=... \
///     flutter test test/live_upload_test.dart --tags live
void main() {
  final baseUrl = Platform.environment['FSA_LIVE_BASE_URL'];
  final username = Platform.environment['FSA_LIVE_USER'];
  final password = Platform.environment['FSA_LIVE_PASSWORD'];

  if (baseUrl == null || username == null || password == null) {
    test('live upload', () {}, skip: 'FSA_LIVE_* environment not set.');
    return;
  }

  late LocalDatabase db;
  late EggsRepository repo;
  late String token;
  late Directory scratch;

  setUpAll(() async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'device_id': 'live-test-harness',
            'device_model': 'flutter test',
          }),
        )
        .timeout(const Duration(seconds: 30));

    expect(response.statusCode, 200, reason: 'login transport failed');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['outcome'], 'success', reason: 'login rejected: ${response.body}');
    token = body['access'] as String;
  });

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(baseUrl: baseUrl, database: db);
    scratch = await Directory.systemTemp.createTemp('fsa_live_');
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });

  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  /// Smallest thing Django's ImageField will accept: a real 1x1 PNG.
  File writePng(String name) {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
        'IQAAAABJRU5ErkJggg==';
    final file = File('${scratch.path}/$name')
      ..writeAsBytesSync(base64Decode(pngBase64));
    return file;
  }

  Future<Map<String, dynamic>?> fetchFromServer(String uuid) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/eggs/inspections/'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    expect(response.statusCode, 200);
    final decoded = jsonDecode(response.body);
    final rows = (decoded is Map<String, dynamic>
            ? (decoded['results'] as List<dynamic>? ?? const [])
            : decoded as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final row in rows) {
      if (row['client_uuid'] == uuid) return row;
    }
    return null;
  }

  test('an inspection, its eggs and its photos reach the server', () async {
    // A real v4 uuid: the server rejects anything else, and the app itself
    // generates one per inspection. Fresh each run, so a rerun neither
    // collides with nor asserts against a previous run's record.
    final uuid = const Uuid().v4();
    final capturedAt = DateTime.now().subtract(const Duration(hours: 3));
    final at = DateTime.now();

    await repo.saveInspection(
      EggInspectionsCompanion.insert(
        clientUuid: uuid,
        inspectedAt: at,
        updatedAt: at,
        status: const Value('completed'),
        facilityName: const Value('Live Upload Test Facility'),
        clientName: const Value('Live Upload Test Client'),
        producerSupplier: const Value('Live Upload Test Producer'),
        batchNumber: const Value('LIVE-0001'),
        sampleSize: const Value(2),
        generalComments: const Value('[automated upload verification]'),
        latitude: const Value(-29.1183),
        longitude: const Value(26.2249),
      ),
      [
        // Deliberately the *computed* Haugh unit, at full float precision,
        // rather than a tidy hand-picked figure. This is what the form
        // actually produces, and short literals hid a defect that rejected
        // every real inspection.
        EggSamplesCompanion.insert(
          inspectionUuid: uuid,
          eggNumber: 1,
          massG: const Value(58.4),
          albumenHeightMm: const Value(6.2),
          haughUnit: Value(
            EggRules.haughUnit(albumenHeightMm: 6.2, massG: 58.4),
          ),
        ),
        EggSamplesCompanion.insert(
          inspectionUuid: uuid,
          eggNumber: 2,
          massG: const Value(61.9),
          albumenHeightMm: const Value(7.1),
          haughUnit: Value(
            EggRules.haughUnit(albumenHeightMm: 7.1, massG: 61.9),
          ),
        ),
      ],
    );

    await repo.addPhoto(
      EggPhotosCompanion.insert(
        inspectionUuid: uuid,
        kind: 'label',
        filePath: writePng('label.png').path,
        caption: const Value('label'),
        capturedAt: capturedAt,
      ),
    );
    await repo.addPhoto(
      EggPhotosCompanion.insert(
        inspectionUuid: uuid,
        kind: 'egg',
        filePath: writePng('egg.png').path,
        caption: const Value('sample tray'),
        capturedAt: capturedAt,
      ),
    );

    await repo.upload(await repo.inspectionByUuid(uuid) as EggInspection,
        token: token);

    // 1. The device only marks a record sent once the server confirmed it.
    expect((await repo.inspectionByUuid(uuid))!.isUploaded, isTrue);

    // 2. The server actually has it.
    final remote = await fetchFromServer(uuid);
    expect(remote, isNotNull, reason: 'inspection not found on the server');
    expect(remote!['batch_number'], 'LIVE-0001');
    expect(remote['client_name'], 'Live Upload Test Client');

    // 3. Every egg went up, with its readings.
    final samples =
        (remote['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(samples.length, 2);
    expect(
      samples.map((s) => double.parse('${s['mass_g']}')).toList()..sort(),
      [58.4, 61.9],
    );

    // The computed Haugh unit must survive as a real reading, not be rejected
    // for carrying full float precision.
    for (final sample in samples) {
      final haugh = double.parse('${sample['haugh_unit']}');
      expect(haugh, greaterThan(0));
      expect(haugh, lessThan(120));
    }

    // 4. Both images went up, and each photo row is marked sent locally so it
    //    is not uploaded a second time.
    final photos =
        (remote['photos'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(photos.length, 2,
        reason: 'expected both images, got ${photos.length}');
    expect(
      photos.map((p) => p['kind']).toSet(),
      {'label', 'egg'},
    );
    for (final photo in photos) {
      expect(photo['image'], isNotNull);
      expect('${photo['image']}'.isNotEmpty, isTrue);
      // The capture time must survive the trip, not be lost to null.
      expect(photo['captured_at'], isNotNull,
          reason: 'photo captured_at was dropped');
    }
    for (final local in await repo.photosFor(uuid)) {
      expect(local.isUploaded, isTrue);
    }

    // 5. The stored image is really retrievable, not just a database row.
    final imageUrl = '${photos.first['image']}';
    final absolute =
        imageUrl.startsWith('http') ? imageUrl : '$baseUrl$imageUrl';
    final image = await http.get(Uri.parse(absolute));
    expect(image.statusCode, 200, reason: 'stored image not served: $absolute');
    expect(image.bodyBytes.length, greaterThan(0));
  });

  test('re-uploading the same record updates rather than duplicates',
      () async {
    final uuid = const Uuid().v4();
    final at = DateTime.now();

    Future<void> save(String batch) => repo.saveInspection(
          EggInspectionsCompanion.insert(
            clientUuid: uuid,
            inspectedAt: at,
            updatedAt: at,
            status: const Value('completed'),
            clientName: const Value('Idempotency Test Client'),
            batchNumber: Value(batch),
            generalComments: const Value('[automated upload verification]'),
          ),
          [
            EggSamplesCompanion.insert(
              inspectionUuid: uuid,
              eggNumber: 1,
              massG: const Value(55),
            ),
          ],
        );

    await save('FIRST');
    await repo.upload(
        await repo.inspectionByUuid(uuid) as EggInspection, token: token);

    await save('SECOND');
    await repo.upload(
        await repo.inspectionByUuid(uuid) as EggInspection, token: token);

    // A dropped connection means the handset retries. That must never leave
    // two records for one inspection.
    final response = await http.get(
      Uri.parse('$baseUrl/api/eggs/inspections/'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final decoded = jsonDecode(response.body);
    final rows = (decoded is Map<String, dynamic>
            ? (decoded['results'] as List<dynamic>? ?? const [])
            : decoded as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final matching = rows.where((r) => r['client_uuid'] == uuid).toList();

    expect(matching.length, 1, reason: 'upload was not idempotent');
    expect(matching.single['batch_number'], 'SECOND');
  });
}
