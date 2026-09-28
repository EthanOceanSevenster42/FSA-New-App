import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The facility type is chosen once, on the visit, and the inspections
/// inside it do not ask again.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));

  VisitPrefill visit(String facilityType) => VisitPrefill(
        uuid: 'v-1',
        facilityName: 'Bridge City Butchery',
        facilityAddress: '',
        facilityPhone: '',
        contactPerson: 'Sam',
        contactEmail: '',
        representative: 'Sam',
        managerName: 'Sam',
        managerEmail: '',
        facilityType: facilityType,
      );

  Future<void> pumpRaw(WidgetTester tester, VisitPrefill? prefill) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = RawRmpRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await repo.loadBundledRulesIfEmpty();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: RawRmpInspectionForm(
        repository: repo,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'Cinga',
        visit: prefill,
      ),
    ));
    await tester.pumpAndSettle();
    // Take the form down before the database goes, so no autosave is left
    // talking to a closed connection when the next test starts.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
  }

  testWidgets('a type chosen at the door is not asked again on the raw form',
      (tester) async {
    await pumpRaw(tester, visit('Butchery'));
    expect(find.textContaining('Inspection Facility Type', findRichText: true),
        findsNothing);
  });

  test('the visit remembers the type and hands it to every form', () async {
    addTearDown(db.close);
    final visits = VisitRepository(db);
    await visits.create('v-9', 'Cinga');
    await visits.updateDetails(
        'v-9', const StoreVisitsCompanion(facilityType: Value('Pack House')));
    final stored = (await visits.byUuid('v-9'))!;
    expect(stored.facilityType, 'Pack House');
    expect(visits.prefillOf(stored).facilityType, 'Pack House');
  });
}
