import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/visits/data/occurrence_document_pdf.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An occurrence report leaves the handset as one PDF — the written report
/// and its photographs — riding with the visit as its Occurrence Document.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The document layer is plain Dart; the handset installs its font and
  // logo loader at start-up, and a test that renders a form has to do the
  // same or it has no assets to draw with.
  installFsaFormAssets();

  late LocalDatabase db;
  late Directory tmp;
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('occurrence');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<File> photo(String name) async {
    // Any real JPEG will do; the letterhead logo ships with the app.
    final bytes =
        await rootBundle.load('assets/images/fsa_letterhead_logo.jpg');
    return File('${tmp.path}/$name')
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  }

  /// A multipart field's value, read off the serialised body the way the
  /// server does. The separator between headers and value is CR LF CR LF.
  final crlf = String.fromCharCodes([13, 10]);
  String? fieldOf(String body, String name) {
    final marker = 'name="$name"$crlf$crlf';
    final start = body.indexOf(marker);
    if (start < 0) return null;
    final from = start + marker.length;
    final end = body.indexOf(crlf, from);
    return body.substring(from, end < 0 ? body.length : end);
  }

  test('the document is a PDF with the report and one page per photo',
      () async {
    final a = await photo('a.jpg');
    final b = await photo('b.jpg');
    final out = await OccurrenceDocumentPdf.write(
      out: File('${tmp.path}/occurrence.pdf'),
      facilityName: 'SHOPRITE - Bridge City Mall',
      facilityAddress: '14 Bhejane Road, Inanda',
      date: '27/08/2026',
      timeOfVisit: '11:55',
      registrationCode: 'ABC-123',
      inspectorName: 'Cinga',
      description: 'Rodent droppings found in the cold room.',
      photoPaths: [a.path, b.path, '${tmp.path}/missing.jpg'],
    );
    final bytes = await out.readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final text = String.fromCharCodes(bytes);
    // Short findings and two photographs: the whole document is one page.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 1);
    expect(bytes.length, greaterThan(20 * 1024),
        reason: 'the photos are in it');
  });

  test('an occurrence visit uploads its document and its written report',
      () async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-occ',
          startedAt: DateTime.utc(2026, 8, 27, 9, 55),
          facilityName: const Value('SHOPRITE - Bridge City Mall'),
          completedAt: Value(DateTime.utc(2026, 8, 27, 11)),
          isOccurrenceReport: const Value(true),
          occurrenceTimeOfVisit: const Value('11:55'),
          occurrenceRegistrationCode: const Value('ABC-123'),
          occurrenceDescription:
              const Value('Rodent droppings found in the cold room.'),
        ));
    late String body;
    late int bodyLength;
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        bodyLength = request.bodyBytes.length;
        body = String.fromCharCodes(request.bodyBytes);
        return http.Response('{"id": 9}', 201);
      }),
    );
    await repository.addOccurrencePhoto(
        'visit-occ', (await photo('p.jpg')).path);
    expect((await repository.occurrencePhotos('visit-occ')).length, 1);

    final ok = await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
      kilometres: 0,
      hours: 1,
    );
    expect(ok, isTrue);
    expect(fieldOf(body, 'is_occurrence_report'), 'true');
    expect(fieldOf(body, 'occurrence_time_of_visit'), '11:55');
    expect(fieldOf(body, 'occurrence_registration_code'), 'ABC-123');
    expect(fieldOf(body, 'occurrence_description'),
        'Rodent droppings found in the cold room.');
    expect(
        body,
        contains(
            'name="occurrence_document"; filename="occurrence-report.pdf"'));
    expect(body, contains('%PDF-'));
    expect(bodyLength, greaterThan(20 * 1024), reason: 'the photo is in it');
  });

  test('a visit that is not an occurrence report sends no document',
      () async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-plain',
          startedAt: DateTime.utc(2026, 8, 27, 9),
          facilityName: const Value('Kroon Foods'),
          completedAt: Value(DateTime.utc(2026, 8, 27, 10)),
        ));
    late String body;
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        body = String.fromCharCodes(request.bodyBytes);
        return http.Response('{"id": 10}', 201);
      }),
    );
    await repository.upload((await repository.pendingUploads()).single,
        token: 'jwt', kilometres: 0, hours: 1);
    expect(body, isNot(contains('name="occurrence_document"')));
    expect(body, contains('name="occurrence_description"'),
        reason: 'the field still travels, empty');
  });

  test('long findings push the photographs onto their own pages', () async {
    final a = await photo('long-a.jpg');
    final out = await OccurrenceDocumentPdf.write(
      out: File('${tmp.path}/occurrence-long.pdf'),
      facilityName: 'Kroon Foods',
      facilityAddress: '',
      date: '28/08/2026',
      timeOfVisit: '09:00',
      registrationCode: '',
      inspectorName: 'Cinga',
      description: List.filled(30, 'The manager refused to let us in and would not say why.').join(' '),
      photoPaths: [a.path],
    );
    final text = String.fromCharCodes(await out.readAsBytes());
    // Findings spill to a second page, and the photograph gets a third.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 3);
  });
}
