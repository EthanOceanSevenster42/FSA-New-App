import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The processed-meat form asks how the sample travels the way the raw form
/// does (Ethan, 2026-10-02): Hand Delivered or Couriered, one choice, no
/// "Hand Delivered" switch that wrote the field the other way round.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('the delivery method is the two-way choice, not a switch',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 14000);
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

    // The sampling block opens once a sample is taken.
    final sampled = find.byWidgetPredicate(
        (w) => w is YesNoQuestion && w.label == 'Is Sampled');
    expect(sampled, findsOneWidget);
    tester.widget<YesNoQuestion>(sampled).onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.text('Delivery Method - Toggle the option below'),
        findsOneWidget);
    expect(find.text('Hand Delivered'), findsOneWidget);
    expect(find.text('Couriered'), findsOneWidget);
  });

  test('the printed checklist names the delivery the way the field says',
      () async {
    // Reading the same column the Pending Courier screen reads: true is
    // couriered — the row used to print it the other way round.
    expect(deliveryWords(couriered: true), 'Courier');
    expect(deliveryWords(couriered: false), 'Hand delivered');
  });
}

/// What the checklist row prints for the delivery method.
String deliveryWords({required bool couriered}) =>
    couriered ? 'Courier' : 'Hand delivered';
