import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The plan row counts inspections, so it is plural; the button opens one,
/// so it is singular.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));

  testWidgets('the start button names one inspection, the plan row many',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{}', 500));
    const url = 'http://example.test';
    final visits = VisitRepository(db, baseUrl: url, client: client);
    await visits.create('v-1', 'Cinga');
    await db.update(db.storeVisits).write(
        const StoreVisitsCompanion(plannedRaw: Value(2)));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: StoreVisitPage(
        visitUuid: 'v-1',
        visits: visits,
        eggs: EggsRepository(baseUrl: url, database: db, client: client),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: url, client: client),
        poultryCapture:
            PoultryCaptureRepository(database: db, baseUrl: url, client: client),
        rawRmp: RawRmpRepository(database: db, baseUrl: url, client: client),
        pmp: PmpRepository(database: db, baseUrl: url, client: client),
        inspectorName: 'Cinga',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });

    expect(find.text('Certain Raw Processed Meat Product Inspections'),
        findsOneWidget,
        reason: 'the plan row counts them');
    expect(find.text('START CERTAIN RAW PROCESSED MEAT PRODUCT INSPECTION'),
        findsOneWidget,
        reason: 'the button opens one');
    expect(find.text('START CERTAIN RAW PROCESSED MEAT PRODUCT INSPECTIONS'),
        findsNothing);
  });
}
