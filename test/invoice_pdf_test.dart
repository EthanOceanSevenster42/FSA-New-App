import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/invoicing/data/invoice_pdf.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_form_data.dart';

/// The Request for Invoice is one sheet.
///
/// It is signed and filed as a single page, so a form that spills onto a
/// second sheet — even one carrying nothing but the signature lines — is
/// wrong. This renders the fullest form the app can produce: every commodity
/// ticked, every laboratory test counted, and names longer than any real
/// site's.
void main() {
  // The form loads the Agency's typeface and letterhead from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  // The document layer is plain Dart; the handset installs its font and
  // logo loader at start-up, and a test that renders a form has to do the
  // same or it has no assets to draw with.
  installFsaFormAssets();

  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('rfi'));
  tearDown(() => scratch.deleteSync(recursive: true));

  InvoiceFormData form({
    String site = 'Kroon Foods Test Store',
    int tests = 0,
  }) =>
      InvoiceFormData(
        inspectorName: 'Ethan',
        siteVisited: site,
        siteManager: 'Test Manager',
        productName:
            'Eggs, Poultry Meat, Raw Processed Meat, Processed Meat',
        dateOfVisit: DateTime(2026, 8, 22),
        timeStarted: '21:16',
        timeEnded: '21:25',
        pmpTicked: true,
        rawRmpTicked: true,
        eggsTicked: true,
        poultryTicked: true,
        sampleTakingTicked: true,
        normalHours: 0,
        overtimeHours: 1,
        sundayHours: 0,
        kilometres: 5,
        pmpFatTests: tests,
        pmpProteinTests: tests,
        pmpCalciumTests: tests,
        pmpPhysicalTests: tests,
        rawFatTests: tests,
        rawProteinTests: tests,
        rawSoyaTests: tests,
        rawStarchTests: tests,
        rawDnaTests: tests,
        rawCalciumTests: tests,
        managerSignaturePath: '',
        inspectorSignaturePath: '',
        signedAt: DateTime(2026, 8, 22),
      );

  Future<int> pagesOf(InvoiceFormData request) async {
    final file = await InvoicePdf.write(
      request,
      outputPath: '${scratch.path}/rfi.pdf',
    );
    final bytes = await file.readAsBytes();
    // Page objects declare their type in the object dictionary, which the
    // pdf package writes uncompressed; /Pages is the tree node, not a page.
    return RegExp(r'/Type\s*/Page[^s]')
        .allMatches(String.fromCharCodes(bytes))
        .length;
  }

  test('a typical visit prints on one page', () async {
    expect(await pagesOf(form()), 1);
  });

  test('every laboratory test filled still prints on one page', () async {
    expect(await pagesOf(form(tests: 9)), 1);
  });

  test('a very long site name does not push it onto a second page',
      () async {
    expect(
      await pagesOf(form(
        site: 'Kroonstad Cooperative Poultry Abattoir and Processing '
            'Facility Number Seventeen (Northern Free State Division)',
      )),
      1,
    );
  });
}
