import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/features/auth/data/api_auth_service.dart';
import 'package:fsa_app/features/auth/data/offline_capable_auth_service.dart';
import 'package:fsa_app/features/auth/data/user_sync_repository.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/data/eggs_sync_service.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/sync/server_sync.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The "Re-send everything" button on Server Sync.
///
/// An ordinary sync leaves an inspection the office already has alone. When
/// the office is holding an older copy than the device — documents built by
/// an earlier version of the app — this is what puts it right. Reported
/// 2026-10-08: an egg rejection reached APS without its six photographs.
///
/// Nothing here reaches a network: the address refuses at once, so every
/// sync step fails and the dialog finishes, which is all the button needs.
void main() {
  const dead = 'http://127.0.0.1:1';

  late LocalDatabase db;
  late VisitRepository visits;
  late ServerSyncRunner runner;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    runner = ServerSyncRunner(
      authService: OfflineCapableAuthService(
        remote: ApiAuthService(
            baseUrl: dead, deviceId: 'test', deviceModel: 'test'),
        database: db,
        syncRepository: UserSyncRepository(baseUrl: dead, database: db),
      ),
      eggs: EggsRepository(baseUrl: dead, database: db),
      eggsSync: EggsSyncService(
        repository: EggsRepository(baseUrl: dead, database: db),
        connectivity: ConnectivityService(),
      ),
      poultry: PoultryRepository(baseUrl: dead, database: db),
      poultryCapture: PoultryCaptureRepository(baseUrl: dead, database: db),
      pmp: PmpRepository(baseUrl: dead, database: db),
      rawRmp: RawRmpRepository(baseUrl: dead, database: db),
      visits: visits,
    );
  });
  tearDown(() => db.close());

  Future<void> seedSentVisit() =>
      db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: 'visit-1',
            startedAt: DateTime.utc(2026, 10, 8, 8),
            completedAt: Value(DateTime.utc(2026, 10, 8, 10)),
            isUploaded: const Value(true),
          ));

  Future<bool> stillMarkedSent() async => (await (db.select(db.storeVisits)
            ..where((t) => t.uuid.equals('visit-1')))
          .getSingle())
      .isUploaded;

  /// Opens the dialog and waits for the pass to finish.
  Future<void> openSync(WidgetTester tester) async {
    // A tablet-sized surface: the dialog lists every sync step and the
    // default 800x600 test window is shorter than the handset it runs on.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showServerSyncDialog(context, runner: runner, username: 'x'),
              child: const Text('sync'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('sync'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('offers to re-send once the pass has finished', (tester) async {
    await seedSentVisit();

    await openSync(tester);

    expect(find.text('Re-send everything'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget,
        reason: 'the pass has finished, so the dialog can be closed');
  });

  testWidgets('asks before sending, and backing out changes nothing',
      (tester) async {
    await seedSentVisit();
    await openSync(tester);

    await tester.tap(find.text('Re-send everything'));
    await tester.pumpAndSettle();
    expect(find.text('Send everything again?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await stillMarkedSent(), isTrue,
        reason: 'cancelled: the inspection stays as sent');
  });

  testWidgets('confirming puts the sent inspection back in front of the sync',
      (tester) async {
    await seedSentVisit();
    await openSync(tester);

    await tester.tap(find.text('Re-send everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(await stillMarkedSent(), isFalse,
        reason: 'clearing the sent flag is what makes the sync carry it again');
  });
}
