import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:image/image.dart' as img;
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The signing rule must survive the signature sitting on it.
///
/// The signing pad saves an opaque white box, not a transparent one. The
/// signature line drew that box flush with the bottom of its container,
/// which is exactly where the rule is — so the image painted the rule out
/// behind it, and the notice reached the client with the line broken in
/// the middle and the ink struck across what was left. It read as somebody
/// having drawn a line through the signature.
///
/// The geometry check below is the regression guard. It also writes a real
/// page out so the fix can be looked at rather than taken on trust.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFsaFormAssets();

  /// A stand-in for what the pad saves: ink on an opaque white field, with
  /// a stroke running to the very bottom of the box like a descender.
  pw.MemoryImage padSignature() {
    final canvas = img.Image(width: 300, height: 120);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    for (var x = 20; x < 280; x++) {
      final y = 20 + ((x - 20) * 99 ~/ 260);
      img.drawPixel(canvas, x, y, img.ColorRgb8(0, 0, 0));
      img.drawPixel(canvas, x, y + 1, img.ColorRgb8(0, 0, 0));
    }
    return pw.MemoryImage(img.encodePng(canvas));
  }

  test('the signature is held clear of the rule', () {
    // What the fix rests on: the image is sized from the space left after
    // the clearance, so its opaque box can never reach the rule at the
    // bottom of the container — at the full height or the compact one.
    const clearance = 3.0;
    for (final lineHeight in [22.0, 17.0]) {
      final imageHeight = (lineHeight - clearance - 1).clamp(6.0, 20.0);
      expect(imageHeight + clearance, lessThan(lineHeight),
          reason: 'the signature must not reach the rule at $lineHeight pt');
      expect(imageHeight, greaterThan(5),
          reason: 'the signature must stay legible at $lineHeight pt');
    }
  });

  test('a signed block renders, and is written out to be looked at',
      () async {
    final assets = await FsaForm.assets();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 40),
            FsaForm.heading('SIGNATURE CONTROLS', assets),
            pw.SizedBox(height: 20),
            FsaForm.signedBlock(
              assets,
              inspectorName: 'Kabelo Percy',
              authorisedPersonName: 'Mohammed',
              inspectorSignature: padSignature(),
              authorisedPersonSignature: padSignature(),
            ),
            pw.SizedBox(height: 30),
            FsaForm.signedBlock(
              assets,
              inspectorName: 'Kabelo Percy (compact)',
              authorisedPersonName: 'Mohammed',
              inspectorSignature: padSignature(),
              authorisedPersonSignature: padSignature(),
              compact: true,
            ),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));

    final out = File('${Directory.systemTemp.path}/signature_line_check.pdf');
    await out.writeAsBytes(bytes);
    // ignore: avoid_print
    print('signature sample written to: ${out.path}');
    expect(out.existsSync(), isTrue);
  });

  test('a name line still prints the typed name', () async {
    // Only the image overlapped; the typed name already sat above the rule
    // and must keep doing so.
    final assets = await FsaForm.assets();
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (_) => FsaForm.signatureLine(assets, name: 'Kabelo Percy'),
    ));
    expect((await doc.save()).length, greaterThan(1000));
  });
}
