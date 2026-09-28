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

/// Marking a visit as an occurrence report puts the inspection plan away:
/// there are no inspections to count, only the report to write and sign.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));

  Future<void> pumpVisit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = MockClient((_) async => http.Response('{}', 500));
    const url = 'http://example.test';
    final visits = VisitRepository(db, baseUrl: url, client: client);
    await visits.create('v-1', 'Cinga');
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

  testWidgets('the plan is shown for an ordinary visit and put away for an '
      'occurrence report', (tester) async {
    await pumpVisit(tester);
    expect(find.text('PLAN — HOW MANY OF EACH'), findsOneWidget);
    expect(find.textContaining('Set the plan above'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(find.text('PLAN — HOW MANY OF EACH'), findsNothing);
    expect(find.textContaining('Set the plan above'), findsNothing);
    expect(find.text('OCCURRENCE REPORT'), findsOneWidget);
    expect(find.text('SIGN & SUBMIT OCCURRENCE REPORT'), findsOneWidget);
    expect(find.text('SIGN & SUBMIT ALL INSPECTIONS'), findsNothing);

    // Back to No and the plan returns.
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN — HOW MANY OF EACH'), findsOneWidget);
  });
}
