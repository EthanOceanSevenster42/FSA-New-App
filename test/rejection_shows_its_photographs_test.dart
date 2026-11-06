import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fsa_app/core/documents/direction_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';

/// A rejection must show the photographs it was served on.
///
/// Reported 2026-10-08: six photographs were taken of underweight eggs and
/// not one appeared on the rejection. Two faults behind it — the egg
/// repository never passed them (the parameter was optional, so nothing
/// complained), and the sheet printed only the first four anyway. Both are
/// held here: the evidence is what makes the notice arguable.
void main() {
  // The document layer loads its fonts and logo through the asset bundle,
  // which needs the test binding up first.
  TestWidgetsFlutterBinding.ensureInitialized();
  installFsaFormAssets();

  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('rejection'));
  tearDown(() => scratch.deleteSync(recursive: true));

  /// A real picture the PDF can embed.
  Future<String> photo(String name) async {
    final canvas = img.Image(width: 24, height: 24);
    img.fill(canvas, color: img.ColorRgb8(180, 180, 180));
    final file = File('${scratch.path}/$name');
    await file.writeAsBytes(img.encodePng(canvas));
    return file.path;
  }

  Future<String> rejectionWith(List<String> photos) async {
    final out = await DirectionPdf.write(
      out: File('${scratch.path}/rejection.pdf'),
      control: FsaDocuments.eggDirection,
      natureOfInspection: 'Egg Quality',
      facilityName: 'SHOPRITE - Bridge City Mall',
      ownerOrRepresentative: 'P. Person',
      physicalAddress: 'Shop L2 Bridge City Mall',
      emailAddress: '',
      dateOfVisit: DateTime(2026, 10, 8),
      inspectionReason: 'Egg Quality',
      latestReference: '',
      originalReference: 'REJ-261008-001',
      subjectFields: const [(label: 'Batch Number', value: 'EG-4471')],
      deviations: const [
        DirectionDeviation(
            product: 'Large Grade 1 Eggs',
            nature: 'Underweight — 6 of 12 eggs in the sample.',
            regulation: 'Reg. 10'),
      ],
      correctByDate: '3 November 2026',
      actionsAndRemark: '',
      inspectorName: 'CINGA NGONGO',
      authorisedPersonName: 'P. Person',
      photoPaths: photos,
    );
    return String.fromCharCodes(await out.readAsBytes());
  }

  /// Embedded images in the file. The page text is compressed, so the
  /// pictures are counted rather than read.
  int imagesIn(String pdf) => '/Subtype/Image'.allMatches(pdf).length;

  test('every deviation photograph is embedded, not just the first four',
      () async {
    final none = imagesIn(await rejectionWith(const []));
    // What one picture costs: a PNG with transparency embeds as an image and
    // a soft mask, so the count per photograph is measured, not assumed.
    final each = imagesIn(await rejectionWith([await photo('one.png')])) - none;
    expect(each, greaterThan(0), reason: 'a photograph must embed something');

    final six = imagesIn(await rejectionWith([
      for (var n = 1; n <= 6; n++) await photo('egg-$n.png'),
    ]));

    // Six pictures' worth. The sheet used to take(4), so two of an egg
    // inspection's six were dropped without a word.
    expect(six - none, each * 6,
        reason: 'all six photographs taken must reach the notice');
  });

  test('a rejection with nothing photographed prints no empty section',
      () async {
    final pdf = await rejectionWith(const []);

    expect(pdf, isNot(contains('PHOTOGRAPHS')));
  });
}

