import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';

/// What the handset actually sends the office.
///
/// The documents are built from the record and the server accepts the shape,
/// but neither says the *values* arrive: a field read from the wrong column
/// still renders, and still validates. This captures the request body the
/// upload would put on the wire and reads the figures back out of it.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 1, 11, 30);

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Captures the one request the repository makes.
  ({http.Client client, List<Map<String, dynamic>> bodies}) recorder() {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{}', 201);
    });
    return (client: client, bodies: bodies);
  }

  test('a grading inspection arrives with what was captured', () async {
    final rec = recorder();
    final repo = PoultryRepository(
        database: db, baseUrl: 'http://example.test', client: rec.client);
    await repo.saveInspection(PoultryInspectionsCompanion.insert(
      clientUuid: 'up-grading',
      inspectedAt: when,
      updatedAt: when,
      facilityName: const Value('Rainbow Chickens - Hammarsdale'),
      companyRegNumber: const Value('ZA-PM-4471'),
      producerTradingName: const Value('Rainbow Farms'),
      productDetails: const Value('Whole Frozen Chicken'),
      sampleNumber: const Value('3'),
      compliantItemIds: const Value('1,2,3'),
      gradingBySample: const Value('1:1,2;2:1'),
      inspectionComments: const Value('Breast fleshiness on sample 3.'),
    ));
    final saved = (await db.select(db.poultryInspections).get()).single;
    await repo.upload(saved, token: 'test-token');

    expect(rec.bodies, hasLength(1));
    final body = rec.bodies.single;
    expect(body['client_uuid'], 'up-grading');
    expect(body['facility_name'], 'Rainbow Chickens - Hammarsdale');
    expect(body['company_reg_number'], 'ZA-PM-4471');
    expect(body['producer_trading_name'], 'Rainbow Farms');
    expect(body['product_details'], 'Whole Frozen Chicken');
    expect(body['sample_number'], '3');
    expect(body['compliant_item_ids'], '1,2,3');
    // The per-carcass answers, not just the union.
    expect(body['grading_by_sample'], '1:1,2;2:1');
    expect(body['inspection_comments'], 'Breast fleshiness on sample 3.');
    // Restricted particulars are a labelling matter and no longer travel on
    // a grading record.
    expect(body.containsKey('restricted_particulars'), isFalse);
  });

  test('a label checklist arrives without the grading fields', () async {
    final rec = recorder();
    final capture = PoultryCaptureRepository(
        database: db, baseUrl: 'http://example.test', client: rec.client);
    await capture.saveLabelInspection(PoultryLabelInspectionsCompanion.insert(
      clientUuid: 'up-label',
      inspectedAt: when,
      updatedAt: when,
      facilityName: const Value('Rainbow Chickens - Hammarsdale'),
      registrationNumber: const Value('ZA-PM-4471'),
      productDetails: const Value('Whole Frozen Chicken'),
      outerLabelsPresent: const Value(true),
      compliantItemIds: const Value('11,12'),
      restrictedParticularsText: const Value('Free Range'),
      nonConformanceComments: const Value('Packer address absent.'),
    ));
    final saved = (await db.select(db.poultryLabelInspections).get()).single;
    await capture.uploadLabelInspection(saved, token: 'test-token');

    final body = rec.bodies.single;
    expect(body['client_uuid'], 'up-label');
    expect(body['registration_number'], 'ZA-PM-4471');
    expect(body['outer_labels_present'], isTrue);
    expect(body['compliant_item_ids'], '11,12');
    expect(body['restricted_particulars_text'], 'Free Range');
    expect(body['non_conformance_comments'], 'Packer address absent.');
    // Classification and grading belong to their own inspection.
    for (final absent in [
      'meat_type',
      'portion_type',
      'designation_class',
      'alternative_designation_class',
      'grade',
      'sample_number',
    ]) {
      expect(body.containsKey(absent), isFalse,
          reason: '$absent is a grading field and must not ride on a label '
              'record');
    }
  });

  test('a QUID determination arrives with its masses', () async {
    final rec = recorder();
    final capture = PoultryCaptureRepository(
        database: db, baseUrl: 'http://example.test', client: rec.client);
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'up-quid',
      inspectedAt: when,
      updatedAt: when,
      facilityName: const Value('Rainbow Chickens - Hammarsdale'),
      isWaterChilled: const Value(true),
      isWholeCarcass: const Value(true),
      dispensationQuidPercent: const Value('8.0'),
      averageWaterChillPickup: const Value('10.5'),
      documentDate: Value(DateTime(2026, 8, 30)),
      documentName: const Value('Brine batch record BR-2291'),
    ));
    await capture.replaceQuidInjectors('up-quid', [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: 'up-quid',
        position: 1,
        name: const Value('Brine 1'),
        quidPercent: const Value('8.0'),
      ),
    ]);
    await capture.replaceQuidSamples('up-quid', [
      PoultryQuidSamplesCompanion.insert(
        inspectionUuid: 'up-quid',
        carcassNumber: const Value('1'),
        initialMassG: const Value('1403'),
        finalMassG: const Value('1552'),
        pickupPercent: const Value('10.3'),
        beforeMassG: const Value('1383'),
        injectorAfterMassG: const Value('1403'),
        gainG: const Value('20'),
        injectorRatePercent: const Value('1.45'),
        quidFinalMassG: const Value('1508'),
        quidGainG: const Value('105'),
        quidPercent: const Value('6.963'),
        assignedInjector: const Value('1'),
      ),
    ]);
    final saved = (await db.select(db.poultryQuidInspections).get()).single;
    await capture.uploadQuidInspection(saved, token: 'test-token');

    final body = rec.bodies.single;
    expect(body['client_uuid'], 'up-quid');
    expect(body['is_water_chilled'], isTrue);
    expect(body['dispensation_quid_percent'], '8.0');
    expect(body['average_water_chill_pickup'], '10.5');

    // The carcass weighings are the determination; without them the office
    // has an average it cannot check.
    final samples = (body['samples'] as List<dynamic>).cast<Map<String, Object?>>();
    expect(samples, hasLength(1));
    expect(samples.single['carcass_number'], '1');
    expect(samples.single['initial_mass_g'], '1403');
    expect(samples.single['final_mass_g'], '1552');
    expect(samples.single['pickup_percent'], '10.3');

    // The injector weighings, which were captured on the handset and stopped
    // there: without them the office has a rate it cannot check.
    expect(samples.single['before_mass_g'], '1383');
    expect(samples.single['injector_after_mass_g'], '1403');
    expect(samples.single['gain_g'], '20');
    expect(samples.single['injector_rate_percent'], '1.45');

    // The determination is made per carcass and judged per injector, so the
    // carcass's own QUID and the injector it ran through both have to
    // travel, along with what that injector was set to.
    expect(samples.single['quid_final_mass_g'], '1508');
    expect(samples.single['quid_gain_g'], '105');
    expect(samples.single['quid_percent'], '6.963');
    expect(samples.single['assigned_injector'], '1');

    final injectors = (body['injectors'] as List<dynamic>).cast<Map<String, Object?>>();
    expect(injectors, hasLength(1));
    expect(injectors.single['position'], 1);
    expect(injectors.single['name'], 'Brine 1');
    expect(injectors.single['quid_percent'], '8.0');

    // The date on the record that was verified.
    expect(body['document_date'], '2026-08-30');
  });
}
