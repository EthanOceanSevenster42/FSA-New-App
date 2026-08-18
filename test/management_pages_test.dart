import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_user.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_direction_list_page.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_list_page.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_summary_page.dart';

/// The management screens: who may see the bulk corrections, and that a row
/// can always be opened.
void main() {
  late LocalDatabase db;
  late EggsRepository repo;

  const inspector = SessionUser(userName: 'Ethan', roleName: 'Inspector');
  const admin =
      SessionUser(userName: 'Ethan', roleName: 'System Administrator');

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(baseUrl: 'http://example.test', database: db);
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });

  tearDown(() async => db.close());

  Future<void> seedInspectionToday() async {
    final now = DateTime.now();
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: 'uuid-1',
            inspectedAt: now,
            updatedAt: now,
            clientName: const Value('Sunrise Poultry Farm'),
            producerSupplier: const Value('Highveld Layers'),
            status: const Value('completed'),
          ),
        );
  }

  Future<void> seedDirectionToday() async {
    final now = DateTime.now();
    await db.into(db.eggDirections).insert(
          EggDirectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: 'dir-1',
            qualityPart: const Value(true),
            issuedAt: now,
            updatedAt: now,
            clientName: const Value('Sunrise Poultry Farm'),
            status: const Value('completed'),
          ),
        );
  }

  /// 360x800dp — the working size of the cheap handsets this runs on. At the
  /// default test surface, content below the fold is silently untappable.
  Future<void> pumpAt(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: child));
    await tester.pumpAndSettle();
  }

  group('bulk corrections are gated on role', () {
    testWidgets('an inspector never sees them', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionListPage(repository: repo, user: inspector),
      );

      expect(find.textContaining('ADMINISTRATOR'), findsNothing);
      expect(find.text('Re-queue'), findsNothing);
      expect(find.text('Mark as sent'), findsNothing);
    });

    testWidgets('an administrator sees them on inspections', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionListPage(repository: repo, user: admin),
      );

      expect(find.textContaining('ADMINISTRATOR'), findsOneWidget);
      expect(find.text('Re-queue'), findsOneWidget);
      expect(find.text('Mark as sent'), findsOneWidget);
    });

    testWidgets('an administrator sees them on directions', (tester) async {
      await seedDirectionToday();
      await pumpAt(
        tester,
        EggDirectionListPage(repository: repo, user: admin),
      );

      expect(find.text('Re-queue'), findsOneWidget);
    });

    testWidgets('an inspector never sees them on directions', (tester) async {
      await seedDirectionToday();
      await pumpAt(
        tester,
        EggDirectionListPage(repository: repo, user: inspector),
      );

      expect(find.text('Re-queue'), findsNothing);
    });
  });

  group('bulk corrections confirm before acting', () {
    testWidgets('backing out of the dialog changes nothing', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionListPage(repository: repo, user: admin),
      );

      await tester.tap(find.text('Mark as sent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await repo.inspectionByUuid('uuid-1'))!.isUploaded, isFalse);
    });

    testWidgets('confirming applies it and reports the count', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionListPage(repository: repo, user: admin),
      );

      await tester.tap(find.text('Mark as sent'));
      await tester.pumpAndSettle();
      // The dialog's confirm button carries the same label as the trigger, so
      // target the one inside the dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark as sent'),
        ),
      );
      await tester.pumpAndSettle();

      expect((await repo.inspectionByUuid('uuid-1'))!.isUploaded, isTrue);
      expect(find.textContaining('1 inspection marked as sent'), findsOneWidget);
    });
  });

  group('opening a record', () {
    testWidgets('View opens the summary for that inspection', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionListPage(repository: repo, user: inspector),
      );

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.byType(EggInspectionSummaryPage), findsOneWidget);
      // Once as the page heading, once under Client.
      expect(find.text('Sunrise Poultry Farm'), findsWidgets);
    });

    testWidgets('a record with no eggs says so instead of showing an empty '
        'table', (tester) async {
      await seedInspectionToday();
      await pumpAt(
        tester,
        EggInspectionSummaryPage(repository: repo, inspectionUuid: 'uuid-1'),
      );

      // No grade was determined, so it must not claim one.
      expect(find.text('Not graded'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('No individual eggs were recorded.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No individual eggs were recorded.'), findsOneWidget);
    });

    testWidgets('a deleted record reports itself rather than crashing',
        (tester) async {
      await pumpAt(
        tester,
        EggInspectionSummaryPage(repository: repo, inspectionUuid: 'gone'),
      );

      expect(
        find.text('This inspection is no longer on the device.'),
        findsOneWidget,
      );
    });
  });
}
