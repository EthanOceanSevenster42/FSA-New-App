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

/// An inspector who opened an inspection by mistake can take the plan back
/// down: the unfinished draft goes with it after a confirmation. Only
/// captured work is the office's to remove.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));

  testWidgets('reducing the plan past an unfinished draft removes it',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{}', 500));
    const url = 'http://example.test';
    final visits = VisitRepository(db, baseUrl: url, client: client);
    await visits.create('v-1', 'Cinga');
    await db.update(db.storeVisits).write(
        const StoreVisitsCompanion(plannedEggs: Value(1)));
    final now = DateTime(2026, 8, 28, 10, 40);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-draft',
          inspectedAt: now,
          updatedAt: now,
          visitUuid: const Value('v-1'),
          inspectorUsername: const Value('Cinga'),
          status: const Value('draft'),
        ));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: StoreVisitPage(
        visitUuid: 'v-1',
        visits: visits,
        eggs: EggsRepository(baseUrl: url, database: db, client: client),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: url, client: client),
        poultryCapture: PoultryCaptureRepository(
            database: db, baseUrl: url, client: client),
        rawRmp: RawRmpRepository(database: db, baseUrl: url, client: client),
        pmp: PmpRepository(database: db, baseUrl: url, client: client),
        inspectorName: 'Cinga',
        canRemoveRecords: false, // an inspector
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
    expect(find.text('0 of 1 done'), findsOneWidget);

    // The minus on the egg row — the first plan row.
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Discard the unfinished inspection?'), findsOneWidget);
    expect(find.textContaining('Only a system administrator'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(await db.select(db.eggInspections).get(), isEmpty);
    final visit = await visits.byUuid('v-1');
    expect(visit!.plannedEggs, 0);
    expect(find.text('0 of 1 done'), findsNothing);
  });
}
