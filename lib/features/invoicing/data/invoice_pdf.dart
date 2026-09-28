import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_form_pdf.dart';

import '../domain/invoice_form_data.dart';
import '../domain/invoice_rules.dart';

/// Renders the Request for Invoice form (SOP-APS-002 V8) as a PDF, laid out
/// as the Agency's document is: the letterhead, the particulars, the tick
/// boxes, the three costing tables and the two signature lines.
///
/// Built rather than filled into the supplied Word file: the app has to
/// produce this offline, on a handset, from a record — and a template that
/// has to be shipped, parsed and written into is a second thing to keep in
/// step with the form. What is on the page here is what the form prints.
///
/// One page, always. The form is a single sheet the office signs and files,
/// and a second sheet carrying two signature lines and nothing else is not
/// the same document. Everything is therefore sized to fit A4 once: the
/// particulars take one line each however long the name, and the type is as
/// small as the printed form's own small print. [test/invoice_pdf_test.dart]
/// holds it to one page with every field filled at its longest.
abstract final class InvoicePdf {
  // A signed RIF is printed and filed.  Keep enough vertical space for the
  // captured handwriting to remain plainly legible on paper.
  static const _signatureHeight = 56.0;

  static const _letterhead = 'Food Safety Agency (Pty) Ltd\n'
      '318 The Hillside Building, The Hillside Street, Lynnwood, Pretoria '
      '(4th Floor). PO Box 35224, Menlo Park, 0102\n'
      'Tel: (012) 361 1937 • Email: info@afsq.co.za • '
      'www.foodsafetyagency.co.za';

  static String _dmy(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Writes the form to [outputPath] and returns it.
  static Future<File> write(
    InvoiceFormData form, {
    required String outputPath,
  }) async {
    // The hours the money is worked out from. The column that prints them
    // has to be the same figures, or the form shows an hour count that does
    // not multiply out to the amount beside it.
    final bands = InvoiceRules.chargeableBands(
      normal: form.normalHours,
      overtime: form.overtimeHours,
      sunday: form.sundayHours,
    );
    // Certain raw processed meat and processed meat carry a kilometre
    // charge; the others do not. The distance is printed either way — the
    // office wants to see how far the inspector drove — so the basis column
    // says which it is rather than leaving a rate beside a nought.
    final chargeTravel = InvoiceRules.travelIsChargeable(
      rawRmp: form.rawRmpTicked,
      pmp: form.pmpTicked,
    );
    final totals = InvoiceRules.totals(
      normalHours: form.normalHours,
      overtimeHours: form.overtimeHours,
      sundayHours: form.sundayHours,
      kilometres: form.kilometres,
      chargeTravel: chargeTravel,
      pmpFatTests: form.pmpFatTests,
      pmpProteinTests: form.pmpProteinTests,
      pmpCalciumTests: form.pmpCalciumTests,
      pmpPhysicalTests: form.pmpPhysicalTests,
      rawFatTests: form.rawFatTests,
      rawProteinTests: form.rawProteinTests,
      rawSoyaTests: form.rawSoyaTests,
      rawStarchTests: form.rawStarchTests,
      rawDnaTests: form.rawDnaTests,
      rawCalciumTests: form.rawCalciumTests,
    );

    // Lato is the Agency's typeface and travels in the APK, so the PDF reads
    // as their document rather than in the pdf package's default face.
    final assets = await FsaForm.assets();
    final regular = assets.regular;
    final bold = assets.bold;
    final logo = assets.letterhead;

    final document = pw.Document(
      title: 'Request for Invoice — ${form.siteVisited}',
      author: form.inspectorName,
    );

    Future<pw.Widget?> signature(String path, String caption) async {
      final file = File(path);
      if (path.isEmpty || !file.existsSync()) return null;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Image(
            pw.MemoryImage(await file.readAsBytes()),
            height: _signatureHeight,
            fit: pw.BoxFit.contain,
          ),
          pw.Container(width: 200, height: 0.8, color: PdfColors.black),
          pw.Text(caption, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      );
    }

    final managerSignature = await signature(
        form.managerSignaturePath,
        'Manager/Owner/'
        'Responsible Person Signature');
    final inspectorSignature =
        await signature(form.inspectorSignaturePath, 'Inspector Signature');

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 22, 30, 22),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // The Agency's letterhead, as the printed form carries it: the
            // anniversary mark at the left, the address block centred.
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 96,
                  height: 96,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    _letterhead,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 7.5, height: 1.4),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text('REQUEST FOR INVOICE FORM',
                  style: pw.TextStyle(fontSize: 12.5, font: bold)),
            ),
            pw.SizedBox(height: 8),
            _particular('Inspector Name:', form.inspectorName),
            _particular('Site/Manufacturer Visited:', form.siteVisited),
            _particular(
                'Site Manager/Owner/Responsible Person:', form.siteManager),
            _particular('Product Name:', form.productName),
            _particular('Date of Visit:', _dmy(form.dateOfVisit)),
            pw.Row(
              children: [
                pw.Expanded(
                    child: _particular(
                        'Inspection Time Started:', form.timeStarted)),
                pw.SizedBox(width: 12),
                pw.Expanded(
                    child:
                        _particular('Inspection Time Ended:', form.timeEnded)),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'The request for invoicing is in terms of the following '
              'inspections (please tick the applicable box):',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                _tick('Processed Meat Products', form.pmpTicked),
                _tick('Raw Processed Meat Products', form.rawRmpTicked),
                _tick('Eggs', form.eggsTicked),
                _tick('Poultry Meat', form.poultryTicked),
                _tick('Sample Taking', form.sampleTakingTicked),
              ],
            ),
            pw.SizedBox(height: 9),
            _tableHeading('Invoicing:  Inspection of Poultry Meat, Processed '
                'Meat Products and Certain Raw Processed Meat Products'),
            _grid(
              header: const [
                '',
                'Per Hour Rate',
                'Hours Services Rendered',
                'Amount for Invoicing',
              ],
              rows: [
                [
                  'Normal Time (08:00 – 16:00)',
                  '${_rate(InvoiceRates.normalHour)} per hour',
                  '${_hours(bands.normal)} x ${_rate(InvoiceRates.normalHour)}',
                  InvoiceRules.rand(totals.normal),
                ],
                [
                  'Normal Overtime (Mon – Sat)',
                  '${_rate(InvoiceRates.overtimeHour)} per hour',
                  '${_hours(bands.overtime)} x '
                      '${_rate(InvoiceRates.overtimeHour)}',
                  InvoiceRules.rand(totals.overtime),
                ],
                [
                  'Sunday & Public Holidays',
                  '${_rate(InvoiceRates.sundayHour)} per hour',
                  '${_hours(bands.sunday)} x ${_rate(InvoiceRates.sundayHour)}',
                  InvoiceRules.rand(totals.sunday),
                ],
                [
                  'Kilometre Rate',
                  chargeTravel
                      ? '${_rate(InvoiceRates.perKilometre)} per kilometre'
                      : 'Not charged on this commodity',
                  chargeTravel
                      ? '${_number(form.kilometres)} km x '
                          '${_rate(InvoiceRates.perKilometre)}'
                      : '${_number(form.kilometres)} km travelled',
                  InvoiceRules.rand(totals.travel),
                ],
                ['Total', '', '', InvoiceRules.rand(totals.inspection)],
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '-  Where hourly rates are applicable, a minimum of one hour '
              '(R540.60) will be charged. Thereafter time will be charged in '
              'half hour segments of R270.30 per half hour or part thereof. '
              'The same principle will be applied to overtime and Sunday '
              'time.\n'
              '-  In all instances where it is found that the hourly and '
              'kilometre rates are insufficient to cover the costs of the '
              'inspections, Food Safety Agency (Pty) Ltd, at its own '
              'discretion, reserves the right to amend the rates.',
              style: const pw.TextStyle(fontSize: 6.5, height: 1.25),
            ),
            pw.SizedBox(height: 8),
            _tableHeading('Invoicing:  Laboratory Cost - Processed Meat '
                'Products (Only applicable if sample taken)'),
            _grid(
              header: const [
                'Type of analysis',
                'Fee',
                'Number of Tests',
                'Invoice',
              ],
              rows: [
                _labRow('Fat Content', 'R875.56', form.pmpFatTests,
                    InvoiceRates.pmpFat),
                _labRow('Protein Content', 'R533.18', form.pmpProteinTests,
                    InvoiceRates.pmpProtein),
                _labRow('Calcium Determination (MRM only)', 'R401.74',
                    form.pmpCalciumTests, InvoiceRates.pmpCalcium),
                _labRow('Physical Test (coated products)', 'R212.00',
                    form.pmpPhysicalTests, InvoiceRates.pmpPhysical),
                ['Total', '', '', InvoiceRules.rand(totals.pmpLab)],
              ],
            ),
            pw.SizedBox(height: 8),
            _tableHeading('Invoicing:  Laboratory Cost – Certain Raw Processed '
                'Meat Products (Only applicable if sample taken)'),
            _grid(
              header: const [
                'Type of analysis',
                // No category letters (Ethan, 2026-09-24): they were there to
                // help inspectors work the sum by hand; the form does it.
                'Fee',
                'Number of Tests',
                'Invoice',
              ],
              rows: [
                _labRow('Fat Content', 'R875.56', form.rawFatTests,
                    InvoiceRates.rawFat),
                _labRow('Protein Content (Meat Content)', 'R533.18',
                    form.rawProteinTests, InvoiceRates.rawProtein),
                _labRow('Soya Content', 'R1 764.90', form.rawSoyaTests,
                    InvoiceRates.rawSoya),
                _labRow('Starch Content', 'R1 560.32', form.rawStarchTests,
                    InvoiceRates.rawStarch),
                _labRow('Meat Specie Identification (DNA)', 'R2 761.30',
                    form.rawDnaTests, InvoiceRates.rawDna),
                _labRow('Calcium Determination (MRM only)', 'R401.74',
                    form.rawCalciumTests, InvoiceRates.rawCalcium),
                ['Total', '', '', InvoiceRules.rand(totals.rawLab)],
              ],
            ),
            pw.SizedBox(height: 9),
            pw.Text(
              'Total Invoice Amount: ${InvoiceRules.rand(totals.grand)}  '
              '(excluding 15% VAT)',
              style: pw.TextStyle(fontSize: 10.5, font: bold),
            ),
            // Whatever room is left goes above the signatures, so they sit at
            // the foot of the sheet as they do on the printed form.
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: managerSignature ??
                      _signatureLine('Manager/Owner/Responsible Person '
                          'Signature'),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(child: _dateSigned(_dmy(form.signedAt))),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: inspectorSignature ??
                      _signatureLine('Inspector Signature'),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(child: _dateSigned(_dmy(form.signedAt))),
              ],
            ),
          ],
        ),
      ),
    );

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  /// A band that was not worked leaves the blank the paper form leaves.
  static String _hours(double hours) =>
      hours <= 0 ? '____' : _number(hours);

  /// A rate as the form prints it, taken from the tariff so a rate change is
  /// one edit rather than one per place it is written.
  static String _rate(double amount) => InvoiceRules.rand(amount);

  static String _number(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  static List<String> _labRow(
          String analysis, String fee, int count, double rate) =>
      [
        analysis,
        '$fee per sample/test',
        '${count == 0 ? '____' : count} x $fee',
        InvoiceRules.rand(count * rate),
      ];

  static pw.Widget _particular(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
                ),
                padding: const pw.EdgeInsets.only(bottom: 1),
                // One line, whatever the inspector typed: a wrapped site
                // name would push the signatures onto a second sheet.
                child: pw.Text(
                  value,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ),
          ],
        ),
      );

  static pw.Widget _tick(String label, bool ticked) => pw.Expanded(
        child: pw.Row(
          children: [
            pw.Container(
              width: 9,
              height: 9,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.8),
              ),
              alignment: pw.Alignment.center,
              child: ticked
                  ? pw.Text('X',
                      style: const pw.TextStyle(fontSize: 7, height: 1))
                  : null,
            ),
            pw.SizedBox(width: 3),
            pw.Expanded(
              child: pw.Text(label,
                  style: const pw.TextStyle(fontSize: 7.5, height: 1.1)),
            ),
          ],
        ),
      );

  static pw.Widget _tableHeading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
      );

  static pw.Widget _grid({
    required List<String> header,
    required List<List<String>> rows,
  }) =>
      pw.TableHelper.fromTextArray(
        headers: header,
        data: rows,
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
        headerStyle: const pw.TextStyle(fontSize: 7.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.8),
        cellAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.centerRight,
        },
      );

  static pw.Widget _signatureLine(String caption) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: _signatureHeight),
          pw.Container(width: 200, height: 0.8, color: PdfColors.black),
          pw.Text(caption, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      );

  static pw.Widget _dateSigned(String date) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: _signatureHeight),
          pw.Container(
            width: 140,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
            ),
            child: pw.Text(date, style: const pw.TextStyle(fontSize: 8.5)),
          ),
          pw.Text('Date Signed', style: const pw.TextStyle(fontSize: 7.5)),
        ],
      );
}
