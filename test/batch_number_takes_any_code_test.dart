import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A batch number is whatever the pack carries (Ethan, 2026-10-02): the raw
/// and processed-meat forms take a lettered code and keep it as typed, and
/// neither tells the inspector that only digits count.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Finder batchBox() => find.descendant(
        of: find.ancestor(
            of: find.byWidgetPredicate(
                (w) => w is RequiredLabel && w.label == 'Batch Number'),
            matching: find.byType(LabelledField)),
        matching: find.byType(TextField),
      );

  testWidgets('the raw form takes a lettered batch code', (tester) async {
    tester.view.physicalSize = const Size(1080, 12000);
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
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(batchBox().first, 'LOT-A12/B');
    await tester.pumpAndSettle();
    expect(find.text('LOT-A12/B'), findsOneWidget);
    expect(find.textContaining('nothing else counts'), findsNothing);
    expect(find.textContaining('Numbers only'), findsNothing);
  });

  testWidgets('the processed-meat form takes a lettered batch code',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = PmpRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await repo.loadBundledRulesIfEmpty();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: PmpInspectionForm(
        repository: repo,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'Cinga',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(batchBox().first, 'ABC 123');
    await tester.pumpAndSettle();
    expect(find.text('ABC 123'), findsOneWidget);
    expect(find.textContaining('nothing else counts'), findsNothing);
  });
}
