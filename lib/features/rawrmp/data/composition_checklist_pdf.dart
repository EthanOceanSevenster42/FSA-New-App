import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_form_pdf.dart';
import '../domain/composition_checklist.dart';

/// FSA's Compositional Requirements Checklist (SOP-APS-RAW-003, V1), filled
/// in from the raw processed meat inspection on the handset.
///
/// One landscape A4 page, laid out as the paper form: the document-control
/// header with the logo and the Act and regulation titles, FACILITY
/// INFORMATION in two columns, SAMPLE DETAILS, the nine-row Regulation 5
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
    String authorisedPersonName = '',
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
  }) async {
    final assets = await FsaForm.assets();
    final regular = assets.regular;
    final bold = assets.bold;
    final logo = assets.logo;
    final theme = assets.theme;

    Future<pw.MemoryImage?> image(String path) async {
      final file = File(path);
      if (path.isEmpty || !file.existsSync()) return null;
      return pw.MemoryImage(await file.readAsBytes());
    }

    final inspectorSignature = await image(inspectorSignaturePath);
    final clientSignature = await image(authorisedPersonSignaturePath);

    pw.TextStyle text({bool isBold = false, double size = 7.5}) =>
        pw.TextStyle(fontSize: size, font: isBold ? bold : regular);

    pw.Widget cell(String value,
            {bool isBold = false,
            PdfColor? fill,
            double size = 7,
            pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          color: fill,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
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
              cell('Chief Executive Officer'),
              cell('Page', fill: grey),
              cell('Page 1 of 1'),
            ]),
          ],
        );

    pw.Widget header() => pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(6.4),
          },
          children: [
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                pw.Container(
                  height: 96,
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
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
    pw.Widget heading(String label) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 7, bottom: 3),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7.5,
                  font: bold,
                  decoration: pw.TextDecoration.underline)),
        );

    pw.Widget box(String value, {double width = 190}) => pw.Container(
          width: width,
          height: 13,
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
          padding: const pw.EdgeInsets.only(bottom: 4),
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
          cell('CONTRIBUTION (g)', isBold: true, align: pw.Alignment.center),
          cell('REMARKS', isBold: true, align: pw.Alignment.center),
        ]),
      ];
      for (var i = 0; i < CompositionChecklist.items.length; i++) {
        final a = i < answers.length ? answers[i] : const CompositionAnswer();
        rows.add(pw.TableRow(children: [
          cell('${i + 1}. ${CompositionChecklist.items[i]}'),
          cell(a.deviation == true ? 'X' : '',
              isBold: true, align: pw.Alignment.center),
          cell(a.deviation == false ? 'X' : '',
              isBold: true, align: pw.Alignment.center),
          // Total Meat Content prints its worked-out percentage, and the
          // two amounts it came from beside the remark.
          cell(
              i == CompositionChecklist.totalMeatIndex &&
                      a.totalMeatPercent != null
                  ? CompositionChecklist.percentText(a.totalMeatPercent!)
                  : a.contributionGrams,
              align: pw.Alignment.center),
          cell(i == CompositionChecklist.totalMeatIndex &&
                  a.totalMeatPercent != null
              ? [
                  'Meat ${a.meatGrams} g / all other ingredients '
                      '${a.otherGrams} g',
                  if (a.remarks.trim().isNotEmpty) a.remarks,
                ].join('\n')
              : a.remarks),
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
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
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
    final commentLines = _wrap(comments, 150);
    pw.Widget commentsBlock() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 130,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text('COMMENTS/ACTIONS:',
                      style: text(isBold: true, size: 7)),
                )),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0;
                      i < (commentLines.length > 2 ? commentLines.length : 2);
                      i++)
                    pw.Container(
                      height: 14,
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
                      child: pw.Text(
                          i < commentLines.length ? commentLines[i] : '',
                          style: text(size: 7.5)),
                    ),
                ],
              ),
            ),
          ],
        );

    pw.Widget signLine(pw.MemoryImage? sig, {String name = ''}) => pw.Container(
          width: 150,
          height: 22,
          alignment: pw.Alignment.bottomCenter,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
          child: sig != null
              ? pw.Image(sig, height: 20, fit: pw.BoxFit.contain)
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
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header(),
            heading('FACILITY INFORMATION:'),
            facility(),
            heading('SAMPLE DETAILS'),
            sample(),
            pw.SizedBox(height: 6),
            checklist(),
            pw.SizedBox(height: 8),
            commentsBlock(),
            pw.SizedBox(height: 10),
            signing(),
            pw.Spacer(),
            pw.Center(
                child: pw.Text('@ Food Safety Agency (Pty) Ltd',
                    style: text(size: 6.5))),
          ],
        ),
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
