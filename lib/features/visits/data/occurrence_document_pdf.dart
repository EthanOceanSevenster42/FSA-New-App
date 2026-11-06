import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_documents.dart';
import '../../../core/documents/fsa_form_pdf.dart';

/// FSA's Occurrence Document (SOP-APS-009, revision V3), filled in from the
/// handset instead of by hand.
///
/// Laid out as the paper form the Agency scans today: the document-control
/// header with the logo, the "OCCURRENCE DOCUMENT" bar, the particulars
/// table, the findings on ruled lines, and the two name-and-signature rows.
/// Photographs taken at the visit follow as numbered pages, so the office
/// receives one PDF in place of the scan plus loose photos.
abstract final class OccurrenceDocumentPdf {
  static const docNo = 'SOP-APS-009';
  // The revision is carried by FsaDocuments.occurrence, which is what the
  // header prints; a second copy here only drifts (Ethan, 2026-10-08).
  // Reworded 2026-10-20 (Neo Noe): the procedure read as though an
  // occurrence document were only ever written when entry was refused.
  // Refusal of entry is one occurrence among others — it keeps its place as
  // the example, but the document is for any occurrence at the premises
  // that has to be put on record.
  static const procedure =
      'This document will serve as an occurrence document. The document needs '
      'to be completed as and when any occurrence or incident arises at an '
      'abattoir, production plant, processing facility, repacking plant, '
      'importer or retailer that must be placed on record — including, '
      'but not limited to, where the assignee is refused entry/access. The '
      'description of events needs to be captured in full and as it '
      'happened.';

  static const _photosPerPage = 2;
  static const _photosPerRow = 4;

  /// Lines of findings that fit on the first page, before the signatures.
  // Fewer than before the letterhead (Ethan, 2026-10-04): the logo and
  // address above and the band below take about four ruled lines.
  static const _linesOnFirstPage = 12;
  static const _linesOnLaterPages = 30;
  static const _charsPerLine = 92;

  static Future<File> write({
    required File out,
    required String facilityName,
    required String facilityAddress,
    required String date,
    required String timeOfVisit,
    required String registrationCode,
    required String inspectorName,
    required String description,
    required List<String> photoPaths,
    String ownerManagerDetails = '',
    String telephone = '',
    String email = '',
    String managerName = '',
    String inspectorSignaturePath = '',
    String managerSignaturePath = '',
  }) async {
    final assets = await FsaForm.assets();
    final regular = assets.regular;
    final bold = assets.bold;

    Future<pw.MemoryImage?> image(String path) async {
      final file = File(path);
      if (path.isEmpty || !file.existsSync()) return null;
      return pw.MemoryImage(await file.readAsBytes());
    }

    final inspectorSignature = await image(inspectorSignaturePath);
    final managerSignature = await image(managerSignaturePath);

    final lines = _wrap(description, _charsPerLine);
    final existingPhotos =
        photoPaths.where((p) => File(p).existsSync()).toList();
    // The whole document on one page when it fits — the form, the findings,
    // a strip of photographs and the signatures, as the paper form is one
    // sheet. Each row of thumbnails costs about six ruled lines; when the
    // findings will not fit alongside, the document falls back to the
    // longer form: findings pages, then photographs two to a page.
    //
    // The old guard was `linesWithPhotos >= 6`, which no photographed visit
    // could ever satisfy — twelve lines less the seven a row costs leaves
    // five — so a document with pictures always took the long form. One row
    // of thumbnails fits beside short findings (Ethan, 2026-10-08).
    final photoRows = (existingPhotos.length / _photosPerRow).ceil();
    final linesWithPhotos = _linesOnFirstPage - photoRows * 6;
    final onePage = photoRows <= 1 && lines.length <= linesWithPhotos;
    final firstPageBudget = onePage ? linesWithPhotos : _linesOnFirstPage;
    final laterLines = lines.skip(firstPageBudget).toList();
    final textPages = 1 +
        (laterLines.isEmpty
            ? 0
            : (laterLines.length / _linesOnLaterPages).ceil());
    final photoPages =
        onePage ? 0 : (existingPhotos.length / _photosPerPage).ceil();
    final totalPages = textPages + photoPages;

    final document = pw.Document(
      title: 'Occurrence Document — $facilityName',
      author: inspectorName,
    );

    pw.TextStyle small({bool isBold = false}) =>
        pw.TextStyle(fontSize: 7.5, font: isBold ? bold : regular);
    pw.TextStyle body({bool isBold = false, double size = 9.5}) =>
        pw.TextStyle(fontSize: size, font: isBold ? bold : regular);

    pw.Widget cell(String text,
            {bool isBold = false,
            PdfColor? fill,
            double size = 7.5,
            pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          color: fill,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
          alignment: align,
          child: pw.Text(text,
              style:
                  pw.TextStyle(fontSize: size, font: isBold ? bold : regular)),
        );

    const grey = PdfColors.grey300;
    final border = pw.TableBorder.all(width: 0.6, color: PdfColors.grey700);

    // The same document-control header as every other report (Ethan,
    // 2026-10-08): the Act line, one title bar, merged "Issue / Eff. Date"
    // and no page row. It used to build its own table, which printed
    // "OCCURRENCE DOCUMENT" twice on every page — once in the control block
    // and again in a title bar underneath.
    pw.Widget header() => FsaForm.header(assets, FsaDocuments.occurrence);

    /// The form's standing note on when an occurrence document is written.
    pw.Widget procedureNote() => pw.Table(
          border: border,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(4.9),
          },
          children: [
            pw.TableRow(children: [
              cell('Procedure', isBold: true, fill: grey),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(procedure,
                    style: pw.TextStyle(
                        fontSize: 6.8, font: regular, lineSpacing: 1)),
              ),
            ]),
          ],
        );

    pw.Widget particulars() {
      // Set at the same size as the tables on the other reports, which also
      // buys the room the signature block needs to close the sheet on one
      // page (Ethan, 2026-10-08).
      pw.TableRow row(String label, String value) => pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              cell(label, isBold: true, size: 7.5),
              cell(value.isEmpty ? '' : value, size: 8),
            ],
          );
      return pw.Table(
        border: border,
        columnWidths: const {
          0: pw.FlexColumnWidth(1.55),
          1: pw.FlexColumnWidth(3.45),
        },
        children: [
          row('Abattoir/Production Plant/Processing/\nRepacking/Plant/Importer/Retailer',
              facilityName),
          row('Owner/Manager/Representative Details', ownerManagerDetails),
          row('Registration Code (if applicable)', registrationCode),
          row('Physical Address', facilityAddress),
          row('Telephone Number', telephone),
          row('E-Mail Address', email),
          row('Date(s) of Visit', date),
          row('Time of Visit', timeOfVisit),
        ],
      );
    }

    // The ruled findings lines and the signature rows are drawn by the shared
    // furniture now (FsaForm.signedBlock), so the hand-rolled versions that
    // lived here are gone (Ethan, 2026-10-08).

    Future<pw.Widget> photoStrip() async {
      final rows = <pw.Widget>[];
      for (var r = 0; r < existingPhotos.length; r += _photosPerRow) {
        final batch = existingPhotos.skip(r).take(_photosPerRow).toList();
        final cells = <pw.Widget>[];
        for (var i = 0; i < batch.length; i++) {
          final n = r + i + 1;
          final photo = pw.MemoryImage(await File(batch[i]).readAsBytes());
          cells.add(pw.Expanded(
            child: pw.Container(
              margin: pw.EdgeInsets.only(right: i == batch.length - 1 ? 0 : 6),
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.5, color: PdfColors.grey600)),
              child: pw.Column(children: [
                pw.SizedBox(
                    height: 72,
                    child: pw.Center(
                        child: pw.Image(photo, fit: pw.BoxFit.contain))),
                pw.SizedBox(height: 2),
                pw.Text('Photograph $n', style: small(isBold: true)),
              ]),
            ),
          ));
        }
        for (var i = batch.length; i < _photosPerRow; i++) {
          cells.add(pw.Expanded(child: pw.SizedBox()));
        }
        rows.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(children: cells),
        ));
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          FsaForm.heading('PHOTOGRAPHS', assets, compact: true),
          ...rows,
        ],
      );
    }

    final strip =
        onePage && existingPhotos.isNotEmpty ? await photoStrip() : null;

    // The "© Food Safety Agency (Pty) Ltd" caption was removed at Ethan's
    // request (2026-10-08); kept as an empty widget so callers are unchanged.
    pw.Widget footer() => pw.SizedBox();

    // Same closing block as every other report (Ethan, 2026-10-08).
    pw.Widget signatures() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // No extra gap: the heading already carries its own top margin.
            FsaForm.heading('SIGNATURE CONTROLS', assets, compact: true),
            FsaForm.signedBlock(
              assets,
              inspectorName: inspectorName,
              authorisedPersonName: managerName,
              inspectorSignature: inspectorSignature,
              authorisedPersonSignature: managerSignature,
              rightCaption: 'MANAGER/OWNER/REPRESENTATIVE:',
            ),
          ],
        );

    // One flowing document: the findings run on as far as they need and the
    // signatures close them. A fixed-height page dropped any block that did
    // not fit, which silently lost the findings and the signatures
    // (Ethan, 2026-10-08).
    // Four ruled lines when the findings are short, as on the other reports:
    // twelve pushed the signatures onto a second page, which then repeated
    // the whole control block for nothing (Ethan, 2026-10-08).
    const minimumRuledLines = 4;
    final ruledCount =
        lines.length < minimumRuledLines ? minimumRuledLines : lines.length;
    document.addPage(
      pw.MultiPage(
        pageTheme: FsaForm.letterhead(assets, PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
        header: (context) => header(),
        build: (context) => [
          procedureNote(),
          // Compact bars: the occurrence document is one sheet, and with
          // photographs on it the roomy spacing tipped it onto a second
          // page (Ethan, 2026-10-08).
          FsaForm.heading('DETAILS', assets, compact: true),
          particulars(),
          FsaForm.heading('FINDINGS', assets, compact: true),
          // One widget per ruled line so the page can break between them.
          for (var i = 0; i < ruledCount; i++)
            pw.Container(
              height: 14,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom:
                        pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
              ),
              alignment: pw.Alignment.bottomLeft,
              padding: const pw.EdgeInsets.only(bottom: 1.5),
              child: pw.Text(i < lines.length ? lines[i] : '',
                  style: const pw.TextStyle(fontSize: 9)),
            ),
          // Signatures then photographs, the order every other report uses
          // (Ethan, 2026-10-08).
          signatures(),
          if (strip != null) strip,
        ],
      ),
    );

    // Photographs, two to a page, each in its own captioned frame — only
    // when the document did not fit on one page.
    for (var p = onePage ? existingPhotos.length : 0;
        p < existingPhotos.length;
        p += _photosPerPage) {
      final batch = existingPhotos.skip(p).take(_photosPerPage).toList();
      final pageNo = textPages + 1 + p ~/ _photosPerPage;
      final frames = <pw.Widget>[];
      for (var i = 0; i < batch.length; i++) {
        final n = p + i + 1;
        final photo = pw.MemoryImage(await File(batch[i]).readAsBytes());
        frames.add(
          pw.Expanded(
            child: pw.Container(
              margin:
                  pw.EdgeInsets.only(bottom: i == batch.length - 1 ? 0 : 14),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.6, color: PdfColors.grey600)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(photo, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Photograph $n', style: small(isBold: true)),
                ],
              ),
            ),
          ),
        );
      }
      // A lone photograph on the last page keeps to the same frame size.
      if (batch.length < _photosPerPage)
        frames.add(pw.Expanded(child: pw.SizedBox()));
      document.addPage(
        pw.Page(
          pageTheme: FsaForm.letterhead(assets, PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('OCCURRENCE DOCUMENT — $facilityName — photographs',
                      style: body(isBold: true, size: 9.5)),
                  pw.Text('Page $pageNo of $totalPages', style: small()),
                ],
              ),
              pw.SizedBox(height: 8),
              ...frames,
              footer(),
            ],
          ),
        ),
      );
    }

    await out.writeAsBytes(await document.save(), flush: true);
    return out;
  }

  /// Breaks the findings into lines that fit the ruled area, keeping the
  /// inspector's own paragraph breaks.
  static List<String> _wrap(String text, int width) {
    final out = <String>[];
    for (final paragraph in text.replaceAll('\r', '').split('\n')) {
      var line = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        if (line.isEmpty) {
          line = word;
        } else if ((line.length + 1 + word.length) <= width) {
          line = '$line $word';
        } else {
          out.add(line);
          line = word;
        }
      }
      out.add(line);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }
}
