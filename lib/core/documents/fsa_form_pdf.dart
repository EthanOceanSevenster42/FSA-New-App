import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The furniture every FSA compliance document shares.
///
/// The Agency's checklists are one family of forms — the Egg Weighing
/// Checklist, the labelling and sampling checklists for each commodity, the
/// compositional checklist — and every one of them opens with the same
/// document-control header: the logo, the Act, the regulation the checklist
/// is written against, and the five-row control table (Doc Type, Doc No.,
/// IP, Designed by, Approved by against Issue, Eff. and Rev. dates, the
/// revision and the page number). The office's own SSRS reports render that
/// header from a shared block; this is the handset's copy of it, so ten
/// documents cannot drift into ten slightly different headers.
///
/// Everything here is layout only. What goes *in* the header comes from
/// [FsaDocControl], and each document supplies its own body.
abstract final class FsaForm {
  /// Loaded once per process: the fonts and the letterhead logo are the same
  /// for every document and re-reading them per page is wasted work.
  static FsaFormAssets? _assets;

  /// Supplies the fonts and logo from somewhere other than the asset
  /// bundle — a command-line tool that renders the Agency's forms without a
  /// Flutter engine, for instance. Set once, before anything is drawn.
  static void useAssets(FsaFormAssets assets) => _assets = assets;

  /// Where the fonts and logo come from when nothing has been supplied.
  ///
  /// The app installs a loader that reads the asset bundle; a command-line
  /// tool reads the same files off disk. Keeping it injectable is what lets
  /// this layer — the Agency's forms — stay plain Dart with no Flutter in
  /// it, so the documents can be rendered without an engine.
  static Future<FsaFormAssets> Function()? assetLoader;

  static Future<FsaFormAssets> assets() async {
    final cached = _assets;
    if (cached != null) return cached;
    final loader = assetLoader;
    if (loader == null) {
      throw StateError(
        'No FSA form assets: call FsaForm.useAssets, or install the bundle '
        'loader with installFsaFormAssets().',
      );
    }
    return _assets = await loader();
  }

  static const grey = PdfColors.grey300;

  static pw.TableBorder border() =>
      pw.TableBorder.all(width: 0.6, color: PdfColors.grey800);

  /// A table cell. The checklists are dense, so the default is small and
  /// tight; [size] and [align] cover the exceptions.
  static pw.Widget cell(
    String value,
    FsaFormAssets a, {
    bool isBold = false,
    PdfColor? fill,
    double size = 7,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) =>
      pw.Container(
        color: fill,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
        alignment: align,
        child: pw.Text(value, style: a.text(isBold: isBold, size: size)),
      );

  /// The document-control header, as the Agency's own forms print it: the
  /// Act across the top, then the logo beside the checklist's title and the
  /// five-row control table, and a rule under the lot.
  static pw.Widget header(
    FsaFormAssets a,
    FsaDocControl control, {
    double logoHeight = 52,
  }) {
    pw.Widget c(String v, {bool isBold = false}) =>
        cell(v, a, isBold: isBold, size: 7.5);

    final table = pw.Table(
      border: border(),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.7),
      },
      children: [
        pw.TableRow(children: [
          c('Doc Type', isBold: true),
          c(control.docType),
          c('Issue Date', isBold: true),
          c(control.issueDate),
        ]),
        pw.TableRow(children: [
          c('Doc. No.', isBold: true),
          c(control.docNo),
          c('Eff. Date', isBold: true),
          c(control.effectiveDate),
        ]),
        pw.TableRow(children: [
          c('IP', isBold: true),
          c(control.ip),
          c('Rev. Date', isBold: true),
          c(control.revisionDate),
        ]),
        pw.TableRow(children: [
          c('Designed by', isBold: true),
          c(control.designedBy),
          c('Revision', isBold: true),
          c(control.revision),
        ]),
        pw.TableRow(children: [
          c('Approved by', isBold: true),
          c(control.approvedBy),
          c(''),
          c(''),
        ]),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(control.act, style: a.text(isBold: true, size: 11)),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 190,
              height: logoHeight,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(a.logo, fit: pw.BoxFit.contain),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 3),
                    decoration:
                        pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
                    child: pw.Text(control.title,
                        style: a.text(isBold: true, size: 9)),
                  ),
                  table,
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.9, color: PdfColors.black),
        pw.SizedBox(height: 6),
      ],
    );
  }

  /// The Agency's footer: who generated it, the version, the page and when.
  static pw.Widget pageFooter(FsaFormAssets a, int page, int pages,
      {DateTime? at}) {
    final when = at ?? DateTime.now();
    final hour24 = when.hour;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final stamp = '${when.day.toString().padLeft(2, '0')}/'
        '${when.month.toString().padLeft(2, '0')}/${when.year} '
        '${hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')} '
        '${hour24 < 12 ? 'AM' : 'PM'}';
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Generated by E-Click (Pty) Ltd', style: a.text(size: 8)),
        pw.Text('v1.00', style: a.text(size: 8)),
        pw.Text('$page   of   $pages', style: a.text(size: 8)),
        pw.Text(stamp, style: a.text(size: 8)),
      ],
    );
  }

  /// An underlined section heading — "FACILITY INFORMATION:".
  static pw.Widget heading(String label, FsaFormAssets a) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 7, bottom: 3),
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7.5,
            font: a.bold,
            decoration: pw.TextDecoration.underline,
          ),
        ),
      );

  /// A boxed value, as the paper form's ruled entry boxes.
  static pw.Widget box(String value, FsaFormAssets a, {double width = 190}) =>
      pw.Container(
        width: width,
        height: 13,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        alignment: pw.Alignment.centerLeft,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
        child: pw.Text(value,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: a.text(size: 7.5)),
      );

  /// A caption and its boxed value on one line.
  static pw.Widget field(
    String label,
    String value,
    FsaFormAssets a, {
    double labelWidth = 130,
    double boxWidth = 190,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              width: labelWidth,
              child: pw.Text(label, style: a.text(isBold: true, size: 7)),
            ),
            box(value, a, width: boxWidth),
          ],
        ),
      );

  /// Ruled writing lines, as the paper form's comment blocks.
  static pw.Widget ruledLines(
    List<String> lines,
    FsaFormAssets a, {
    int minimum = 2,
    double height = 14,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var i = 0;
              i < (lines.length > minimum ? lines.length : minimum);
              i++)
            pw.Container(
              height: height,
              alignment: pw.Alignment.bottomLeft,
              padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
              child: pw.Text(i < lines.length ? lines[i] : '',
                  style: a.text(size: 7.5)),
            ),
        ],
      );

  /// A signature line: the image when one was given, the typed name when it
  /// is a name line, empty when the form is to be signed by hand.
  static pw.Widget signatureLine(
    FsaFormAssets a, {
    pw.MemoryImage? signature,
    String name = '',
    double width = 150,
  }) =>
      pw.Container(
        width: width,
        height: 22,
        alignment: pw.Alignment.bottomCenter,
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
        child: signature != null
            ? pw.Image(signature, height: 20, fit: pw.BoxFit.contain)
            : pw.Text(name, style: a.text(size: 7.5)),
      );

  /// The closing block both sides sign: the inspector on the left, the
  /// facility's authorised person on the right, each over a printed name.
  static pw.Widget signedBlock(
    FsaFormAssets a, {
    required String inspectorName,
    required String authorisedPersonName,
    pw.MemoryImage? inspectorSignature,
    pw.MemoryImage? authorisedPersonSignature,
    String leftCaption = 'FOOD SAFETY AGENCY INSPECTOR:',
    String rightCaption = 'FACILITY AUTHORISED PERSON:',
  }) {
    pw.Widget side(String caption, pw.MemoryImage? sig, String name) =>
        pw.Expanded(
          child: pw.Column(children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.SizedBox(
                    width: 150,
                    child:
                        pw.Text(caption, style: a.text(isBold: true, size: 7))),
                signatureLine(a, signature: sig),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.SizedBox(
                    width: 150,
                    child: pw.Text('NAME & SURNAME:',
                        style: a.text(isBold: true, size: 7))),
                signatureLine(a, name: name),
              ],
            ),
          ]),
        );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
            width: 130,
            child: pw.Text('SIGNED:', style: a.text(isBold: true, size: 7))),
        side(leftCaption, inspectorSignature, inspectorName),
        pw.SizedBox(width: 20),
        side(rightCaption, authorisedPersonSignature, authorisedPersonName),
      ],
    );
  }

  /// The Agency's footer line, on every page of every form.
  static pw.Widget footer(FsaFormAssets a) => pw.Center(
        child:
            pw.Text('@ Food Safety Agency (Pty) Ltd', style: a.text(size: 6.5)),
      );

  /// Reads an image from disk, or null when the path is empty or the file
  /// has been cleared by the phone.
  static Future<pw.MemoryImage?> image(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return pw.MemoryImage(await file.readAsBytes());
  }

  /// Greedy word wrap, for the ruled comment blocks.
  static List<String> wrap(String text, int width) {
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

  /// The Agency's file-naming convention, matching what the office sees.
  static String fileName(String site, String kind, DateTime date) {
    final slug = site
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stamp = '${date.year % 100}'.padLeft(2, '0') +
        '${date.month}'.padLeft(2, '0') +
        '${date.day}'.padLeft(2, '0');
    return 'FSA-$slug-$kind-$stamp.pdf';
  }
}

/// The fonts and logo a document is drawn with.
class FsaFormAssets {
  const FsaFormAssets({
    required this.regular,
    required this.bold,
    required this.logo,
    pw.MemoryImage? letterhead,
  }) : _letterhead = letterhead;

  final pw.Font regular;
  final pw.Font bold;
  final pw.MemoryImage logo;

  /// The Request for Invoice is printed on the Agency's letterhead rather
  /// than with the checklists' mark. Falls back to the mark when only one
  /// image is supplied.
  final pw.MemoryImage? _letterhead;

  pw.MemoryImage get letterhead => _letterhead ?? logo;

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold);

  pw.TextStyle text({bool isBold = false, double size = 7.5}) =>
      pw.TextStyle(fontSize: size, font: isBold ? bold : regular);
}

/// What the document-control table says about a form.
///
/// These are the Agency's own values, taken from the printed forms and from
/// the office system's report definitions — not something a record supplies.
class FsaDocControl {
  const FsaDocControl({
    required this.docNo,
    required this.title,
    required this.issueDate,
    required this.effectiveDate,
    required this.revisionDate,
    required this.revision,
    this.act = 'AGRICULTURAL PRODUCT STANDARDS ACT, 119 OF 1990',
    this.docType = 'Checklist',
    this.ip = 'Food Safety Agency (Pty) Ltd',
    this.designedBy = 'N Bergh',
    this.approvedBy = 'Chief Executive Officer',
    this.page = 1,
    this.pages = 1,
  });

  final String docNo;

  /// The line under the Act — the checklist's own name and the regulation
  /// it is written against.
  final String title;
  final String issueDate;
  final String effectiveDate;
  final String revisionDate;
  final String revision;
  final String act;
  final String docType;
  final String ip;
  final String designedBy;
  final String approvedBy;
  final int page;
  final int pages;

  FsaDocControl onPage(int page, int pages) => FsaDocControl(
        docNo: docNo,
        title: title,
        issueDate: issueDate,
        effectiveDate: effectiveDate,
        revisionDate: revisionDate,
        revision: revision,
        act: act,
        docType: docType,
        ip: ip,
        designedBy: designedBy,
        approvedBy: approvedBy,
        page: page,
        pages: pages,
      );
}
