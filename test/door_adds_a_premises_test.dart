import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// Registering a premises the directory does not hold, at the door.
///
/// Inspectors arrive at places nobody has registered. What they type into the
/// sheet has to reach the visit and the directory, or the next inspector at
/// the same depot types it afresh and the two visits never line up.
void main() {
  late LocalDatabase db;
  const visitUuid = 'visit-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: DateTime(2026, 9, 22, 8),
        ));
  });
  tearDown(() async => db.close());

  testWidgets('what is typed on the sheet reaches the visit and the list',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: visitUuid,
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();

    // Type a name the directory does not have, then take the offer to add it.
    await tester.enterText(
        find.byType(TextField).first, 'Shamika Supermarket 2');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add new'));
    await tester.pumpAndSettle();

    Finder box(String label) => find.descendant(
          of: find.ancestor(
              of: find.text(label), matching: find.byType(Column)),
          matching: find.byType(TextField),
        );
    await tester.enterText(
        box('Physical address').first, '12 Bridge Road, Pinetown');
    await tester.enterText(box('Telephone / cellphone').first, '0312001234');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add premises'));
    await tester.pumpAndSettle();

    // On the visit, so every inspection under it carries the address.
    final visit = (await db.select(db.storeVisits).get()).single;
    expect(visit.facilityName, 'Shamika Supermarket 2');
    expect(visit.facilityAddress, '12 Bridge Road, Pinetown');
    expect(visit.facilityPhone, '0312001234');

    // And in the directory, so the next inspector finds it.
    final directory = await EggsRepository(database: db, baseUrl: '')
        .facilities();
    expect(directory.map((f) => f.name), contains('Shamika Supermarket 2'));
    expect(directory.single.physicalAddress, '12 Bridge Road, Pinetown');
  });
}
