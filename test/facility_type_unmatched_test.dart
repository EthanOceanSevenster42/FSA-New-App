import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The raw form does not ask the facility type again inside a grouped
/// inspection, even when the door's answer is not on raw's own list: the
/// door has asked it once (Ethan, 2026-09-24). That it still asks on its
/// own is pinned in raw_is_inspection_or_composition_test.dart.
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

  testWidgets('inside a visit it is not asked again, even when unmatched',
      (tester) async {
    await pumpRaw(tester, visit('Abattoir'));
    expect(find.textContaining('Inspection Facility Type', findRichText: true),
        findsNothing);
  });

}
