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

/// An inspector may put away an in-progress visit of their own.
///
/// One with nothing captured goes quietly. One that already carries
/// inspections still goes — none of it has been sent — but only behind a
/// dialog that says what is about to be lost and counts it.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));

  Future<VisitRepository> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{}', 500));
    const url = 'http://example.test';
    final visits = VisitRepository(db, baseUrl: url, client: client);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: StoreVisitListPage(
        visits: visits,
        eggs: EggsRepository(baseUrl: url, database: db, client: client),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: url, client: client),
        poultryCapture: PoultryCaptureRepository(
            database: db, baseUrl: url, client: client),
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
    return visits;
  }

  testWidgets('an inspector can discard an empty in-progress visit',
      (tester) async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'empty-1',
          inspectorUsername: const Value('Cinga'),
          startedAt: DateTime(2026, 8, 28, 9, 50),
        ));
    await pumpList(tester);
    expect(find.text('Unnamed facility'), findsOneWidget);

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this inspection?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Unnamed facility'), findsNothing);
    expect(await db.select(db.storeVisits).get(), isEmpty);
  });

  testWidgets('a visit with captured inspections says what will be lost',
      (tester) async {
    final now = DateTime(2026, 8, 28, 9);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'busy-1',
          inspectorUsername: const Value('Cinga'),
          facilityName: const Value('Kroon Foods'),
          startedAt: now,
        ));
    await db.into(db.poultryInspections).insert(
          PoultryInspectionsCompanion.insert(
            clientUuid: 'p-1',
            inspectedAt: now,
            updatedAt: now,
            visitUuid: const Value('busy-1'),
            inspectorUsername: const Value('Cinga'),
            status: const Value('ready'),
          ),
        );
    await pumpList(tester);

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();
    // It is not refused — it is spelled out: the count, and that none of it
    // has been sent, so it cannot be recovered from here.
    expect(find.text('Discard this inspection?'), findsOneWidget);
    expect(find.textContaining('1 inspection'), findsOneWidget);
    expect(find.textContaining('cannot be brought back'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Kroon Foods'), findsOneWidget);
  });
}
