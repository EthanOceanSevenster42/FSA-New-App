import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/visits/presentation/commodity_inspection_view.dart';

/// Opening a captured poultry inspection that raised a rejection used to hang
/// the view on its spinner for ever: the shared deviation query selected a
/// `section` column that the poultry checklist table does not have, so it threw
/// "no such column: section" — but only when a direction existed, so only
/// rejections were affected. The throw was swallowed by a `_load` with no
/// catch, which left `_loading` true. This pins the fix down.
void main() {
  late LocalDatabase db;
  late PoultryRepository repo;
  late PoultryCaptureRepository capture;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PoultryRepository(database: db, baseUrl: 'http://example.test');
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<void> loadReference() async {
    final raw =
        File('assets/reference/poultry_reference.json').readAsStringSync();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  }

  testWidgets('a poultry inspection with a rejection opens, not an endless '
      'spinner', (tester) async {
    await loadReference();
    final now = DateTime.now();

    await repo.saveInspection(
      PoultryInspectionsCompanion.insert(
        clientUuid: 'rej-1',
        inspectedAt: now,
        updatedAt: now,
        inspectorUsername: const Value('Ethan'),
        status: const Value('completed'),
        facilityName: const Value('Spar Rejection Test'),
        // Two items ticked; every other active grading row is a deviation,
        // which is what the rejection path reads off the checklist table.
        compliantItemIds: const Value('1,2'),
      ),
    );
    await capture.saveDirection(
      PoultryDirectionsCompanion.insert(
        clientUuid: 'rej-1',
        issuedAt: now,
        updatedAt: now,
        inspectorUsername: const Value('Ethan'),
        status: const Value('completed'),
        facilityName: const Value('Spar Rejection Test'),
        remarks: const Value('Grade designation missing'),
      ),
    );

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: CommodityInspectionViewPage(
          database: db,
          kind: 'poultry',
          uuid: 'rej-1',
          title: 'Poultry 1',
          uploaded: false,
          status: 'completed',
        ),
      ),
    );
    // Fixed pumps rather than pumpAndSettle: the read-back lands in a few
    // frames, and a spinner that never resolves would make pumpAndSettle wait
    // out its whole ten-minute timeout.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The page finished loading: no spinner left turning, and no error state
    // (the old "no such column: section" throw would have landed us there).
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('This inspection could not be opened.'), findsNothing);
    // The record is on screen, and the rejection it raised is shown — the
    // section that only renders once the direction loaded without throwing.
    expect(find.text('Spar Rejection Test'), findsWidgets);
    expect(find.text('REJECTION SERVED'), findsOneWidget);
  });
}
