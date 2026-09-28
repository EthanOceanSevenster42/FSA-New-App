import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/documents/fsa_form_pdf.dart';

/// FSA's Occurrence Document (SOP-APS-009, revision V2), filled in from the
/// handset instead of by hand.
///
/// Laid out as the paper form the Agency scans today: the document-control
/// header with the logo, the "OCCURRENCE DOCUMENT" bar, the particulars
/// table, the findings on ruled lines, and the two name-and-signature rows.
/// Photographs taken at the visit follow as numbered pages, so the office
/// receives one PDF in place of the scan plus loose photos.
abstract final class OccurrenceDocumentPdf {
  static const docNo = 'SOP-APS-009';
  static const revision = 'V2';
  static const procedure =
      'This document will serve as an occurrence document. The document would '
      'need to be completed as and when an abattoir, production plant, '
      'processing facility, repacking plant, importer or retailer refused the '
      'assignee entry/access. The description of events needs to be captured '
      'in full and as it happened.';

  static const _photosPerPage = 2;
  static const _photosPerRow = 4;

  /// Lines of findings that fit on the first page, before the signatures.
  static const _linesOnFirstPage = 16;
  static const _linesOnLaterPages = 34;
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
    final logo = assets.logo;
    final theme = assets.theme;

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
    // sheet. Each row of thumbnails costs about seven ruled lines; when the
    // findings will not fit alongside, the document falls back to the
    // longer form: findings pages, then photographs two to a page.
    final photoRows = (existingPhotos.length / _photosPerRow).ceil();
    final linesWithPhotos = _linesOnFirstPage - photoRows * 7;
    final onePage = lines.length <= linesWithPhotos && linesWithPhotos >= 6;
    final firstPageBudget = onePage ? linesWithPhotos : _linesOnFirstPage;
    final firstPageLines = lines.take(firstPageBudget).toList();
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
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          alignment: align,
          child: pw.Text(text,
              style:
                  pw.TextStyle(fontSize: size, font: isBold ? bold : regular)),
        );

    const grey = PdfColors.grey300;
    final border = pw.TableBorder.all(width: 0.6, color: PdfColors.grey700);

    pw.Widget header(int page) {
      final control = pw.Table(
        border: border,
        columnWidths: const {
          0: pw.FlexColumnWidth(1.1),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FlexColumnWidth(1.1),
          3: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(children: [
            cell('Doc Type', isBold: true, fill: grey),
            cell('Document'),
            cell('Issue Date', isBold: true, fill: grey),
            cell('1 August 2022'),
          ]),
          pw.TableRow(children: [
            cell('Doc No.', isBold: true, fill: grey),
            cell(docNo),
            cell('Eff. Date', isBold: true, fill: grey),
            cell('1 August 2022'),
          ]),
          pw.TableRow(children: [
            cell('IP', isBold: true, fill: grey),
            cell('Food Safety Agency (Pty) Ltd'),
            cell('Rev. Date', isBold: true, fill: grey),
            cell('31 July 2025'),
          ]),
          pw.TableRow(children: [
            cell('Designed by', isBold: true, fill: grey),
            cell('N Bergh'),
            cell('Revision', isBold: true, fill: grey),
            cell(revision),
          ]),
          pw.TableRow(children: [
            cell('Approved by', isBold: true, fill: grey),
            cell('Chief Executive Officer'),
            cell('Page', isBold: true, fill: grey),
            cell('Page $page of $totalPages'),
          ]),
        ],
      );
      return pw.Table(
        border: border,
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(3.6),
        },
        children: [
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Container(
                height: 118,
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.all(8),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    alignment: pw.Alignment.center,
                    child: pw.Text('OCCURRENCE DOCUMENT',
                        style: body(isBold: true, size: 11)),
                  ),
                  control,
                  pw.Table(
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
                                  fontSize: 6.8,
                                  font: regular,
                                  lineSpacing: 1)),
                        ),
                      ]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    pw.Widget titleBar() => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
          alignment: pw.Alignment.center,
          child: pw.Text('OCCURRENCE DOCUMENT',
              style: body(isBold: true, size: 11)),
        );

    pw.Widget particulars() {
      pw.TableRow row(String label, String value) => pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              cell(label, isBold: true, size: 8),
              cell(value.isEmpty ? '' : value, size: 9.5),
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

    pw.Widget ruledLines(List<String> text, int count) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++)
              pw.Container(
                height: 17,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom:
                          pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
                ),
                alignment: pw.Alignment.bottomLeft,
                padding: const pw.EdgeInsets.only(bottom: 1.5),
                child: pw.Text(i < text.length ? text[i] : '',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
          ],
        );

    pw.Widget signatureRow(
            String nameLabel, String name, pw.MemoryImage? sig) =>
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: 22,
                    alignment: pw.Alignment.bottomLeft,
                    padding: const pw.EdgeInsets.only(left: 16, bottom: 2),
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
                    child: pw.Text(name.toUpperCase(),
                        style: const pw.TextStyle(fontSize: 9.5)),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                      child: pw.Text(nameLabel, style: small(isBold: true))),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    height: 34,
                    alignment: pw.Alignment.bottomCenter,
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
                    child: sig == null
                        ? pw.SizedBox()
                        : pw.Image(sig, height: 32, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                      child: pw.Text('SIGNATURE', style: small(isBold: true))),
                ],
              ),
            ),
          ],
        );

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
                    height: 88,
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
          pw.SizedBox(height: 6),
          pw.Text('PHOTOGRAPHS:', style: body(isBold: true, size: 9.5)),
          ...rows,
        ],
      );
    }

    final strip =
        onePage && existingPhotos.isNotEmpty ? await photoStrip() : null;

    pw.Widget footer() => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          alignment: pw.Alignment.center,
          child: pw.Text('© Food Safety Agency (Pty) Ltd', style: small()),
        );

    pw.Widget signatures() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.SizedBox(height: 14),
            signatureRow(
                'AUDITOR/INSPECTOR NAME', inspectorName, inspectorSignature),
            pw.SizedBox(height: 16),
            signatureRow('MANAGER/OWNER/REPRESENTATIVE NAME', managerName,
                managerSignature),
            footer(),
          ],
        );

    // Page 1: header, particulars, the first block of findings, and the
    // signatures when everything fits.
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 26, 34, 24),
        theme: theme,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header(1),
            titleBar(),
            particulars(),
            pw.SizedBox(height: 10),
            pw.Text('FINDINGS:', style: body(isBold: true, size: 9.5)),
            pw.SizedBox(height: 2),
            ruledLines(firstPageLines, firstPageBudget),
            if (strip != null) strip,
            if (laterLines.isEmpty) signatures() else footer(),
          ],
        ),
      ),
    );

    // Continuation pages for long findings; the signatures close the last.
    for (var p = 0; p < laterLines.length; p += _linesOnLaterPages) {
      final chunk = laterLines.skip(p).take(_linesOnLaterPages).toList();
      final last = p + _linesOnLaterPages >= laterLines.length;
      final pageNo = 2 + p ~/ _linesOnLaterPages;
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 26, 34, 24),
          theme: theme,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              header(pageNo),
              titleBar(),
              pw.Text('FINDINGS (continued):',
                  style: body(isBold: true, size: 9.5)),
              pw.SizedBox(height: 2),
              ruledLines(
                  chunk, last ? _linesOnLaterPages - 8 : _linesOnLaterPages),
              if (last) signatures() else footer(),
            ],
          ),
        ),
      );
    }

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
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 26, 34, 24),
          theme: theme,
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
