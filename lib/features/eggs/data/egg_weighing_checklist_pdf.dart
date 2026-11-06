import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_documents.dart';
import '../../../core/documents/fsa_form_pdf.dart';

/// One weighed egg, as the checklist prints it.
class EggWeighingRow {
  const EggWeighingRow({
    required this.number,
    this.massG,
    this.albumenHeightMm,
    this.haughUnit,
    this.deviations = const [],
    this.comments = '',
  });

  final int number;
  final double? massG;

  /// The Haugh meter reading in millimetres, before the formula.
  final double? albumenHeightMm;

  /// The Haugh unit the formula gives for that reading and mass.
  final double? haughUnit;

  /// The deviations ticked on this egg, already resolved to their wording.
  final List<String> deviations;
  final String comments;
}

/// FSA's Egg Weighing Checklist (SOP-APS-EGGS-003, revision V5).
///
/// The Agency's office system renders this from SSRS as a landscape sheet:
/// the document-control header, the facility and consignment particulars,
/// then a row per egg — number, weight, Haugh reading, Haugh value, the
/// deviations found and any comment — with the tray label photograph and
/// the two signatures. This is the same sheet, produced on the handset at
/// sign-off instead of by the office days later.
abstract final class EggWeighingChecklistPdf {
  /// Rows that fit under the header on the first page, and on a continuation
  /// page which carries no particulars block.
  // Fewer than before the letterhead (Ethan, 2026-10-04): the logo and
  // address above and the band below take about five rows' height.
  static const _rowsOnFirstPage = 11;
  static const _rowsOnLaterPages = 25;

  static Future<File> write({
    required File out,
    required String facilityName,
    required String facilityAddress,
    required String dateOfInspection,
    required String representative,
    required String facilityType,
    required String producerSupplier,
    required String batchNumber,
    required String bestBefore,
    required String declaredSize,
    required String declaredGrade,
    required String traySize,
    required List<EggWeighingRow> rows,
    required String inspectorName,
    String authorisedPersonName = '',
    String comments = '',
    String trayLabelPhotoPath = '',
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.signature(inspectorSignaturePath);
    final clientSignature = await FsaForm.signature(authorisedPersonSignaturePath);
    final trayPhoto = await FsaForm.image(trayLabelPhotoPath);

    final firstRows = rows.take(_rowsOnFirstPage).toList();
    final laterRows = rows.skip(_rowsOnFirstPage).toList();
    final pages = 1 +
        (laterRows.isEmpty ? 0 : (laterRows.length / _rowsOnLaterPages).ceil());

    pw.Widget particulars() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  FsaForm.field('NAME OF FACILITY:', facilityName, a),
                  FsaForm.field(
                      'PHYSICAL ADDRESS OF FACILITY:', facilityAddress, a),
                  FsaForm.field('DATE OF INSPECTION:', dateOfInspection, a,
                      boxWidth: 95),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  FsaForm.field('SITE REPRESENTATIVE:', representative, a,
                      labelWidth: 135, boxWidth: 130),
                  FsaForm.field('PRODUCER/SUPPLIER:', producerSupplier, a,
                      labelWidth: 135, boxWidth: 130),
                  FsaForm.field('TYPE OF FACILITY:', facilityType, a,
                      labelWidth: 135, boxWidth: 130),
                ],
              ),
            ),
          ],
        );

    pw.Widget consignment() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  FsaForm.field('BATCH NUMBER:', batchNumber, a),
                  FsaForm.field('BEST BEFORE DATE:', bestBefore, a,
                      boxWidth: 95),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  FsaForm.field('SIZE DECLARED:', declaredSize, a,
                      labelWidth: 135, boxWidth: 130),
                  FsaForm.field('GRADE DECLARED:', declaredGrade, a,
                      labelWidth: 135, boxWidth: 130),
                  FsaForm.field('TRAY PACKAGING SIZE:', traySize, a,
                      labelWidth: 135, boxWidth: 130),
                ],
              ),
            ),
          ],
        );

    String number(double? v, {int decimals = 1}) =>
        v == null ? '' : v.toStringAsFixed(decimals);

    pw.Widget table(List<EggWeighingRow> slice) {
      pw.Widget head(String v) => FsaForm.cell(v, a,
          isBold: true, fill: FsaForm.grey, align: pw.Alignment.center);
      return pw.Table(
        border: FsaForm.border(),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.8),
          1: pw.FlexColumnWidth(1.0),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1.0),
          4: pw.FlexColumnWidth(3.4),
          5: pw.FlexColumnWidth(2.6),
        },
        children: [
          pw.TableRow(children: [
            head('Egg Number'),
            head('Weight  (g)'),
            head('Haugh Reading (mm)'),
            head('Haugh Value'),
            head('Deviation'),
            head('Comments (if found)'),
          ]),
          for (final r in slice)
            pw.TableRow(children: [
              FsaForm.cell('${r.number}', a, align: pw.Alignment.center),
              FsaForm.cell(number(r.massG), a, align: pw.Alignment.center),
              FsaForm.cell(number(r.albumenHeightMm), a,
                  align: pw.Alignment.center),
              FsaForm.cell(number(r.haughUnit, decimals: 0), a,
                  align: pw.Alignment.center),
              FsaForm.cell(r.deviations.join('; '), a),
              FsaForm.cell(r.comments, a),
            ]),
        ],
      );
    }

    // The photograph is its own section under a grey bar, with a caption
    // under the picture, the same as every other report (Ethan, 2026-10-08).
    pw.Widget photo() => trayPhoto == null
        ? pw.SizedBox()
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              FsaForm.heading('PHOTOGRAPHS', a),
              // The tray label, given the room the page has left.
              FsaForm.photoGrid([trayPhoto], a, maxHeight: 96, perRow: 3),
            ],
          );

    final commentLines = FsaForm.wrap(comments, 150);
    final document = pw.Document(
      title: 'Egg Weighing Checklist — $facilityName',
      author: inspectorName,
    );

    document.addPage(
      pw.Page(
        pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22)),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            FsaForm.header(a, FsaDocuments.eggWeighing.onPage(1, pages)),
            FsaForm.heading('FACILITY INFORMATION:', a),
            particulars(),
            FsaForm.heading('CONSIGNMENT DETAILS', a),
            consignment(),
            pw.SizedBox(height: 6),
            table(firstRows),
            if (laterRows.isEmpty) ...[
              FsaForm.heading('COMMENTS AND REMARKS', a),
              FsaForm.ruledLines(commentLines, a),
              pw.SizedBox(height: 10),
              FsaForm.heading('SIGNATURE CONTROLS', a),
              FsaForm.signedBlock(
                a,
                inspectorName: inspectorName,
                authorisedPersonName: authorisedPersonName,
                inspectorSignature: inspectorSignature,
                authorisedPersonSignature: clientSignature,
              ),
              photo(),
            ],
            pw.Spacer(),
            FsaForm.footer(a),
          ],
        ),
      ),
    );

    for (var i = 0; i < laterRows.length; i += _rowsOnLaterPages) {
      final slice = laterRows.skip(i).take(_rowsOnLaterPages).toList();
      final page = 2 + (i ~/ _rowsOnLaterPages);
      final last = i + _rowsOnLaterPages >= laterRows.length;
      document.addPage(
        pw.Page(
          pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22)),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              FsaForm.header(a, FsaDocuments.eggWeighing.onPage(page, pages)),
              pw.SizedBox(height: 6),
              table(slice),
              if (last) ...[
                FsaForm.heading('COMMENTS AND REMARKS', a),
                FsaForm.ruledLines(commentLines, a),
                pw.SizedBox(height: 10),
                FsaForm.heading('SIGNATURE CONTROLS', a),
                FsaForm.signedBlock(
                  a,
                  inspectorName: inspectorName,
                  authorisedPersonName: authorisedPersonName,
                  inspectorSignature: inspectorSignature,
                  authorisedPersonSignature: clientSignature,
                ),
                photo(),
              ],
              pw.Spacer(),
              FsaForm.footer(a),
            ],
          ),
        ),
      );
    }

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await document.save(), flush: true);
    return out;
  }
}
