import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/invoicing/data/tariff_sync.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_rules.dart';

/// The RFI fees are set on the web and reach the tablet on its next sync
/// (Ethan, 2026-09-29).
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async {
    InvoiceRates.use(InvoiceRates.defaults);
    await db.close();
  });

  Map<String, Object?> serverTariff({double normal = 575.00}) => {
        ...InvoiceRates.defaults.toJson(),
        'normal_hour': normal,
        'per_kilometre': 7.25,
        'raw_dna': 2900.00,
        'updated_at': '2026-09-29T09:00:00Z',
      };

  TariffSync syncAnswering(Map<String, Object?> body, {int status = 200}) =>
      TariffSync(
        database: db,
        baseUrl: 'https://inspector-app.example',
        client: MockClient((request) async {
          expect(request.url.path, '/api/visits/tariff/');
          expect(request.headers['Authorization'], 'Bearer jwt');
          return http.Response(jsonEncode(body), status);
        }),
      );

  test('until it has synced, the tablet bills the published tariff', () {
    expect(InvoiceRates.normalHour, 540.60);
    expect(InvoiceRates.perKilometre, 6.50);
  });

  test('the server tariff is put in force and kept', () async {
    expect(await syncAnswering(serverTariff()).pull(token: 'jwt'), isTrue);
    expect(InvoiceRates.normalHour, 575.00);
    expect(InvoiceRates.perKilometre, 7.25);
    expect(InvoiceRates.rawDna, 2900.00);
    // Unchanged figures stay as published.
    expect(InvoiceRates.pmpFat, 875.56);

    // A restart brings back what was kept, with no signal needed.
    InvoiceRates.use(InvoiceRates.defaults);
    await TariffSync(database: db).load();
    expect(InvoiceRates.normalHour, 575.00);
  });

  test('pulling the same tariff again says nothing changed', () async {
    await syncAnswering(serverTariff()).pull(token: 'jwt');
    expect(await syncAnswering(serverTariff()).pull(token: 'jwt'), isFalse);
  });

  test('a refused request leaves the tariff as it was', () async {
    expect(await syncAnswering(const {}, status: 401).pull(token: 'jwt'),
        isFalse);
    expect(InvoiceRates.normalHour, 540.60);
  });

  test('a missing or unreadable figure keeps the one in force', () {
    final tariff = InvoiceTariff.fromJson(
        {'normal_hour': 'not a number', 'sunday_hour': -3, 'raw_soya': 1800});
    expect(tariff.normalHour, 540.60);
    expect(tariff.sundayHour, 720.80);
    expect(tariff.rawSoya, 1800);
  });

  test('the totals bill with the tariff in force', () {
    InvoiceRates.use(InvoiceTariff.fromJson(serverTariff()));
    final totals = InvoiceRules.totals(
      normalHours: 1,
      overtimeHours: 0,
      sundayHours: 0,
      kilometres: 10,
      chargeTravel: true,
      pmpFatTests: 0,
      pmpProteinTests: 0,
      pmpCalciumTests: 0,
      pmpPhysicalTests: 0,
      rawFatTests: 0,
      rawProteinTests: 0,
      rawSoyaTests: 0,
      rawStarchTests: 0,
      rawDnaTests: 1,
      rawCalciumTests: 0,
    );
    expect(totals.normal, 575.00);
    expect(totals.travel, 72.50);
    expect(totals.rawLab, 2900.00);
  });
}
