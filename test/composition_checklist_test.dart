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
    test('nine requirements, in the form\'s order', () {
      expect(CompositionChecklist.items.length, 9);
      expect(CompositionChecklist.items.first, startsWith('Manufactured from'));
      expect(CompositionChecklist.items.last, 'Total Meat Content');
    });

    test('answers survive a round trip through JSON', () {
      final answers = CompositionChecklist.blank();
      answers[0] = const CompositionAnswer(
          deviation: true, contributionGrams: '12.5', remarks: 'Pork added');
      answers[8] = const CompositionAnswer(
          deviation: false, contributionGrams: '88', remarks: '');
      final back = CompositionChecklist.decode(CompositionChecklist.encode(answers));
      expect(back[0].deviation, isTrue);
      expect(back[0].contributionGrams, '12.5');
      expect(back[0].remarks, 'Pork added');
      expect(back[8].deviation, isFalse);
      expect(back[8].contributionGrams, '88');
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
      answers[6] = const CompositionAnswer(deviation: true, remarks: 'Colourant');
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
      expect(file.path, contains('Kroon-Foods-Compositional-Checklist'));
      expect(file.lengthSync(), greaterThan(1000));
    });
  });
}
