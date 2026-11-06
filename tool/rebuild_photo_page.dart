import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

/// Redraws a document's PHOTOGRAPHS page with the pictures at full size.
///
/// A report already filed with the office carries its photographs as
/// thumbnails on an otherwise empty sheet. The evidence is right; only the
/// presentation is cramped. This takes the pictures out of the sheet that
/// was filed and lays them out the way the app does now, so the filed copy
/// can be replaced without the inspector re-capturing anything
/// (Ethan, 2026-10-08).
///
///   dart run tool/rebuild_photo_page.dart <out.pdf> <photo.jpg> [...]
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: rebuild_photo_page.dart <out.pdf> <photo> [...]');
    exitCode = 2;
    return;
  }
  final out = File(args.first);
  final photos = <pw.MemoryImage>[];
  for (final path in args.skip(1)) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('missing: $path');
      continue;
    }
    photos.add(pw.MemoryImage(await file.readAsBytes()));
  }
  if (photos.isEmpty) {
    stderr.writeln('no photographs to draw');
    exitCode = 1;
    return;
  }

  // The same fonts and letterhead the app draws with, so the rebuilt sheet
  // is indistinguishable from the ones around it.
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer
            .asByteData()),
    bold: pw.Font.ttf(
        (await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
            .buffer
            .asByteData()),
    logo: pw.MemoryImage(
        await File('assets/images/FSA_Logo.png').readAsBytes()),
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
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          FsaForm.heading('PHOTOGRAPHS', a),
          FsaForm.photoGrid(photos, a),
        ],
      ),
    ),
  );
  await out.parent.create(recursive: true);
  await out.writeAsBytes(await document.save(), flush: true);
  stdout.writeln('${out.path}  (${photos.length} photographs)');
}
