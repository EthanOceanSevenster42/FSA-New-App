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

    /// The regulation shown under NATURE OF INSPECTION (e.g. "R.345 of 20
    /// March 2020"). Empty falls back to nothing.
    String regulation = '',


    /// Photographs of the non-conformity, shown under their own section at
    /// the end, the same as the seizure and the checklists
    /// (Ethan, 2026-10-08).
    ///
    /// Required, and deliberately so: it was optional, and the egg rejection
    /// simply never passed it — the sheet read "underweight — 6 of 12 eggs"
    /// with not one of the six photographs on it, and nothing anywhere said
    /// so. A caller with nothing to show now has to say `const []` and mean
    /// it, rather than lose the evidence by omission (Ethan, 2026-10-08).
    required List<String> photoPaths,
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.signature(inspectorSignaturePath);
    final authorisedSignature =
        await FsaForm.signature(authorisedPersonSignaturePath);
    final photos = <pw.MemoryImage>[
      for (final path in photoPaths)
        if (await FsaForm.image(path) case final image?) image,
    ];
    final doc = pw.Document();

    final visit = fsaDateLong(dateOfVisit);

    // Portrait: two columns inside 551pt, so a label and its box together
    // must stay under half the width or the box runs off the sheet.
    // No field is left blank — an empty value prints "N/A" (Ethan, 2026-10-08).
    String na(String v) => v.trim().isEmpty ? 'N/A' : v;
    pw.Widget pair(String label, String value) =>
        FsaForm.field(label, na(value), a, labelWidth: 110, boxWidth: 150);
    pw.Widget wide(String label, String value) =>
        FsaForm.field(label, na(value), a, labelWidth: 110, boxWidth: 410);

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
              body(na(deviations[i].product)),
              body(na(deviations[i].nature)),
              body(na(deviations[i].regulation)),
            ]),
          // A direction with nothing on it is not served, but the sheet must
          // still rule a row rather than collapse the table.
          if (deviations.isEmpty)
            pw.TableRow(
                children: [body('N/A'), body('N/A'), body('N/A'), body('N/A')]),
        ],
      );
    }

    // A section travels whole: its grey bar and the rows under it stay on one
    // page. MultiPage breaks between its top-level children and pw.Column is
    // a SpanningWidget, so laying a section out as loose children let a break
    // fall inside it — which stranded "Batch Number" alone at the top of the
    // next page, away from the rest of PRODUCT DETAILS (Ethan, 2026-10-08).
    pw.Widget section(List<pw.Widget> children) => pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
        build: (context) => [
          FsaForm.header(a, control),
          section([
            FsaForm.heading(
                'DETAILS: PRODUCER/IMPORTER/BUTCHER/RETAILER FACILITY', a),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pair('Facility', facilityName),
                      pair('Owner/Manager/Representative',
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
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(
                    child: pair('Latest Reference No.', latestReference)),
                pw.Expanded(
                    child: pair('Original Reference No.', originalReference)),
              ],
            ),
          ]),
          // The commodity and the regulation read as one sentence rather than
          // as two stacked lines (Ethan, 2026-10-08).
          section([
            FsaForm.heading('NATURE OF INSPECTION', a),
            pw.Text(
              regulation.trim().isEmpty
                  ? natureOfInspection
                  : '$natureOfInspection: As per the Regulation No. '
                      '${regulation.trim()}',
              style: a.text(size: 8),
            ),
          ]),
          // No FINDINGS section: nothing on the handset captures one, so it
          // printed an empty box on every real rejection. The deviations
          // table below is what carries each contravention, with the
          // regulation it offends (Ethan, 2026-10-08).
          if (subjectFields.isNotEmpty)
            section([
              FsaForm.heading('PRODUCT DETAILS', a),
              for (final f in subjectFields) wide(f.label, f.value),
            ]),
          // The deviations keep their heading, but the table itself is left
          // free to span: a direction with many non-conformities must be
          // allowed to run onto the next page rather than be forced onto one.
          FsaForm.heading('DEVIATIONS (NON-CONFORMITIES)', a),
          deviationTable(),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 3),
            child: pw.Row(children: [
              pw.Text(
                'Rectify the non-conformity as mentioned below before or on ',
                style: a.text(size: 7.5),
              ),
              FsaForm.box(na(correctByDate), a, width: 90),
            ]),
          ),
          section([
            FsaForm.heading('COMMENTS AND REMARKS', a),
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
          ]),
          // Generic signature block, the same across every report
          // (Ethan, 2026-10-08).
          section([
            pw.SizedBox(height: 18),
            FsaForm.heading('SIGNATURE CONTROLS', a),
            FsaForm.signedBlock(
              a,
              inspectorName: inspectorName,
              authorisedPersonName: authorisedPersonName,
              inspectorSignature: inspectorSignature,
              authorisedPersonSignature: authorisedSignature,
            ),
          ]),
          // Photographs close the sheet, framed and numbered, the same as
          // the seizure and the checklists (Ethan, 2026-10-08).
          //
          // One child, not a spread: MultiPage breaks between its top-level
          // children, so spreading the bar and the pictures left the bar
          // stranded at the foot of one page and the pictures alone on the
          // next.
          if (photos.isNotEmpty)
            // pw.Inseparable keeps the bar and the pictures on one page.
            // pw.Column is a SpanningWidget, so MultiPage will split it and
            // strand the bar at the foot of one page with the pictures alone
            // on the next; neither a bare Container nor a Padding stops that,
            // because MultiPage asks the child itself whether it may span
            // (Ethan, 2026-10-08).
            pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  FsaForm.heading('PHOTOGRAPHS', a),
                  // Sized to the room the page has, not a fixed thumbnail.
                  FsaForm.photoGrid(photos.toList(), a),
                ],
              ),
            ),
        ],
      ),
    );

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    return out;
  }
}
