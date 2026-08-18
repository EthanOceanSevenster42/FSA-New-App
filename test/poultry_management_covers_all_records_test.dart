import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_user.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_inspection_form.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_inspection_list_page.dart';

/// The two failure modes this file exists to keep dead:
///
/// Inspection Management once listed only grading records, so a completed
/// Label/Container or QUID checklist had no Send button anywhere — captured,
/// finished, and stranded on the handset.
///
/// And "Resume" once opened a blank form over the saved draft, so completing
/// it overwrote everything the inspector had already entered with empties.
void main() {
  late LocalDatabase db;
  late PoultryRepository repo;
  late PoultryCaptureRepository capture;

  const inspector = SessionUser(userName: 'Ethan', roleName: 'Inspector');

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PoultryRepository(database: db, baseUrl: 'http://example.test');
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<void> loadReference() async {
    // Synchronous read, deliberately: `testWidgets` runs the body inside a
    // FakeAsync zone where real asynchronous file I/O never completes — the
    // await hangs until the ten-minute test timeout with no error printed.
    final raw =
        File('assets/reference/poultry_reference.json').readAsStringSync();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// 360x800dp — the working size of the cheap handsets this runs on.
  Future<void> pumpAt(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: child));
    await tester.pumpAndSettle();
  }

  group('management lists every record type', () {
    testWidgets('label and QUID records appear beside grading, with Send',
        (tester) async {
      final now = DateTime.now();
      await repo.saveInspection(
        PoultryInspectionsCompanion.insert(
          clientUuid: 'g-1',
          inspectedAt: now,
          updatedAt: now,
          inspectorUsername: const Value('Ethan'),
          facilityName: const Value('Grading Farm'),
          status: const Value('completed'),
        ),
      );
      await capture.saveLabelInspection(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'l-1',
          inspectedAt: now,
          updatedAt: now,
          inspectorUsername: const Value('Ethan'),
          facilityName: const Value('Label Depot'),
          status: const Value('completed'),
        ),
      );
      await capture.saveQuidInspection(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'q-1',
          inspectedAt: now,
          updatedAt: now,
          inspectorUsername: const Value('Ethan'),
          facilityName: const Value('Quid Abattoir'),
          status: const Value('draft'),
        ),
      );

      await pumpAt(
        tester,
        PoultryInspectionListPage(
          repository: repo,
          captureRepository: capture,
          user: inspector,
        ),
      );

      // All three kinds are on the page, each named — a card that does not
      // say which checklist it is invites sending the wrong one.
      expect(find.text('Grading'), findsOneWidget);
      expect(find.text('Label/Container'), findsOneWidget);
      expect(find.text('QUID'), findsOneWidget);
      expect(find.text('Grading Farm'), findsOneWidget);
      expect(find.text('Label Depot'), findsOneWidget);
      expect(find.text('Quid Abattoir'), findsOneWidget);

      // Both completed records offer Send — the label one having a Send
      // button at all is the bug this test pins down.
      expect(find.text('Send'), findsNWidgets(2));
      // The QUID draft is resumable, not sendable.
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('another inspector\'s records stay off the page',
        (tester) async {
      final now = DateTime.now();
      await capture.saveLabelInspection(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'theirs',
          inspectedAt: now,
          updatedAt: now,
          inspectorUsername: const Value('someone-else'),
          facilityName: const Value('Not Yours Depot'),
          status: const Value('completed'),
        ),
      );

      await pumpAt(
        tester,
        PoultryInspectionListPage(
          repository: repo,
          captureRepository: capture,
          user: inspector,
        ),
      );

      expect(find.text('Not Yours Depot'), findsNothing);
    });
  });

  group('resuming a draft restores it', () {
    testWidgets('a grading draft comes back with its values on screen',
        (tester) async {
      await loadReference();
      final now = DateTime.now();
      await repo.saveInspection(
        PoultryInspectionsCompanion.insert(
          clientUuid: 'draft-1',
          inspectedAt: now,
          updatedAt: now,
          inspectorUsername: const Value('Ethan'),
          status: const Value('draft'),
          facilityName: const Value('Halfway House Poultry'),
          contactPerson: const Value('P. Person'),
          sampleNumber: const Value('S-42'),
          compliantItemIds: const Value('1,2'),
        ),
      );

      // Fixed pumps rather than pumpAndSettle: the form's 60-odd reference
      // rows and restore both land within a few frames, and pumpAndSettle
      // waits out any animation for its full ten-minute timeout instead.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PoultryInspectionForm(
            repository: repo,
            captureRepository: capture,
            inspectorName: 'Ethan',
            existingUuid: 'draft-1',
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The saved values are back on screen. A blank form here meant
      // completing the draft erased everything already entered.
      expect(find.text('Halfway House Poultry'), findsOneWidget);
      expect(find.text('P. Person'), findsOneWidget);
    });
  });
}
