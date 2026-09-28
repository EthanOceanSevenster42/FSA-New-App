import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fsa_form_pdf.dart';

/// One non-conformity on a direction: what was wrong, on which product, and
/// the regulation it offends.
class DirectionDeviation {
  const DirectionDeviation({
    required this.product,
    required this.nature,
    this.regulation = '',
  });

  final String product;
  final String nature;
  final String regulation;
}

/// The direction (rejection) served on a facility.
///
/// Reproduced from the layout the office already issues — FSA-WEB's
/// `...CompositionDirectionReport.rdl` and its siblings — so an inspector
/// serving one on the handset and the office printing one from the web are
/// working from the same sheet: the facility block, the nature of the
/// inspection, the deviations table, the date to rectify by, the actions and
/// remark, and the two signatures.
///
/// The handset had no direction document at all: the data went up and the
/// sheet existed only on the web, so nothing could be shown to the person it
/// was being served on.
abstract final class DirectionPdf {
  static Future<File> write({
    required File out,
    required FsaDocControl control,
    required String natureOfInspection,
    required String facilityName,
    required String ownerOrRepresentative,
    required String physicalAddress,
    required String emailAddress,
    required DateTime dateOfVisit,
    required String inspectionReason,
    required String latestReference,
    required String originalReference,
    required List<({String label, String value})> subjectFields,
    required List<DirectionDeviation> deviations,
    required String correctByDate,
    required String actionsAndRemark,
    required String inspectorName,
    required String authorisedPersonName,
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
    String pleaseNote = '',
    DateTime? generatedAt,
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.image(inspectorSignaturePath);
    final authorisedSignature =
        await FsaForm.image(authorisedPersonSignaturePath);
    final doc = pw.Document();

    String two(int v) => v.toString().padLeft(2, '0');
    final visit = '${two(dateOfVisit.day)}/${two(dateOfVisit.month)}/'
        '${dateOfVisit.year}';

    // Portrait: two columns inside 551pt, so a label and its box together
    // must stay under half the width or the box runs off the sheet.
    pw.Widget pair(String label, String value) =>
        FsaForm.field(label, value, a, labelWidth: 110, boxWidth: 150);
    pw.Widget wide(String label, String value) =>
        FsaForm.field(label, value, a, labelWidth: 110, boxWidth: 410);

    // The deviations table is the body of a direction: numbered so the
    // facility and the office can refer to a point by number when it is
    // rectified.
    pw.Widget deviationTable() {
      pw.Widget head(String v) => FsaForm.cell(v, a, isBold: true, size: 7);
      pw.Widget body(String v) => FsaForm.cell(v, a, size: 7);
      return pw.Table(
        border: FsaForm.border(),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.5),
          1: pw.FlexColumnWidth(2.0),
          2: pw.FlexColumnWidth(4.2),
          3: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(children: [
            head('Point'),
            head('Product'),
            head('Nature of Deviation'),
            head('Regulation Reference Number'),
          ]),
          for (var i = 0; i < deviations.length; i++)
            pw.TableRow(children: [
              body('${i + 1}'),
              body(deviations[i].product),
              body(deviations[i].nature),
              body(deviations[i].regulation),
            ]),
          // A direction with nothing on it is not served, but the sheet must
          // still rule a row rather than collapse the table.
          if (deviations.isEmpty)
            pw.TableRow(children: [body(''), body(''), body(''), body('')]),
        ],
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            FsaForm.header(a, control),
            FsaForm.heading('Producer/Importer/Butcher/Retailer Facility', a),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pair('Facility', facilityName),
                      pair('Owner / Manager / Representative',
                          ownerOrRepresentative),
                      pair('Physical Address', physicalAddress),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pair('E-Mail Address', emailAddress),
                      pair('Date of Visit', visit),
                      pair('Inspection', inspectionReason),
                    ],
                  ),
                ),
              ],
            ),
            pw.Row(
              children: [
                pw.Expanded(
                    child: pair('Latest Reference No.', latestReference)),
                pw.Expanded(
                    child: pair('Original Reference No.', originalReference)),
              ],
            ),
            FsaForm.heading('NATURE OF INSPECTION', a),
            pw.Text(natureOfInspection, style: a.text(size: 8)),
            if (subjectFields.isNotEmpty) ...[
              FsaForm.heading(natureOfInspection.toUpperCase(), a),
              for (final f in subjectFields) wide(f.label, f.value),
            ],
            FsaForm.heading('DEVIATIONS (NON-CONFORMITIES)', a),
            deviationTable(),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 7, bottom: 3),
              child: pw.Row(children: [
                pw.Text(
                  'Rectify the non-conformity as mentioned below before or on ',
                  style: a.text(size: 7.5),
                ),
                FsaForm.box(correctByDate, a, width: 90),
              ]),
            ),
            FsaForm.heading('ACTIONS AND REMARK', a),
            FsaForm.ruledLines(
              actionsAndRemark.isEmpty ? const [] : [actionsAndRemark],
              a,
              minimum: 3,
            ),
            if (pleaseNote.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text('Please note:  $pleaseNote',
                    style: a.text(size: 7)),
              ),
            pw.Spacer(),
            FsaForm.heading('SIGNATURES', a),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final side in [
                  (
                    caption: 'INSPECTOR:',
                    name: inspectorName,
                    signature: inspectorSignature
                  ),
                  (
                    caption: 'MANAGER:',
                    name: authorisedPersonName,
                    signature: authorisedSignature
                  ),
                ])
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(side.caption,
                            style: a.text(isBold: true, size: 7)),
                        pw.SizedBox(height: 2),
                        FsaForm.signatureLine(a,
                            signature: side.signature, width: 200),
                        pw.SizedBox(height: 3),
                        pw.Text('NAME & SURNAME',
                            style: a.text(isBold: true, size: 6.5)),
                        pw.SizedBox(
                          width: 200,
                          child: pw.Text(side.name, style: a.text(size: 7.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 4),
            FsaForm.footer(a),
          ],
        ),
      ),
    );

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    return out;
  }
}
