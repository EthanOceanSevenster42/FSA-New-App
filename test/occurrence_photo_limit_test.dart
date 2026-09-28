import 'dart:io';

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

/// An occurrence report takes two photographs at most: the camera tile is
/// offered until the second is taken, then put away.
void main() {
  late LocalDatabase db;
  late Directory tmp;
  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('occ-photos');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpVisit(WidgetTester tester,
      {required int photos, String description = ''}) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{}', 500));
    const url = 'http://example.test';
    final visits = VisitRepository(db, baseUrl: url, client: client);
    await visits.create('v-1', 'Cinga');
    await db.update(db.storeVisits).write(StoreVisitsCompanion(
        isOccurrenceReport: const Value(true),
        occurrenceDescription: Value(description)));
    for (var i = 0; i < photos; i++) {
      final f = File('${tmp.path}/p$i.jpg')..writeAsBytesSync([0]);
      await visits.addOccurrencePhoto('v-1', f.path);
    }
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
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
  }

  testWidgets('the camera tile is offered while fewer than two photographs',
      (tester) async {
    await pumpVisit(tester, photos: 1);
    expect(find.text('1 of 2 taken — at least 1, 2 at most.'), findsOneWidget);
    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Take photograph'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('two photographs is the limit', (tester) async {
    await pumpVisit(tester, photos: 2);
    expect(find.text('All 2 taken. Delete one to take another.'),
        findsOneWidget);
    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Take photograph'));
    expect(button.onPressed, isNull);
  });

  testWidgets('an occurrence report will not sign off without a photograph',
      (tester) async {
    await pumpVisit(tester,
        photos: 0, description: 'Broken cold chain at receiving.');
    expect(find.text('0 of 2 taken — at least 1, 2 at most.'), findsOneWidget);
    await tester.tap(find.text('SIGN & SUBMIT OCCURRENCE REPORT'));
    await tester.pumpAndSettle();
    expect(
        find.text('Take at least one photograph before signing off the '
            'occurrence report.'),
        findsOneWidget);
    expect(find.text('Store / Client Signature'), findsNothing);
  });
}
