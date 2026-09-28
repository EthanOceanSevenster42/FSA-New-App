import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Where the invoice's kilometres come from.
///
/// One journey to one facility, so the inspector types the distance once at
/// the door and the Request for Invoice bills on it at R6.50 per kilometre.
/// It used to be asked on every raw inspection instead: a visit with two of
/// them asked twice and the invoice kept whichever it read first, and a visit
/// with no raw inspection at all had no distance to bill. If this chain
/// breaks the office invoices every visit as though nobody drove anywhere.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  late InvoiceRepository invoices;

  const visitUuid = 'visit-km-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    invoices = InvoiceRepository(db, visits);
    await visits.create(visitUuid, 'Armand');
  });
  tearDown(() async => db.close());

  Future<void> captureRaw({double? km}) async {
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'client-1',
            inspectedAt: DateTime(2026, 8, 26, 10),
            updatedAt: DateTime(2026, 8, 26, 10),
            inspectorUsername: const Value('Armand'),
            visitUuid: const Value(visitUuid),
            distanceTravelledKm: Value(km),
          ),
        );
  }

  Future<void> setVisitDistance(double km) => visits.updateDetails(
        visitUuid,
        StoreVisitsCompanion(distanceTravelledKm: Value(km)),
      );

  Future<double?> kilometresOnForm() async {
    final visit = await visits.byUuid(visitUuid);
    final form = await invoices.prefill(visit!);
    return form.kilometres.value;
  }

  test('the distance off the visit is what the invoice bills', () async {
    await setVisitDistance(128);

    expect(await kilometresOnForm(), 128);
  });

  test('a visit with no inspection on it still bills its distance', () async {
    // Nothing captured the figure before: the only box for it was on the raw
    // form, so a poultry-only visit invoiced for time alone.
    await setVisitDistance(30);

    expect(await kilometresOnForm(), 30);
  });

  test('the trip stands, whatever the records under it say', () async {
    await setVisitDistance(42.5);
    await captureRaw(km: 12);

    expect(await kilometresOnForm(), 42.5);
  });

  test('a visit captured before the question moved still bills', () async {
    // Its distance is on the raw record, where it was asked at the time.
    await captureRaw(km: 128);

    expect(await kilometresOnForm(), 128);
  });

  test('a visit with no distance recorded bills none', () async {
    await captureRaw();

    expect(await kilometresOnForm(), 0);
  });

  test('an older visit bills one journey, not one per record', () async {
    // One trip, several commodities: the inspector drives there once, so a
    // second record must not add a second journey to the invoice.
    await captureRaw(km: 128);
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'client-2',
            inspectedAt: DateTime(2026, 8, 26, 11),
            updatedAt: DateTime(2026, 8, 26, 11),
            inspectorUsername: const Value('Armand'),
            visitUuid: const Value(visitUuid),
            distanceTravelledKm: const Value(96),
          ),
        );

    expect(await kilometresOnForm(), 128);
  });
}
