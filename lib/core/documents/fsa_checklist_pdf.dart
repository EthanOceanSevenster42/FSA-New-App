import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fsa_form_pdf.dart';

/// What the DEVIATION column says about a requirement.
///
/// The Agency's sheets do not tick: they print a word. A requirement whose
/// block was not present at the premises reads `N/A`, one that was checked
/// and met reads `NO`, and one that was checked and failed reads `YES`.
enum FsaDeviation {
  notApplicable('N/A'),
  no('NO'),
  yes('YES');

  const FsaDeviation(this.label);

  final String label;
}

/// One line of a marking/labelling or sampling checklist.
class FsaChecklistRow {
  const FsaChecklistRow({
    required this.requirement,
    this.regulation = '',
    this.standard = '-',
    this.deviation = FsaDeviation.notApplicable,
    this.value,
  });

  /// The requirement as the regulation words it.
  final String requirement;

  /// The regulation it comes from — "[Reg. 7(1)(a) & 8]".
  final String regulation;

  /// The minimum lettering height where one is prescribed, "-" otherwise.
  final String standard;

  final FsaDeviation deviation;

  /// A detail line rather than a requirement: the sampling blocks record
  /// what was taken, not whether a regulation was met, so the row prints
  /// this in place of the deviation word.
  final String? value;
}

/// A block of requirements under its own heading, which the sheet prints as
/// a table of its own — "MARKING REQUIREMENTS", "SCALE LABEL REQUIREMENTS".
class FsaChecklistSection {
  const FsaChecklistSection({required this.title, required this.rows});

  final String title;
  final List<FsaChecklistRow> rows;
}

/// A caption and its value, for the particulars at the top of the sheet.
typedef FsaField = ({String label, String value});

/// The Agency's container and labelling verification checklists.
///
/// Laid out as the office system prints them: the document-control header,
/// the inspection's particulars in two columns, then the requirement blocks
/// in two columns of tables — each block its own table headed
/// `REGULATIONS | STD | DEVIATION`, every requirement answered `N/A`, `NO`
/// or `YES`. The comments, remarks and the two signatures follow, and the
/// product photographs come after the signatures (Ethan, 2026-10-04) —
/// the sheet signs off under its remarks, as the office's copies do, and
/// the pictures sit below it.
///
/// Six of the Agency's forms are this sheet with different requirements in
/// it, so they share this one builder and supply their own control block,
/// particulars and sections.
abstract final class FsaChecklistPdf {
  static Future<File> write({
    required File out,
    required FsaDocControl control,
    required String facilityName,
    required List<FsaField> leftFields,
    required List<FsaField> rightFields,
    required List<FsaChecklistSection> sections,
    required String inspectorName,
    String authorisedPersonName = '',
    String comments = '',
    String remarks = '',
    List<String> photoPaths = const [],
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
    String? documentTitle,
    DateTime? generatedAt,
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.signature(inspectorSignaturePath);
    final clientSignature = await FsaForm.signature(authorisedPersonSignaturePath);
    final photos = <pw.MemoryImage>[];
    for (final path in photoPaths) {
      final image = await FsaForm.image(path);
      if (image != null) photos.add(image);
    }

    // ---------------------------------------------------------- paging
    //
    // A landscape sheet holds only so many requirement rows, and a long
    // checklist — the egg labelling one runs to twenty-seven — needs more
    // than one. The blocks are measured, split where a single block is
    // taller than a column, and dealt into two columns a page at a time, so
    // nothing is silently dropped off the bottom. The closing block
    // (comments, remarks, signatures, photographs) takes the last page, its
    // own if what is left will not hold it.
    // On the letterhead (Ethan, 2026-10-04) the page keeps room for the
    // logo and address above and the band below, so the body is what is
    // left inside those margins, not the bare page's.
    const margin = pw.EdgeInsets.fromLTRB(30, 22, 30, 20);
    final pageTheme =
        FsaForm.letterhead(a, PdfPageFormat.a4.landscape, margin: margin);
    final grown = FsaForm.letterheadMargin(a, PdfPageFormat.a4.landscape,
        margin: margin);
    final bodyHeight = _bodyHeightFor(grown);
    final batches = _packPages(
      sections,
      bodyHeight: bodyHeight,
      // + 32 reserves the "INSPECTION & FACILITY DETAILS" section bar above
      // the particulars (Ethan, 2026-10-08).
      particularsHeight: (leftFields.length > rightFields.length
                  ? leftFields.length
                  : rightFields.length) *
              _fieldHeight +
          42,
      closingHeight: _closingHeight(photos.isNotEmpty),
    );
    final pages = batches.length;

    // ------------------------------------------------------- particulars
    pw.Widget fieldRow(FsaField f) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: 150,
                child: pw.Text(f.label, style: a.text(isBold: true, size: 8)),
              ),
              FsaForm.box(f.value, a, width: 200),
            ],
          ),
        );

    pw.Widget particulars() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [for (final f in leftFields) fieldRow(f)],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [for (final f in rightFields) fieldRow(f)],
              ),
            ),
          ],
        );

    // ---------------------------------------------------------- the table
    // Each section carries its own heading bar above its table so it reads on
    // its own (Ethan, 2026-10-08), with the section name in the bar and a
    // generic "REQUIREMENT" column header.
    pw.Widget sectionTable(FsaChecklistSection section) {
      // A section whose rows all carry a value — sample details and the like —
      // has no regulation or standard to show, so those two empty columns are
      // dropped (Ethan, 2026-10-08).
      final valueOnly =
          section.rows.isNotEmpty && section.rows.every((r) => r.value != null);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          FsaForm.heading(section.title, a),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Table(
              border: FsaForm.border(),
              columnWidths: valueOnly
                  ? const {
                      0: pw.FlexColumnWidth(3.6),
                      1: pw.FlexColumnWidth(3.5),
                    }
                  : const {
                      0: pw.FlexColumnWidth(3.6),
                      1: pw.FlexColumnWidth(1.7),
                      2: pw.FlexColumnWidth(0.8),
                      3: pw.FlexColumnWidth(1.0),
                    },
              children: [
                pw.TableRow(children: [
                  FsaForm.cell('REQUIREMENT', a, isBold: true, size: 7.5),
                  if (!valueOnly) ...[
                    FsaForm.cell('REGULATIONS', a, isBold: true, size: 7.5),
                    FsaForm.cell('STD', a, isBold: true, size: 7.5),
                  ],
                  // A value column is what was recorded, not a finding:
                  // "Testing for … DEVIATION: Fat, Protein" read as though
                  // the tests were the fault (Ethan, 2026-10-08).
                  FsaForm.cell(valueOnly ? 'DETAIL' : 'DEVIATION', a,
                      isBold: true, size: 7.5),
                ]),
                for (final r in section.rows)
                  pw.TableRow(children: [
                    FsaForm.cell(r.requirement, a, size: 7.5),
                    if (!valueOnly) ...[
                      FsaForm.cell(r.value == null ? r.regulation : '', a,
                          size: 7.5),
                      FsaForm.cell(
                          r.value == null ? r.standard : '', a, size: 7.5),
                    ],
                    FsaForm.cell(r.value ?? r.deviation.label, a, size: 7.5),
                  ]),
              ],
            ),
          ),
        ],
      );
    }

    // The sheet runs the blocks down two columns, as the Agency's own does.
    pw.Widget checklist(_Batch batch) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [for (final s in batch.left) sectionTable(s)],
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [for (final s in batch.right) sectionTable(s)],
              ),
            ),
          ],
        );

    // ------------------------------------------------- comments and signing
    pw.Widget labelledBox(String label, String value, {double height = 26}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // The caption keeps its fixed height: it is one short line, and
              // stretching it needs a bounded height the column cannot give,
              // which collapsed the whole block.
              pw.Container(
                width: 140,
                height: height,
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: pw.BoxDecoration(
                    border:
                        label == 'Remarks' ? pw.Border.all(width: 0.7) : null),
                child: pw.Text(label, style: a.text(isBold: true, size: 8)),
              ),
              pw.Expanded(
                child: pw.Container(
                  // Min-height, not fixed. Three numbered comments need more
                  // than 26pt, and the box did not grow: the third line
                  // printed across the border and was cut off (Kabelo,
                  // 2026-10-23). Same fix as FsaForm.ruledLines.
                  constraints: pw.BoxConstraints(minHeight: height),
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration:
                      pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
                  child: pw.Text(value, style: a.text(size: 8)),
                ),
              ),
            ],
          ),
        );

    // Grading samples five carcasses, one photograph each, so a grading
    // sheet carries up to five. It used to show only three. The sheet is
    // landscape and holds five across when they are sized down past three;
    // they stay one row, so the closing block's reserved height is unchanged
    // (Ethan, 2026-10-05).
    final strip = photos.take(5).toList();
    final roomy = strip.length <= 3;
    // Sized so the closing block still clears the page with the new section
    // bar and captions above and below it. The sheet uses pw.Page, which
    // DROPS a block that does not fit rather than clipping it, so this is
    // deliberately conservative (Ethan, 2026-10-08).
    final cellWidth = roomy ? 96.0 : 88.0;
    final cellHeight = roomy ? 74.0 : 72.0;
    // The photographs are their own section, under a grey bar like every
    // other part of the sheet, and each one is numbered so a finding can be
    // referred to by picture (Ethan, 2026-10-08). The cells were sized down
    // to pay for the bar and the captions.
    pw.Widget photoStrip() => photos.isEmpty
        ? pw.SizedBox()
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              FsaForm.heading('PHOTOGRAPHS', a),
              // Sized to the room left on the closing page: these share
              // it with the comments and the signatures, so the ceiling
              // is lower than a sheet of their own (Ethan, 2026-10-08).
              // One row, however many there are: the pictures share this
              // page with the comments and the signatures, and a second
              // row costs more height than it gives back — five across
              // is both larger and shorter than three-plus-two
              // (Ethan, 2026-10-08).
              FsaForm.photoGrid(strip, a,
                  maxHeight: 96, perRow: strip.length),
            ],
          );

    pw.Widget nameBox(String value) => pw.Container(
          width: 150,
          height: 42,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
          child: pw.Text(value, style: a.text(size: 9)),
        );

    pw.Widget signatureCell(pw.MemoryImage? signature) => pw.Container(
          width: 150,
          height: 60,
          alignment: pw.Alignment.center,
          child: signature == null
              ? pw.SizedBox()
              : pw.Image(signature, height: 58, fit: pw.BoxFit.contain),
        );

    pw.Widget caption(String text) => pw.SizedBox(
          width: 96,
          child: pw.Text(text, style: a.text(isBold: true, size: 8)),
        );

    // Generic signature block, the same across every report
    // (Ethan, 2026-10-08).
    pw.Widget signatures() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            FsaForm.heading('SIGNATURE CONTROLS', a),
            FsaForm.signedBlock(
              a,
              inspectorName: inspectorName,
              authorisedPersonName: authorisedPersonName,
              inspectorSignature: inspectorSignature,
              authorisedPersonSignature: clientSignature,
            ),
          ],
        );

    final document = pw.Document(
      title: '${documentTitle ?? control.docNo} — $facilityName',
      author: inspectorName,
    );

    // No Spacer between the body and the foot: it made the page drop any
    // block that did not fit, which silently lost the signatures and the
    // photographs (Ethan, 2026-10-08).
    pw.Page page(int number, pw.Widget body) => pw.Page(
          pageTheme: pageTheme,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              FsaForm.header(a, control.onPage(number, pages)),
              body,
              FsaForm.pageFooter(a, number, pages, at: generatedAt),
            ],
          ),
        );

    for (final (index, batch) in batches.indexed) {
      final number = index + 1;
      final first = index == 0;
      final last = index == batches.length - 1;
      document.addPage(page(
        number,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (first) ...[
              FsaForm.heading('INSPECTION & FACILITY DETAILS', a),
              particulars(),
              pw.SizedBox(height: 12),
            ],
            if (!batch.isEmpty) checklist(batch),
            if (last) ...[
              pw.SizedBox(height: 10),
              FsaForm.heading('COMMENTS AND REMARKS', a),
              labelledBox('Comments (if found)', comments),
              labelledBox('Remarks', remarks),
              pw.SizedBox(height: 10),
              signatures(),
              photoStrip(),
            ],
          ],
        ),
      ));
    }

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await document.save(), flush: true);
    return out;
  }

  // --------------------------------------------------------------- paging
  //
  // The pdf package lays a page out but will not tell you it did not fit,
  // so the sheet works out for itself how much it is asking for. The
  // figures are the landscape page's own: 595pt tall, the letterhead's
  // margins, a header of about 100 and a footer of 14.

  /// What is left for the body once the margins, header and footer have had
  /// theirs — the margins being the letterhead's (Ethan, 2026-10-04).
  static double _bodyHeightFor(pw.EdgeInsets margin) =>
      PdfPageFormat.a4.landscape.height - margin.top - margin.bottom - 100 - 14;

  /// A particulars row: a 13pt box and 5pt under it.
  static const _fieldHeight = 20.0;

  /// A line of table text, and the padding above and below a row.
  static const _lineHeight = 9.5;
  static const _rowPadding = 3.0;

  /// Characters that fit on one line of the requirement and regulation
  /// columns, at 7.5pt across half the usable width.
  static const _requirementChars = 46;
  static const _regulationChars = 22;

  static double _rowHeight(FsaChecklistRow row) {
    final requirement = (row.requirement.length / _requirementChars).ceil();
    final regulation = row.value != null
        ? 1
        : (row.regulation.length / _regulationChars).ceil();
    final lines = [requirement, regulation, 1].reduce((a, b) => a > b ? a : b);
    return lines * _lineHeight + _rowPadding;
  }

  /// A block: its section heading bar (~32), its table header row, its
  /// requirements, and the gap under it.
  static double _sectionHeight(FsaChecklistSection section) =>
      42 +
      _lineHeight +
      _rowPadding +
      section.rows.fold<double>(0, (h, r) => h + _rowHeight(r)) +
      14;

  /// Comments, remarks, the two signatures and the photographs. The two
  /// extra ~32pt allowances are the "COMMENTS & REMARKS" and "SIGNATURES"
  /// section bars (Ethan, 2026-10-08).
  // The photographs now sit under their own grey bar with a numbered caption
  // under each picture, so they reserve more than the bare strip did
  // (Ethan, 2026-10-08). Under-reserving here does not clip — it silently
  // drops the whole closing block — so the figure is deliberately generous.
  static double _closingHeight(bool hasPhotos) =>
      12 + 42 + 34 + 34 + 12 + 42 + 115 + (hasPhotos ? 230 : 0);

  /// Splits a block that is taller than a column into blocks that are not,
  /// keeping the heading on each so a reader can see what they are looking
  /// at when a block runs over a column break.
  static List<FsaChecklistSection> _fit(
      FsaChecklistSection section, double budget) {
    // Each split keeps the section heading bar (~32) plus the table header row.
    const heading = 42 + _lineHeight + _rowPadding;
    if (_sectionHeight(section) <= budget) return [section];
    final out = <FsaChecklistSection>[];
    var rows = <FsaChecklistRow>[];
    var height = heading + 14;
    for (final row in section.rows) {
      final rowHeight = _rowHeight(row);
      if (rows.isNotEmpty && height + rowHeight > budget) {
        out.add(FsaChecklistSection(title: section.title, rows: rows));
        rows = <FsaChecklistRow>[];
        height = heading + 14;
      }
      rows.add(row);
      height += rowHeight;
    }
    if (rows.isNotEmpty) {
      out.add(FsaChecklistSection(title: section.title, rows: rows));
    }
    return out;
  }

  /// Deals the blocks into pages, two columns to a page.
  ///
  /// The limit is the height of one column, not the two together: a block
  /// sits in one column or the other and cannot be poured across both.
  static List<_Batch> _packPages(
    List<FsaChecklistSection> sections, {
    required double bodyHeight,
    required double particularsHeight,
    required double closingHeight,
  }) {
    final pages = <_Batch>[];
    var firstPage = true;
    double budget() => bodyHeight - (firstPage ? particularsHeight + 8 : 0);

    var left = <FsaChecklistSection>[];
    var right = <FsaChecklistSection>[];
    var leftUsed = 0.0;
    var rightUsed = 0.0;

    void turnPage() {
      pages.add(_Batch(left, right));
      left = <FsaChecklistSection>[];
      right = <FsaChecklistSection>[];
      leftUsed = 0;
      rightUsed = 0;
      firstPage = false;
    }

    final queue = <FsaChecklistSection>[];
    for (final section in sections) {
      queue.addAll(_fit(section, budget()));
    }

    for (final section in queue) {
      final height = _sectionHeight(section);
      if (leftUsed + height <= budget()) {
        left.add(section);
        leftUsed += height;
      } else if (rightUsed + height <= budget()) {
        right.add(section);
        rightUsed += height;
      } else {
        turnPage();
        // Re-split against the fuller budget of a page with no particulars.
        for (final part in _fit(section, budget())) {
          final partHeight = _sectionHeight(part);
          if (leftUsed + partHeight <= budget()) {
            left.add(part);
            leftUsed += partHeight;
          } else {
            right.add(part);
            rightUsed += partHeight;
          }
        }
      }
    }
    if (left.isNotEmpty || right.isNotEmpty) turnPage();
    if (pages.isEmpty) pages.add(const _Batch([], []));

    // The closing block runs the width of the sheet, so it needs room under
    // the taller of the two columns. Give it its own page when there is not.
    final last = pages.last;
    final tallest = [
      last.left.fold<double>(0, (h, s) => h + _sectionHeight(s)),
      last.right.fold<double>(0, (h, s) => h + _sectionHeight(s)),
    ].reduce((a, b) => a > b ? a : b);
    final used = tallest + (pages.length == 1 ? particularsHeight + 8 : 0);
    if (used + closingHeight > bodyHeight) pages.add(const _Batch([], []));
    return pages;
  }
}

/// The blocks on one page, already dealt into the sheet's two columns.
class _Batch {
  const _Batch(this.left, this.right);

  final List<FsaChecklistSection> left;
  final List<FsaChecklistSection> right;

  bool get isEmpty => left.isEmpty && right.isEmpty;
}
