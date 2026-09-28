import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'fsa_form_pdf.dart';

/// Teaches [FsaForm] to read its fonts and logo from the app's asset
/// bundle.
///
/// The document layer itself is plain Dart so the Agency's forms can be
/// rendered by a command-line tool as well as by the handset; this is the
/// one place that knows about Flutter's bundle. Called once at start-up,
/// and harmless if called again.
void installFsaFormAssets() {
  FsaForm.assetLoader ??= () async => FsaFormAssets(
        regular:
            pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Bold.ttf')),
        logo: pw.MemoryImage(
          (await rootBundle.load('assets/images/FSA_Logo.png'))
              .buffer
              .asUint8List(),
        ),
        letterhead: pw.MemoryImage(
          (await rootBundle.load('assets/images/fsa_letterhead_logo.jpg'))
              .buffer
              .asUint8List(),
        ),
      );
}
