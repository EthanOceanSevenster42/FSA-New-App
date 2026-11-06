import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Which photographs belong on an egg rejection.
///
/// A notice served for a labelling deviation went out carrying the
/// egg-quality photographs — evidence of something it does not allege —
/// and without the label photograph the form will not let an inspector
/// past (Jary Investments, PR-IND-IND-3647-001, reported 2026-10-11).
///
/// One egg record holds photographs of several kinds at once while the
/// notice served off it may be for either part, so this is the one
/// commodity where the wrong evidence can reach a statutory document.
void main() {
  group('the rule', () {
    test('a labelling notice carries the label photograph, not the eggs', () {
      expect(
          EggRules.rejectionPhotoKinds(labellingPart: true, qualityPart: false),
          {'label'});
    });

    test('a quality notice carries the egg photographs, not the label', () {
      expect(
          EggRules.rejectionPhotoKinds(labellingPart: false, qualityPart: true),
          {'egg', 'deviation'},
          reason: '"deviation" is the older name for a quality photograph '
              'and is still on records in the field');
    });

    test('a notice serving both parts carries both sets', () {
      expect(
          EggRules.rejectionPhotoKinds(labellingPart: true, qualityPart: true),
          {'egg', 'deviation', 'label'});
    });

    test('a notice naming neither keeps everything rather than nothing', () {
      expect(
          EggRules.rejectionPhotoKinds(
              labellingPart: false, qualityPart: false),
          {'egg', 'deviation', 'label'},
          reason: 'malformed, but losing the evidence is the worse failure');
    });

    test('the numbering photograph is on neither notice', () {
      for (final parts in [(true, false), (false, true), (true, true)]) {
        expect(
            EggRules.rejectionPhotoKinds(
                labellingPart: parts.$1, qualityPart: parts.$2),
            isNot(contains('numbering')),
            reason: 'it evidences how the eggs were numbered, not a '
                'deviation');
      }
    });
  });

  group('the rejection it produces', () {
    late LocalDatabase db;
    late EggsRepository eggs;
    late Directory work;

    /// A JPEG of deterministic noise. JPEG is the one format the PDF
    /// embeds byte for byte, so the finished document can be searched for
    /// it — but two pictures of a FLAT colour compress to long stretches
    /// of identical bytes, and a slice of one was found inside the other.
    /// Noise makes each one unmistakable.
    File jpeg(String name, int seed) {
      final picture = img.Image(width: 64, height: 64);
      var x = seed * 2654435761 % 4294967296;
      for (final pixel in picture) {
        x = (x * 1103515245 + 12345) % 4294967296;
        pixel.setRgb((x >> 16) & 0xFF, (x >> 8) & 0xFF, x & 0xFF);
      }
      return File('${work.path}/$name')
        ..writeAsBytesSync(img.encodeJpg(picture, quality: 95));
    }

    setUp(() async {
      // The same fonts and letterhead the handset draws with; without them
      // the document refuses to render at all.
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
      work = await Directory.systemTemp.createTemp('egg-rejection-');
      db = LocalDatabase(NativeDatabase.memory());
      eggs = EggsRepository(database: db, baseUrl: '');
      // Deliberately NOT loading assets/reference/eggs_reference.json: it
      // carries 5,009 suppliers and 720 tolerances, and inserting those row
      // by row for every test took minutes. None of it bears on which
      // photographs reach the sheet.
    });

    tearDown(() async {
      await db.close();
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    Future<void> seed({
      required bool labellingPart,
      required bool qualityPart,
      required File labelPhoto,
      required File eggPhoto,
    }) async {
      const uuid = 'jary-egg';
      final when = DateTime(2026, 10, 9, 10, 30);
      await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
            clientUuid: uuid,
            inspectedAt: when,
            updatedAt: when,
            inspectorUsername: const Value('inspector1'),
            facilityName: const Value('Jary Investments'),
            clientName: const Value('Jary Investments'),
            producerSupplier: const Value('Ganico'),
            failedRequirementIds: const Value('1,2'),
          ));
      for (final (kind, file) in [('label', labelPhoto), ('egg', eggPhoto)]) {
        await db.into(db.eggPhotos).insert(EggPhotosCompanion.insert(
              inspectionUuid: uuid,
              kind: kind,
              filePath: file.path,
              capturedAt: when,
            ));
      }
      await eggs.saveDirection(EggDirectionsCompanion.insert(
        clientUuid: '$uuid-rejection',
        inspectionUuid: const Value(uuid),
        issuedAt: when,
        updatedAt: when,
        inspectorUsername: const Value('inspector1'),
        status: const Value('completed'),
        directionNumber: const Value('PR-IND-IND-3647-001'),
        labellingPart: Value(labellingPart),
        qualityPart: Value(qualityPart),
        labelCorrectBy: Value(DateTime(2026, 10, 30)),
        clientName: const Value('Jary Investments'),
        producerSupplier: const Value('Ganico'),
      ));
    }

    /// Whether the finished document carries this picture.
    ///
    /// A JPEG goes into a PDF byte for byte, so a slice of its compressed
    /// data is enough to recognise it and far quicker than matching the
    /// whole file against a document of three quarters of a megabyte.
    bool holds(List<int> document, List<int> picture) {
      // Past the headers, into the data two flat colours differ in.
      final from = picture.length ~/ 2;
      final mark = picture.sublist(from, from + 48);
      outer:
      for (var i = 0; i <= document.length - mark.length; i++) {
        for (var j = 0; j < mark.length; j++) {
          if (document[i + j] != mark[j]) continue outer;
        }
        return true;
      }
      return false;
    }

    test('a labelling notice shows the label, never the eggs',
        () async {
      final label = jpeg('label.jpg', 1);
      final egg = jpeg('egg.jpg', 2);
      await seed(
          labellingPart: true,
          qualityPart: false,
          labelPhoto: label,
          eggPhoto: egg);

      final out = await eggs.buildDirection('jary-egg', into: work);
      expect(out, isNotNull, reason: 'the rejection must still be produced');
      final bytes = await out!.readAsBytes();

      expect(holds(bytes, label.readAsBytesSync()), isTrue,
          reason: 'the label photograph is the evidence the notice rests on');
      expect(holds(bytes, egg.readAsBytesSync()), isFalse,
          reason: 'the egg-quality photographs allege something this notice '
              'does not — this is the Jary defect');
    });

    test('a quality notice shows the eggs, never the label',
        () async {
      final label = jpeg('label.jpg', 1);
      final egg = jpeg('egg.jpg', 2);
      await seed(
          labellingPart: false,
          qualityPart: true,
          labelPhoto: label,
          eggPhoto: egg);

      final out = await eggs.buildDirection('jary-egg', into: work);
      final bytes = await out!.readAsBytes();

      expect(holds(bytes, egg.readAsBytesSync()), isTrue);
      expect(holds(bytes, label.readAsBytesSync()), isFalse);
    });

    test('a notice serving both parts shows both', () async {
      final label = jpeg('label.jpg', 1);
      final egg = jpeg('egg.jpg', 2);
      await seed(
          labellingPart: true,
          qualityPart: true,
          labelPhoto: label,
          eggPhoto: egg);

      final out = await eggs.buildDirection('jary-egg', into: work);
      final bytes = await out!.readAsBytes();

      expect(holds(bytes, label.readAsBytesSync()), isTrue);
      expect(holds(bytes, egg.readAsBytesSync()), isTrue);
    });
  });
}
