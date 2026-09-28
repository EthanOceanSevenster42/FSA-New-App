import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Puts several rendered documents into one file, in the order given.
///
/// The office asks for "the compliance documents" as one thing, not as three
/// separate downloads to be found and stapled afterwards.
///
/// Each page is rendered and placed at its own size, so a merged file reads
/// and prints the same way the separate ones do. [dpi] is what that render
/// runs at — high enough for the printed regulation references to stay
/// legible, low enough that a checklist with photographs on it does not turn
/// into a file nobody can email.
Future<Uint8List> mergeDocuments(List<File> files, {double dpi = 150}) async {
  final merged = pw.Document();
  for (final file in files) {
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      final image = pw.MemoryImage(await page.toPng());
      // 72 points to the inch: the page keeps the size it was drawn at.
      final format = PdfPageFormat(
        page.width / dpi * 72,
        page.height / dpi * 72,
      );
      merged.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
  }
  return merged.save();
}
