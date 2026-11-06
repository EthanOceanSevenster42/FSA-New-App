import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The one date format every FSA document prints — "1 September 2021"
/// (Ethan, 2026-10-08: dates must read the same way everywhere, matching the
/// document-control header). Use this for every date shown on a report.
const _fsaMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];
String fsaDateLong(DateTime d) => '${d.day} ${_fsaMonths[d.month - 1]} ${d.year}';

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

  /// The Agency's address and contacts, as the letterhead prints them.
  static const letterheadAddress =
      '318 The Hillside Street, The Hillside Building, Lynnwood, Pretoria '
      '(4th Floor)';
  static const letterheadContacts =
      'Tel: (012) 361 1937  \u2022  info@afsq.co.za  \u2022  '
      'www.foodsafetyagency.co.za';

  /// How wide the strip of icons down the right edge is drawn, in points,
  /// and the room the page keeps for it.
  static const _iconStripWidth = 18.0;
  static const _iconStripRoom = 26.0;

  /// The page a document is drawn on: the Agency's letterhead as the
  /// background — logo top right, address top left, icons down the right
  /// edge, the band along the foot — with [margin] grown so the document's
  /// own form clears all four (Ethan, 2026-10-04). Without letterhead images
  /// the page is plain and the margin is the one given.
  static const _logoHeight = 30.0;
  static const _headTop = 10.0;
  static const _bandBottom = 8.0;
  /// The foot band's width, as a share of the content width.
  ///
  /// A 520pt cap once left it floating narrow in the middle of a landscape
  /// page, so it was taken to the full width — which made it heavier than
  /// everything above it. Just under full width keeps it centred under the
  /// body and in proportion with the rest of the sheet; because the band is
  /// an image, narrowing it is what makes it shorter (Ethan, 2026-10-08).
  static const _bandScale = 0.82;

  /// The margin a document's body sits inside on the letterhead: [margin]
  /// grown for the logo and address above, the icon strip to the right and
  /// the band below. A document that packs its own pages measures its body
  /// against this (Ethan, 2026-10-04).
  /// [agencyBranding] false drops the Agency's own mark and foot band,
  /// leaving the room they took to the body. [centrepieceHeight] is the
  /// height of anything put in the header in their place.
  static pw.EdgeInsets letterheadMargin(
    FsaFormAssets a,
    PdfPageFormat format, {
    required pw.EdgeInsets margin,
    bool agencyBranding = true,
    double centrepieceHeight = 0,
  }) {
    if (!a.hasLetterhead) return margin;
    final band = agencyBranding ? a.letterheadFooter : null;
    final headTall = agencyBranding
        ? (centrepieceHeight > _logoHeight ? centrepieceHeight : _logoHeight)
        : centrepieceHeight;
    final headBottom = _headTop + headTall + 8;
    // No icon strip on the Department's sheet, so no room kept for one.
    final right = margin.right +
        ((!agencyBranding || a.letterheadIcons == null) ? 0 : _iconStripRoom);
    final contentWidth = format.width - margin.left - right;
    final bandWidth =
        contentWidth * _bandScale;
    final bandHeight =
        band == null ? 0.0 : bandWidth * band.height! / band.width!;
    final foot = band == null ? margin.bottom : bandHeight + _bandBottom + 8;
    return pw.EdgeInsets.fromLTRB(
      margin.left,
      margin.top > headBottom ? margin.top : headBottom,
      right,
      margin.bottom > foot ? margin.bottom : foot,
    );
  }

  /// [centrepiece] is drawn centred on the page in the header band, between
  /// the Agency's mark and its address.
  ///
  /// The seizure form is served under the Department's authority and their
  /// template heads it with the national arms, centred. There is no room for
  /// it in the body — the sheet runs to the foot of the page already, and a
  /// centred band of any height at all pushed the signature controls onto a
  /// second sheet — but the header band's middle is empty, so it costs
  /// nothing to put it where it belongs (Ethan, 2026-10-12).
  static pw.PageTheme letterhead(
    FsaFormAssets a,
    PdfPageFormat format, {
    required pw.EdgeInsets margin,
    pw.MemoryImage? centrepiece,
    double centrepieceHeight = 34,

    /// False leaves the Agency's own mark and foot band off the page.
    ///
    /// The seizure form is the Department's, served under their authority,
    /// and Ethan asked for it to carry their arms alone (2026-10-12). The
    /// contact details stay: whoever is handed the sheet needs to know who
    /// to call.
    bool agencyBranding = true,
  }) {
    if (!a.hasLetterhead) {
      return pw.PageTheme(pageFormat: format, margin: margin, theme: a.theme);
    }
    final logo = agencyBranding ? a.letterheadLogo! : null;
    // The icon strip is the Agency's decoration too. On the Department's
    // seizure sheet it ran down the right-hand edge of their form, and in
    // portrait the Agency's address collided with their arms. Their
    // template carries the national arms and nothing else, so
    // agencyBranding:false now takes the whole of the Agency's dressing
    // with it (Ethan, 2026-10-20).
    final icons = agencyBranding ? a.letterheadIcons : null;
    final band = agencyBranding ? a.letterheadFooter : null;

    const logoHeight = _logoHeight;
    final logoWidth =
        logo == null ? 0.0 : logoHeight * logo.width! / logo.height!;
    const headTop = _headTop;

    final grown = letterheadMargin(a, format,
        margin: margin,
        agencyBranding: agencyBranding,
        centrepieceHeight: centrepiece == null ? 0 : centrepieceHeight);
    final right = grown.right;
    final contentWidth = format.width - margin.left - right;
    final bandWidth =
        contentWidth * _bandScale;
    final bandHeight =
        band == null ? 0.0 : bandWidth * band.height! / band.width!;
    const bandBottom = _bandBottom;

    final iconsHeight =
        icons == null ? 0.0 : _iconStripWidth * icons.height! / icons.width!;

    return pw.PageTheme(
      pageFormat: format,
      margin: grown,
      theme: a.theme,
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(
          children: [
            // The logo, top left (Ethan, 2026-10-08: logo and info swapped).
            if (logo != null)
              pw.Positioned(
                top: headTop,
                left: margin.left,
                child: pw.Image(logo, height: logoHeight, width: logoWidth),
              ),
            // The address and contacts, top right, beside the logo.
            if (agencyBranding)
              pw.Positioned(
              top: headTop + 4,
              right: right,
              child: pw.SizedBox(
                width: contentWidth - logoWidth - 16,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Food Safety Agency (Pty) Ltd',
                        style: a.text(isBold: true, size: 8)),
                    pw.Text(letterheadAddress,
                        style: pw.TextStyle(
                            font: a.regular,
                            fontSize: 6.5,
                            color: PdfColors.grey700)),
                    pw.Text(letterheadContacts,
                        style: pw.TextStyle(
                            font: a.regular,
                            fontSize: 6.5,
                            color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ),
            // The Department's arms, centred on the paper between the two.
            if (centrepiece != null)
              pw.Positioned(
                top: headTop,
                left: (format.width -
                        centrepieceHeight *
                            centrepiece.width! /
                            centrepiece.height!) /
                    2,
                child: pw.Image(centrepiece,
                    height: centrepieceHeight,
                    width: centrepieceHeight *
                        centrepiece.width! /
                        centrepiece.height!),
              ),
            // The commodity icons down the right edge, centred on the page.
            if (icons != null)
              pw.Positioned(
                top: (format.height - iconsHeight) / 2,
                right: (_iconStripRoom - _iconStripWidth) / 2 + 2,
                child: pw.Image(icons,
                    width: _iconStripWidth, height: iconsHeight),
              ),
            // "From compliance to confidence", along the foot.
            if (band != null)
              pw.Positioned(
                bottom: bandBottom,
                left: margin.left + (contentWidth - bandWidth) / 2,
                child: pw.Image(band, width: bandWidth, height: bandHeight),
              ),
          ],
        ),
      ),
    );
  }

  /// The document-control header, as the Agency's own forms print it: the
  /// Act across the top, then the logo beside the checklist's title and the
  /// five-row control table, and a rule under the lot. On the letterhead
  /// the logo is already at the top of the page, so the mark beside the
  /// table is left out (Ethan, 2026-10-04).
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
        // Issue and Effective dates are the same on every form, so they are
        // shown once as a single "Issue / Eff. Date" (Ethan, 2026-10-08)
        // rather than repeating the same date twice.
        pw.TableRow(children: [
          c('Doc Type', isBold: true),
          c(control.docType),
          c('Issue / Eff. Date', isBold: true),
          c(control.issueDate),
        ]),
        pw.TableRow(children: [
          c('Doc. No.', isBold: true),
          c(control.docNo),
          c('Rev. Date', isBold: true),
          c(control.revisionDate),
        ]),
        pw.TableRow(children: [
          c('IP', isBold: true),
          c(control.ip),
          c('Revision', isBold: true),
          c(control.revision),
        ]),
        pw.TableRow(children: [
          c('Designed by', isBold: true),
          c(control.designedBy),
          c(''),
          c(''),
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
            if (!a.hasLetterhead)
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

  /// The Agency's footer (name, version, page, timestamp) — removed at Ethan's
  /// request (2026-10-08). Kept as an empty widget so every caller still has a
  /// footer slot without printing the line.
  static pw.Widget pageFooter(FsaFormAssets a, int page, int pages,
          {DateTime? at}) =>
      pw.SizedBox();

  /// A section heading — a shaded bar that sections each part of the form off
  /// from the next, with space above it (Ethan, 2026-10-08: was a plain
  /// underline; now each section is clearly boxed and spaced).
  ///
  /// [compact] keeps the same bar but halves the space around it, for a dense
  /// form that has to stay on its one page — the compositional checklist is
  /// the Agency's one-sheet form and four roomy bars pushed it onto a second
  /// page (Ethan, 2026-10-08).
  static pw.Widget heading(String label, FsaFormAssets a,
          {bool compact = false}) =>
      pw.Container(
        width: double.infinity,
        margin: compact
            ? const pw.EdgeInsets.only(top: 7, bottom: 4)
            : const pw.EdgeInsets.only(top: 14, bottom: 8),
        padding: pw.EdgeInsets.symmetric(
            horizontal: 5, vertical: compact ? 2.5 : 4),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(width: 0.6, color: PdfColors.grey600),
        ),
        child: pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8, font: a.bold),
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

  /// The photographs, laid out to use the room the sheet actually has.
  ///
  /// Every picture is shown, framed and numbered so a finding can be
  /// referred to by photograph. They used to print at a fixed 100pt on a
  /// page that was otherwise empty — six postage stamps and half a sheet of
  /// white (Ethan, 2026-10-08).
  ///
  /// The cells are Expanded, so a row always fills the width whatever the
  /// page margins are, and the height follows the number of rows: fewer
  /// pictures means bigger ones. [maxHeight] is the total the block may take
  /// — a document whose photographs share a page with the signatures passes
  /// a smaller figure than one that gives them a page of their own.
  static pw.Widget photoGrid(
    List<pw.MemoryImage> photos,
    FsaFormAssets a, {
    double maxHeight = 420,
    int? perRow,
  }) {
    if (photos.isEmpty) return pw.SizedBox();
    // Fewer across means larger pictures; past six they have to get smaller
    // or they will not fit the page at all.
    final across = perRow ??
        (photos.length <= 2
            ? photos.length
            : photos.length <= 6
                ? 3
                : 4);
    final rows = (photos.length / across).ceil();
    const caption = 14.0;
    const gap = 8.0;
    final cell =
        ((maxHeight - (rows - 1) * gap) / rows - caption).clamp(70.0, 300.0);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < photos.length; row += across)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: row == 0 ? 0 : gap),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var i = row; i < row + across; i++)
                  pw.Expanded(
                    child: i >= photos.length
                        // Keeps the last row's pictures the same size as the
                        // rows above rather than stretching them.
                        ? pw.SizedBox()
                        : pw.Padding(
                            padding:
                                const pw.EdgeInsets.symmetric(horizontal: 5),
                            child: pw.Column(
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.all(3),
                                  decoration: pw.BoxDecoration(
                                      border: pw.Border.all(
                                          width: 0.5,
                                          color: PdfColors.grey600)),
                                  child: pw.SizedBox(
                                    height: cell,
                                    child: pw.Image(photos[i],
                                        fit: pw.BoxFit.contain),
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text('Photograph ${i + 1}',
                                    style: a.text(isBold: true, size: 7.5)),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// A bordered block of prose that wraps and grows with its text — what the
  /// inspector wrote, shown as written.
  ///
  /// Ruled lines are for a form a person fills in by hand; a sentence the
  /// handset already captured reads as content, not as a blank waiting to be
  /// completed, so it is framed instead (Ethan, 2026-10-08).
  static pw.Widget textBox(
    String value,
    FsaFormAssets a, {
    double minHeight = 26,
    double size = 8,
  }) =>
      pw.Container(
        width: double.infinity,
        constraints: pw.BoxConstraints(minHeight: minHeight),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6, color: PdfColors.grey600)),
        child: pw.Text(
          value.trim().isEmpty ? 'N/A' : value.trim(),
          style: a.text(size: size),
        ),
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
        // Room between one field and the next (Ethan, 2026-10-08).
        padding: const pw.EdgeInsets.only(bottom: 7),
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
  }) {
    // One ruled row per line. A caller may hand a single string that itself
    // holds several lines ("Rejection issued…\n1. The address…"); without
    // splitting it, all of them land in the first row and the overflow prints
    // on top of the rows below (Ethan, 2026-10-05). Each ruled row holds one
    // line, so the text rests on its own line rather than across the next.
    final flat = [
      for (final line in lines) ...line.split('\n'),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0;
            i < (flat.length > minimum ? flat.length : minimum);
            i++)
          pw.Container(
            // Min-height, not fixed: a line too long for the width wraps and
            // the row grows to fit it, so the text neither spills onto the
            // row below nor is clipped (Ethan, 2026-10-05).
            constraints: pw.BoxConstraints(minHeight: height),
            alignment: pw.Alignment.bottomLeft,
            padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
            child: pw.Text(i < flat.length ? flat[i] : '',
                style: a.text(size: 7.5)),
          ),
      ],
    );
  }

  /// A signature line: the image when one was given, the typed name when it
  /// is a name line, empty when the form is to be signed by hand.
  ///
  /// The signature is held clear of the rule rather than set on it. The
  /// signing pad saves an opaque white box, not a transparent one, so an
  /// image that reaches the bottom of this container paints the rule out
  /// behind it: the finished notice came off the handset with the line
  /// broken in the middle and the ink struck through what was left of it,
  /// which read as a line drawn across the signature (Ethan, 2026-11-03).
  static pw.Widget signatureLine(
    FsaFormAssets a, {
    pw.MemoryImage? signature,
    String name = '',
    double width = 150,
    double height = 22,
  }) {
    // Enough air that a descender cannot touch the rule, and the white
    // box behind the ink can never reach it.
    const clearance = 3.0;
    return pw.Container(
      width: width,
      height: height,
      alignment: pw.Alignment.bottomCenter,
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.7))),
      child: signature != null
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: clearance),
              // Sized off the space that is actually left, so a shorter
              // line (the compact forms use 17) cannot push the image
              // back onto the rule.
              child: pw.Image(signature,
                  height: (height - clearance - 1).clamp(6.0, 20.0),
                  fit: pw.BoxFit.contain),
            )
          : pw.Text(name, style: a.text(size: 7.5)),
    );
  }

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
    /// Shorter signing lines, for a dense form that must stay on one page
    /// (Ethan, 2026-10-08).
    bool compact = false,
  }) {
    final lineHeight = compact ? 17.0 : 22.0;
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
                signatureLine(a, signature: sig, height: lineHeight),
              ],
            ),
            pw.SizedBox(height: compact ? 3 : 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.SizedBox(
                    width: 150,
                    child: pw.Text('NAME & SURNAME:',
                        style: a.text(isBold: true, size: 7))),
                signatureLine(a, name: name, height: lineHeight),
              ],
            ),
          ]),
        );

    // The section is labelled by the "SIGNATURE CONTROLS" bar above it, so no
    // separate "SIGNED:" gutter here (Ethan, 2026-10-08).
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        side(leftCaption, inspectorSignature, inspectorName),
        pw.SizedBox(width: 24),
        side(rightCaption, authorisedPersonSignature, authorisedPersonName),
      ],
    );
  }

  /// The "@ Food Safety Agency (Pty) Ltd" caption — removed at Ethan's request
  /// (2026-10-08). Kept as an empty widget so callers are unchanged.
  static pw.Widget footer(FsaFormAssets a) => pw.SizedBox();

  /// Reads an image from disk, or null when the path is empty or the file
  /// has been cleared by the phone.
  static Future<pw.MemoryImage?> image(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return pw.MemoryImage(await file.readAsBytes());
  }

  /// The signature at [path], cropped to the ink.
  ///
  /// The signing pad saves its whole box, mostly empty; scaled into a
  /// signature line as it was, the ink came out a centimetre wide with
  /// hairline strokes (Ethan, 2026-09-30). Null when there is no
  /// signature; the image as saved when it cannot be read for cropping.
  static Future<pw.MemoryImage?> signature(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    try {
      final picture = img.decodeImage(bytes);
      if (picture == null) return pw.MemoryImage(bytes);
      var left = picture.width, top = picture.height, right = -1, bottom = -1;
      for (final px in picture) {
        final ink = px.a > 40 && px.luminanceNormalized < 0.8;
        if (!ink) continue;
        if (px.x < left) left = px.x;
        if (px.x > right) right = px.x;
        if (px.y < top) top = px.y;
        if (px.y > bottom) bottom = px.y;
      }
      if (right < 0) return null;
      const margin = 8;
      left = (left - margin).clamp(0, picture.width - 1);
      top = (top - margin).clamp(0, picture.height - 1);
      right = (right + margin).clamp(0, picture.width - 1);
      bottom = (bottom + margin).clamp(0, picture.height - 1);
      final cropped = img.copyCrop(picture,
          x: left, y: top, width: right - left + 1, height: bottom - top + 1);
      return pw.MemoryImage(img.encodePng(cropped));
    } on Object {
      return pw.MemoryImage(bytes);
    }
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

  /// A facility, product or document name as the file-naming convention
  /// spells it — letters and digits, hyphens between.
  static String nameSlug(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  /// The name a sheet rendered off one inspection is written under:
  /// facility, what was inspected, what the sheet is, and the record it
  /// came off — `FSA-Kroon-Foods-Beef-Sausage-Sampling-Checklist-9cbbdd52`.
  ///
  /// The product is in it because without it a visit with two of the same
  /// commodity wrote every sheet under the same stem, and neither the
  /// office nor the inspector could tell which product a checklist belonged
  /// to without opening it (Ethan, 2026-10-08).
  static String documentFileName({
    required String facility,
    required String kind,
    required String record,
    String product = '',
  }) {
    final short = record.length < 8 ? record : record.substring(0, 8);
    final what = nameSlug(product);
    var sheet = nameSlug(kind);
    if (what.isNotEmpty) {
      // "Eggs-Egg-Weighing-Checklist" says eggs twice. Drop the repeat,
      // counting a plural as the same word.
      String singular(String w) {
        final u = w.toUpperCase();
        return u.endsWith('S') ? u.substring(0, u.length - 1) : u;
      }

      final said = what.split('-').map(singular).toSet();
      final words = sheet.split('-');
      while (words.length > 1 && said.contains(singular(words.first))) {
        words.removeAt(0);
      }
      sheet = words.join('-');
    }
    final middle = what.isEmpty ? '' : '$what-';
    return 'FSA-${nameSlug(facility)}-$middle$sheet-$short.pdf';
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
    this.letterheadLogo,
    this.letterheadIcons,
    this.letterheadFooter,
    this.departmentLogo,
  }) : _letterhead = letterhead;

  final pw.Font regular;
  final pw.Font bold;
  final pw.MemoryImage logo;

  /// The Agency's 2026 letterhead (Ethan, 2026-10-04): the red logo, the
  /// strip of commodity icons for the right edge and the band for the foot
  /// of the page. Null when a renderer has none, and the documents then
  /// print as they did.
  final pw.MemoryImage? letterheadLogo;
  final pw.MemoryImage? letterheadIcons;
  final pw.MemoryImage? letterheadFooter;

  /// The Department of Agriculture's coat of arms and wordmark, as it heads
  /// the seizure form at FSA-SOP-APS-001 Annexure E.
  ///
  /// The Department asked for it on the seizure sheet, centred, the way
  /// their own template carries it (2026-10-12). Taken from that template.
  /// Null when a renderer has none, and the sheet then prints without it
  /// rather than failing.
  final pw.MemoryImage? departmentLogo;

  bool get hasLetterhead => letterheadLogo != null;

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
    this.approvedBy = 'Compliance Manager',
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
