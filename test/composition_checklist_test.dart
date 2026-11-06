import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/rawrmp/data/composition_checklist_pdf.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';

/// SOP-APS-RAW-003: the Regulation 5 compositional checklist, stored on the
/// raw inspection and printed as the Agency's one-page landscape form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The document layer is plain Dart; the handset installs its font and
  // logo loader at start-up, and a test that renders a form has to do the
  // same or it has no assets to draw with.
  installFsaFormAssets();

  group('the checklist as data', () {
    test('eight requirements, in the form\'s order', () {
      expect(CompositionChecklist.items.length, 9);
      expect(CompositionChecklist.items[3], 'Spice');
      expect(CompositionChecklist.items[4], 'Water');
      expect(CompositionChecklist.items[6], 'Food stuff');
      // Asked for by Neo Noe, 2026-10-19 — boerewors may not contain it.
      expect(CompositionChecklist.items[7],
          'Mechanically deboned meat (MDM)');
      expect(CompositionChecklist.totalMeatIndex, 8);
      expect(CompositionChecklist.items, isNot(contains('Contain colourants')));
      expect(CompositionChecklist.items,
          isNot(contains('Contain other foodstuffs')));
      expect(CompositionChecklist.items.first, startsWith('Manufactured from'));
      expect(CompositionChecklist.items.last, 'Total Meat Content');
    });

    test('answers survive a round trip through JSON', () {
      final answers = CompositionChecklist.blank();
      answers[0] = const CompositionAnswer(
          deviation: true, contributionGrams: '12.5', remarks: 'Pork added');
      answers[6] = const CompositionAnswer(
          deviation: false, contributionGrams: '88', remarks: '');
      final back = CompositionChecklist.decode(CompositionChecklist.encode(answers));
      expect(back[0].deviation, isTrue);
      expect(back[0].contributionGrams, '12.5');
      expect(back[0].remarks, 'Pork added');
      expect(back[6].deviation, isFalse);
      expect(back[6].contributionGrams, '88');
      expect(back[1].isBlank, isTrue);
      expect(CompositionChecklist.isAnswered(back), isTrue);
    });

    test('an old record, or rubbish, reads as an untouched checklist', () {
      expect(CompositionChecklist.isAnswered(CompositionChecklist.decode('')),
          isFalse);
      expect(CompositionChecklist.decode('not json').length, 9);
      expect(CompositionChecklist.decode('{"a":1}').every((a) => a.isBlank),
          isTrue);
    });

    test('one remark for the checklist, kept beside the rows', () {
      final json = CompositionChecklist.encode(CompositionChecklist.blank(),
          remarks: 'All in order');
      expect(CompositionChecklist.remarksOf(json), 'All in order');
      expect(CompositionChecklist.decode(json).length, 9);
      // A record from before the remark moved to the bottom has none.
      expect(CompositionChecklist.remarksOf('[]'), '');
    });

    test('amounts are in kg; a record typed in grams keeps saying g', () {
      // In kg from 1 October 2026 (Ethan).
      expect(CompositionChecklist.unitOf(''), 'kg');
      expect(
          CompositionChecklist.unitOf(
              CompositionChecklist.encode(CompositionChecklist.blank())),
          'kg');
      expect(CompositionChecklist.unitOf('[{"grams": "12"}]'), 'g');
      expect(CompositionChecklist.unitOf('{"rows": [{"grams": "12"}]}'), 'g');
      final a = [
        for (var i = 0; i < CompositionChecklist.items.length; i++)
          CompositionAnswer(
            contributionGrams: const ['0.1', '0.05', '0.05', '0', '0', '0', '0', '0', ''][i],
            meatGrams: i == CompositionChecklist.totalMeatIndex ? '0.8' : '',
          ),
      ];
      // Meat is row 1: 0.1 kg of 0.2 kg in all.
      expect(CompositionChecklist.percentText(
              CompositionChecklist.totalMeatPercent(a)!),
          '50.0%');
    });

    test('a record saved with nine rows drops the two removed', () {
      // Rows 7 and 8 (colourants, other foodstuffs) are gone; Total Meat
      // Content, the ninth, is still the last row's answer.
      final nine = [
        for (var i = 0; i < 9; i++)
          {'deviation': i == 5, 'grams': '$i', 'remarks': 'row ${i + 1}'},
      ];
      final back = CompositionChecklist.decode(jsonEncode(nine));
      expect(back.length, 9);
      expect(back[5].remarks, 'row 6');
      expect(back[5].deviation, isTrue);
      // The old ninth row lands in the first free slot now (Ethan,
      // 2026-10-05); Total Meat Content is a computed result with no box.
      expect(back[6].remarks, 'row 9');
    });
  });

  group('the document', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('comp'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('is one landscape page', () async {
      final answers = CompositionChecklist.blank();
      answers[0] = const CompositionAnswer(
          deviation: false, contributionGrams: '100', remarks: 'Beef only');
      answers[4] = const CompositionAnswer(deviation: true, remarks: 'MRM found');
      final out = await CompositionChecklistPdf.write(
        out: File('${tmp.path}/checklist.pdf'),
        facilityName: 'Mabovula Butchery',
        facilityAddress: '12 Main Street, Queenstown',
        dateOfSampling: '28/08/2026',
        siteRepresentative: 'S. Mabovula',
        representativePosition: 'Owner',
        facilityType: 'Butchery',
        productName: 'Beef sausage',
        batchNumber: 'B-2201',
        manufacturedPackedDate: '27/08/2026',
        answers: answers,
        comments: 'Mechanically recovered meat present; not declared.',
        inspectorName: 'Cinga Mkhize',
        authorisedPersonName: 'S. Mabovula',
      );
      final text = String.fromCharCodes(await out.readAsBytes());
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 1);
      final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
          .firstMatch(text)!;
      expect(double.parse(box.group(1)!), greaterThan(double.parse(box.group(2)!)),
          reason: 'landscape, as the form is');
    });

    // The rejection's remarks are printed on the checklist (Ethan,
    // 2026-09-29). They are an extra block of their own on top of a form
    // that already fills its sheet, so with them the checklist may run to a
    // second page — the form without them still fits one, which the test
    // above holds (Ethan, 2026-10-08).
    test('carries the rejection remarks', () async {
      final answers = CompositionChecklist.blank();
      answers[4] = const CompositionAnswer(
          deviation: true, contributionGrams: '12', remarks: 'MRM found');
      final out = await CompositionChecklistPdf.write(
        out: File('${tmp.path}/with-remarks.pdf'),
        facilityName: 'Mabovula Butchery',
        facilityAddress: '12 Main Street, Queenstown',
        dateOfSampling: '28/08/2026',
        siteRepresentative: 'S. Mabovula',
        representativePosition: 'Owner',
        facilityType: 'Butchery',
        productName: 'Beef sausage',
        batchNumber: 'B-2201',
        manufacturedPackedDate: '27/08/2026',
        answers: answers,
        comments: 'Mechanically recovered meat present; not declared.',
        rejectionRemarks: 'Rejection issued and discussed with Client\n'
            'Rejection issued and immediately rectified\n'
            'Rejection issued and product removed',
        inspectorName: 'Cinga Mkhize',
        authorisedPersonName: 'S. Mabovula',
      );
      final text = String.fromCharCodes(await out.readAsBytes());
      expect(text, contains('%PDF-'));
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length,
          lessThanOrEqualTo(2));
    });

    test('is built from the record, and not at all when untouched', () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RawRmpRepository(database: db, baseUrl: '');
      final now = DateTime(2026, 8, 28, 11);
      await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-untouched',
            inspectedAt: now,
            updatedAt: now,
            facilityName: const Value('Kroon Foods'),
          ));
      expect(await repo.buildCompositionChecklist('raw-untouched'), isNull);

      final answers = CompositionChecklist.blank();
      answers[5] = const CompositionAnswer(deviation: true, remarks: 'Offal');
      await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-answered',
            inspectedAt: now,
            updatedAt: now,
            facilityName: const Value('Kroon Foods'),
            productItem: const Value('Boerewors'),
            batchNumber: const Value('77'),
            contactPerson: const Value('P. Person'),
            compositionChecklistJson:
                Value(CompositionChecklist.encode(answers)),
            representativePosition: const Value('Manager'),
          ));
      final file =
          await repo.buildCompositionChecklist('raw-answered', into: tmp);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      // The product sits between the facility and the sheet now, so a
      // visit with two raw products no longer writes both under the same
      // stem (Ethan, 2026-10-08).
      expect(file.path,
          contains('Kroon-Foods-Boerewors-Compositional-Checklist'));
      expect(file.lengthSync(), greaterThan(1000));
    });
  });
}
