import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_documents.dart';
import '../../../core/documents/fsa_form_pdf.dart';
import '../domain/composition_checklist.dart';

/// FSA's Compositional Requirements Checklist (SOP-APS-RAW-003, V1), filled
/// in from the raw processed meat inspection on the handset.
///
/// One landscape A4 page, laid out as the paper form: the document-control
/// header with the logo and the Act and regulation titles, FACILITY
/// INFORMATION in two columns, SAMPLE DETAILS, the seven-row Regulation 5
/// table (deviation YES/NO, contribution in grams, remarks), COMMENTS/ACTIONS
/// on ruled lines, and the two signature blocks.
abstract final class CompositionChecklistPdf {
  static Future<File> write({
    required File out,
    required String facilityName,
    required String facilityAddress,
    required String dateOfSampling,
    required String siteRepresentative,
    required String representativePosition,
    required String facilityType,
    required String productName,
    required String batchNumber,
    required String manufacturedPackedDate,
    required List<CompositionAnswer> answers,
    required String comments,
    required String inspectorName,

    /// The checklist's one remark, printed under the table (Ethan,
    /// 2026-09-30) — the rows no longer carry their own.
    String remarks = '',

    /// The unit the amounts were typed in: kg, or grams on a record from
    /// before the change (Ethan, 2026-10-01).
    String unit = CompositionChecklist.kg,

    /// The remarks of the rejection the checklist raised, one per line;
    /// printed under the comments when there are any (Ethan, 2026-09-29).
    String rejectionRemarks = '',
    String authorisedPersonName = '',
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
  }) async {
    final assets = await FsaForm.assets();
    final regular = assets.regular;
    final bold = assets.bold;

    final inspectorSignature = await FsaForm.signature(inspectorSignaturePath);
    final clientSignature = await FsaForm.signature(authorisedPersonSignaturePath);

    pw.TextStyle text({bool isBold = false, double size = 7.5}) =>
        pw.TextStyle(fontSize: size, font: isBold ? bold : regular);

    pw.Widget cell(String value,
            {bool isBold = false,
            PdfColor? fill,
            double size = 7,
            pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          color: fill,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          alignment: align,
          child: pw.Text(value, style: text(isBold: isBold, size: size)),
        );

    const grey = PdfColors.grey300;
    final border = pw.TableBorder.all(width: 0.6, color: PdfColors.grey800);

    // ------------------------------------------------------------ header
    pw.Widget control() => pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(5.0),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(children: [
              cell('Doc Type', fill: grey),
              cell('Checklist'),
              cell('Issue Date', fill: grey),
              cell('1 January 2024'),
            ]),
            pw.TableRow(children: [
              cell('Doc No.', fill: grey),
              cell(CompositionChecklist.docNo),
              cell('Eff. Date', fill: grey),
              cell('1 January 2024'),
            ]),
            pw.TableRow(children: [
              cell('IP', fill: grey),
              cell('Food Safety Agency (Pty) Ltd'),
              cell('Rev. Date', fill: grey),
              cell('31 July 2025'),
            ]),
            pw.TableRow(children: [
              cell('Designed by', fill: grey),
              cell('N Bergh'),
              cell('Revision', fill: grey),
              cell(CompositionChecklist.revision),
            ]),
            pw.TableRow(children: [
              cell('Approved by', fill: grey),
              cell('Compliance Manager'),
              cell('Page', fill: grey),
              cell('Page 1 of 1'),
            ]),
          ],
        );

    pw.Widget header() => pw.Table(
          border: border,
          columnWidths: const {0: pw.FlexColumnWidth(1.0)},
          children: [
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                // The Agency's mark is on the letterhead now (Ethan,
                // 2026-10-04), not beside the control table.
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                      alignment: pw.Alignment.center,
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  width: 0.6, color: PdfColors.grey800))),
                      child: pw.Text(CompositionChecklist.act,
                          style: text(isBold: true, size: 8)),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2.5, horizontal: 4),
                      alignment: pw.Alignment.center,
                      child: pw.Text(CompositionChecklist.regulation,
                          textAlign: pw.TextAlign.center,
                          style: text(isBold: true, size: 7.5)),
                    ),
                    control(),
                  ],
                ),
              ],
            ),
          ],
        );

    // ------------------------------------------------------------ fields
    // Shared grey section bar, so this sheet sections off the same as every
    // other report (Ethan, 2026-10-08).
    // Compact bars: this is the Agency's one-sheet form and must not
    // run to a second page (Ethan, 2026-10-08).
    pw.Widget heading(String label) =>
        FsaForm.heading(label, assets, compact: true);

    pw.Widget box(String value, {double width = 190}) => pw.Container(
          width: width,
          height: 11,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3),
          alignment: pw.Alignment.centerLeft,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
          child: pw.Text(value,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: text(size: 7.5)),
        );

    pw.Widget field(String label, String value,
            {double labelWidth = 130, double boxWidth = 190}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                  width: labelWidth,
                  child: pw.Text(label, style: text(isBold: true, size: 7))),
              box(value, width: boxWidth),
            ],
          ),
        );

    pw.Widget facility() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('NAME OF FACILITY:', facilityName),
                  field('PHYSICAL ADDRESS OF FACILITY:', facilityAddress),
                  field('DATE OF SAMPLING:', dateOfSampling, boxWidth: 95),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('SITE RESPRESENTATIVE:', siteRepresentative,
                      labelWidth: 135, boxWidth: 130),
                  field('POSITION OF REPRESENTATIVE:', representativePosition,
                      labelWidth: 135, boxWidth: 130),
                  field(
                      'TYPE OF FACILITY (butchery, retailer, re-packer, etc.):',
                      facilityType,
                      labelWidth: 185,
                      boxWidth: 80),
                ],
              ),
            ),
          ],
        );

    pw.Widget sample() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            field('PRODUCT NAME:', productName),
            field('BATCH NUMBER:', batchNumber),
            field('MANUFACTURED/PACKED DATE:', manufacturedPackedDate,
                boxWidth: 95),
          ],
        );

    // ------------------------------------------------------------- table
    pw.Widget checklist() {
      final rows = <pw.TableRow>[
        pw.TableRow(children: [
          cell('PERMISSABLE INGREDIENTS - REGULATION 5', isBold: true),
          cell('YES', isBold: true, align: pw.Alignment.center),
          cell('NO', isBold: true, align: pw.Alignment.center),
          cell('CONTRIBUTION ($unit)',
              isBold: true, align: pw.Alignment.center),
          cell('REMARKS', isBold: true, align: pw.Alignment.center),
        ]),
      ];
      final totalPercent = CompositionChecklist.totalMeatPercent(answers);
      for (var i = 0; i < CompositionChecklist.items.length; i++) {
        final a = i < answers.length ? answers[i] : const CompositionAnswer();
        // Total Meat Content is not judged: no number and no deviation
        // mark, only its percentage (Ethan, 2026-10-01).
        final isTotal = i == CompositionChecklist.totalMeatIndex;
        rows.add(pw.TableRow(children: [
          cell(
              isTotal
                  ? CompositionChecklist.items[i]
                  : '${i + 1}. ${CompositionChecklist.items[i]}',
              isBold: isTotal),
          cell(!isTotal && a.deviation == true ? 'X' : '',
              isBold: true, align: pw.Alignment.center),
          // A row left on Compliant — the slider's starting place — is a
          // NO, as the form shows it (Ethan, 2026-09-30).
          cell(!isTotal && a.deviation != true ? 'X' : '',
              isBold: true, align: pw.Alignment.center),
          // Total Meat Content prints its worked-out percentage: meat (row
          // 1) over the whole (rows 1 to 6), × 100 (Ethan, 2026-10-02).
          cell(
              isTotal
                  ? (totalPercent == null
                      ? ''
                      : CompositionChecklist.percentText(totalPercent))
                  : a.contributionGrams,
              isBold: isTotal,
              align: pw.Alignment.center),
          cell(a.remarks),
        ]));
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // The "DEVIATION" caption spanning the YES/NO columns, as on the
          // form.
          pw.Row(children: [
            pw.Expanded(flex: 620, child: pw.SizedBox()),
            pw.Container(
              width: 100,
              padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.6, color: PdfColors.grey800)),
              child: pw.Text('DEVIATION', style: text(isBold: true, size: 7)),
            ),
            pw.Expanded(flex: 275, child: pw.SizedBox()),
          ]),
          pw.Table(
            border: border,
            columnWidths: const {
              0: pw.FlexColumnWidth(6.2),
              1: pw.FlexColumnWidth(0.5),
              2: pw.FlexColumnWidth(0.5),
              3: pw.FlexColumnWidth(0.85),
              4: pw.FlexColumnWidth(1.9),
            },
            children: rows,
          ),
        ],
      );
    }

    // ---------------------------------------------------- comments, signing
    /// A caption beside ruled lines, as the form's comments are written.
    pw.Widget linedBlock(String caption, List<String> lines) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 130,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(caption, style: text(isBold: true, size: 7)),
                )),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // One ruled line is enough when the text is short: this
                  // form is one sheet and a rejection's remarks can add
                  // three lines of their own (Ethan, 2026-10-08).
                  for (var i = 0; i < (lines.length > 1 ? lines.length : 1); i++)
                    pw.Container(
                      height: 10,
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
                      child: pw.Text(i < lines.length ? lines[i] : '',
                          style: text(size: 7.5)),
                    ),
                ],
              ),
            ),
          ],
        );
    pw.Widget commentsBlock() =>
        linedBlock('COMMENTS:', _wrap(comments, 150));
    final remarksLines = _wrap(remarks, 150);
    final remarkLines = [
      for (final remark in rejectionRemarks.split('\n'))
        if (remark.trim().isNotEmpty) ..._wrap('• ${remark.trim()}', 150),
    ];

    // A signature gets a line tall enough to read (Ethan, 2026-09-30); a
    // name line stays one line of type.
    pw.Widget signLine(pw.MemoryImage? sig, {String name = ''}) => pw.Container(
          width: 150,
          height: sig != null ? 40 : 22,
          alignment: pw.Alignment.bottomCenter,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
          child: sig != null
              ? pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1),
                  child: pw.Image(sig, height: 36, fit: pw.BoxFit.contain))
              : pw.Text(name, style: text(size: 7.5)),
        );

    pw.Widget signing() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 130,
                child: pw.Text('SIGNED:', style: text(isBold: true, size: 7))),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                        width: 150,
                        child: pw.Text('FOOD SAFETY AGENCY INSPECTOR:',
                            style: text(isBold: true, size: 7))),
                    signLine(inspectorSignature),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                        width: 150,
                        child: pw.Text('NAME & SURNAME:',
                            style: text(isBold: true, size: 7))),
                    signLine(null, name: inspectorName),
                  ],
                ),
              ]),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                        width: 150,
                        child: pw.Text('FACILITY AUTHORISED PERSON:',
                            style: text(isBold: true, size: 7))),
                    signLine(clientSignature),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.SizedBox(
                        width: 150,
                        child: pw.Text('NAME & SURNAME:',
                            style: text(isBold: true, size: 7))),
                    signLine(null, name: authorisedPersonName),
                  ],
                ),
              ]),
            ),
          ],
        );

    final document = pw.Document(
      title: 'Compositional Checklist — $facilityName',
      author: inspectorName,
    );
    document.addPage(
      pw.MultiPage(
        pageTheme: FsaForm.letterhead(assets, PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
        build: (context) => [
            FsaForm.header(assets, FsaDocuments.rawComposition),
            heading('FACILITY INFORMATION:'),
            facility(),
            heading('SAMPLE DETAILS'),
            sample(),
            checklist(),
            heading('COMMENTS AND REMARKS'),
            if (remarksLines.isNotEmpty) ...[
              linedBlock('REMARKS:', remarksLines),
              pw.SizedBox(height: 2),
            ],
            commentsBlock(),
            if (remarkLines.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              linedBlock('REJECTION REMARKS:', remarkLines),
            ],
            FsaForm.heading('SIGNATURE CONTROLS', assets, compact: true),
            FsaForm.signedBlock(
              assets,
              compact: true,
              inspectorName: inspectorName,
              authorisedPersonName: authorisedPersonName,
              inspectorSignature: inspectorSignature,
              authorisedPersonSignature: clientSignature,
            ),
        ],
      ),
    );

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await document.save(), flush: true);
    return out;
  }

  /// Greedy word wrap for the ruled comment lines.
  static List<String> _wrap(String text, int width) {
    final lines = <String>[];
    for (final paragraph in text.trim().split('\n')) {
      var line = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final candidate = line.isEmpty ? word : '$line $word';
        if (candidate.length <= width) {
          line = candidate;
        } else {
          if (line.isNotEmpty) lines.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }
    return lines;
  }
}
