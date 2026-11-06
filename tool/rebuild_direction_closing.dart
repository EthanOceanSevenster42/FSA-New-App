import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

/// Redraws the closing sheet of a rejection already filed with the office:
/// the signature controls, then the photographs.
///
/// A notice served for a labelling deviation went out carrying the
/// egg-quality photographs — evidence of something it does not allege —
/// and without the label photograph the form will not let an inspector
/// past (Jary Investments, PR-IND-IND-3647-001). The handset builds the
/// corrected sheet from now on, but a copy already filed cannot wait for
/// the inspector to re-send it, and the signatures on that sheet must
/// survive the correction. This redraws the page with the right pictures
/// under the same two signatures, so the filed copy can be replaced
/// without anyone re-capturing anything (Ethan, 2026-10-11).
///
///   dart run tool/rebuild_direction_closing.dart out.pdf \
///     --inspector "Ben" --inspector-signature sig1.png \
///     --client "Anne"  --client-signature sig2.png \
///     photo.jpg [...]
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: rebuild_direction_closing.dart <out.pdf> '
        '[--inspector NAME] [--inspector-signature FILE] '
        '[--client NAME] [--client-signature FILE] <photo> [...]');
    exitCode = 2;
    return;
  }

  final out = File(args.first);
  var inspectorName = '';
  var clientName = '';
  var correctBy = '';
  var pleaseNote = '';
  final remarks = <String>[];
  String? inspectorSignaturePath;
  String? clientSignaturePath;
  final photoPaths = <String>[];

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--inspector':
        inspectorName = args[++i];
      case '--client':
        clientName = args[++i];
      case '--correct-by':
        correctBy = args[++i];
      case '--remark':
        remarks.add(args[++i]);
      case '--note':
        pleaseNote = args[++i];
      case '--inspector-signature':
        inspectorSignaturePath = args[++i];
      case '--client-signature':
        clientSignaturePath = args[++i];
      default:
        photoPaths.add(args[i]);
    }
  }

  Future<pw.MemoryImage?> image(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('missing: $path');
      return null;
    }
    return pw.MemoryImage(await file.readAsBytes());
  }

  final photos = <pw.MemoryImage>[];
  for (final path in photoPaths) {
    final picture = await image(path);
    if (picture != null) photos.add(picture);
  }
  if (photos.isEmpty) {
    stderr.writeln('no photographs to draw');
    exitCode = 1;
    return;
  }

  // The same fonts and letterhead the handset draws with, so the rebuilt
  // sheet is indistinguishable from the one it replaces.
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer
            .asByteData()),
    bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
        .buffer
        .asByteData()),
    logo: pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
    letterhead: pw.MemoryImage(
        await File('assets/images/fsa_letterhead_logo.jpg').readAsBytes()),
    letterheadLogo: pw.MemoryImage(
        await File('assets/images/letterhead_logo.png').readAsBytes()),
    letterheadIcons: pw.MemoryImage(
        await File('assets/images/letterhead_icons.png').readAsBytes()),
    letterheadFooter: pw.MemoryImage(
        await File('assets/images/letterhead_footer.png').readAsBytes()),
  ));

  final a = await FsaForm.assets();
  // Resolved before the page builder runs: the builder is synchronous.
  // Cropped to the ink, as the documents now do: a signing pad saves its
  // whole box and the pad is portrait, so an uncropped signature scaled
  // into a wide, short signing line came out a tenth of its width
  // (Ethan, 2026-10-12).
  final inspectorSignature = inspectorSignaturePath == null
      ? null
      : await FsaForm.signature(inspectorSignaturePath);
  final clientSignature = clientSignaturePath == null
      ? null
      : await FsaForm.signature(clientSignaturePath);
  final document = pw.Document();
  // MultiPage, not Page: a Page silently DROPS whatever does not fit, and
  // restoring the remarks block pushed the photographs off the sheet
  // without a word. This is how direction_pdf.dart draws it too, so the
  // rebuilt closing breaks where the handset would break it.
  pw.Widget together(List<pw.Widget> children) => pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: children,
        ),
      );
  document.addPage(
    pw.MultiPage(
      pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
      build: (context) => [
          if (correctBy.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10, bottom: 3),
              child: pw.Row(children: [
                pw.Text(
                  'Rectify the non-conformity as mentioned below before or '
                  'on ',
                  style: a.text(size: 7.5),
                ),
                FsaForm.box(correctBy, a, width: 90),
              ]),
            ),
          together([
            FsaForm.heading('COMMENTS AND REMARKS', a),
            FsaForm.ruledLines(remarks, a, minimum: 3),
            if (pleaseNote.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text('Please note:  $pleaseNote',
                    style: a.text(size: 7)),
              ),
          ]),
          together([
            pw.SizedBox(height: 18),
            FsaForm.heading('SIGNATURE CONTROLS', a),
            FsaForm.signedBlock(
              a,
              inspectorName: inspectorName,
              authorisedPersonName: clientName,
              inspectorSignature: inspectorSignature,
              authorisedPersonSignature: clientSignature,
            ),
          ]),
          together([
            FsaForm.heading('PHOTOGRAPHS', a),
            FsaForm.photoGrid(photos, a),
          ]),
      ],
    ),
  );

  await out.parent.create(recursive: true);
  await out.writeAsBytes(await document.save(), flush: true);
  stdout.writeln('${out.path}  (${photos.length} photographs, '
      'signed by $inspectorName and $clientName)');
}
