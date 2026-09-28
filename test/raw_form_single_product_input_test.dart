import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The raw red meat form asks for the product once.
///
/// It used to carry three extra boxes under the product picker — "New Raw
/// Meat Product Item", "New PMP Item Size (g)", "New PMP Item Barcode" — the
/// original's copy-pasted PMP wording on a raw meat screen. A product that is
/// not on the list is added through the picker's own "Add new product"
/// offer, which collects name, size and barcode in one sheet.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('one product input, and no PMP wording anywhere', (tester) async {
    // Tall enough that the whole form is laid out, so a finder that comes
    // back empty means the field is gone, not merely below the fold.
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = RawRmpRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    final capture = PoultryCaptureRepository(
      database: db,
      baseUrl: 'http://example.test',
    );
    // The form only draws its fields once the rules are on the device.
    await repo.loadBundledRulesIfEmpty();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: RawRmpInspectionForm(
        repository: repo,
        captureRepository: capture,
        inspectorName: 'Ethan',
      ),
    ));
    await tester.pumpAndSettle();

    // Exact text: the page title also contains the phrase.
    expect(
        find.text('Certain Raw Processed Meat Product', findRichText: true),
        findsOneWidget,
        reason: 'the product section rendered');
    expect(find.text('New Raw Meat Product Item', findRichText: true), findsNothing);
    expect(find.text('New PMP Item Size (g)', findRichText: true), findsNothing);
    expect(find.text('New PMP Item Barcode', findRichText: true), findsNothing);
    expect(find.textContaining('PMP', findRichText: true), findsNothing,
        reason: 'this is the raw red meat screen');
  });
}
