import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/seizures/data/seizure_repository.dart';

/// The Product class column on the seizure sheet (Cinga, 2026-10-26).
///
/// The sheet filled its class from the record only for eggs and returned
/// nothing for everything else, so every raw, processed meat and poultry
/// seizure went out with the column blank — ten of them in one visit —
/// while the record held a perfectly good class and APS was already
/// showing it (Herti Deli, group 4573).
///
/// Only raw and processed meat products are sold against a class. Eggs
/// and poultry carry sizes, grades and designations instead, so their
/// column reads N/A -- answered, rather than looking like an omission on
/// a notice served under section 8.
void main() {
  late LocalDatabase db;
  late SeizureRepository seizures;
  late Directory work;
  final when = DateTime(2026, 10, 23, 9, 28);

  setUp(() async {
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
      departmentLogo: pw.MemoryImage(
          await File('assets/images/dept_agriculture_logo.jpg').readAsBytes()),
    ));
    work = await Directory.systemTemp.createTemp('seizure-class-');
    db = LocalDatabase(NativeDatabase.memory());
    seizures = SeizureRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Future<void> seize(String kind, String recordUuid,
      {String productName = 'Cheese Boerewors'}) async {
    await seizures.record(SeizuresCompanion.insert(
      clientUuid: 'seizure-$recordUuid',
      recordUuid: recordUuid,
      recordKind: kind,
      issuedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('cinga'),
      clientName: const Value('Herti Deli (Q Meats) /Essmor'),
      productName: Value(productName),
      regulation: const Value('R.2410 of 26 August 2022'),
      natureOfDeviation:
          const Value('the product name is not indicated at all'),
    ));
  }

  Future<String> sheetFor(String recordUuid) async {
    final file = await seizures.buildDocument(recordUuid, into: work);
    expect(file, isNotNull, reason: 'the sheet must still be produced');
    return _textOf(await file!.readAsBytes());
  }

  test('a raw seizure names the class the record holds', () async {
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-1',
            inspectedAt: when,
            updatedAt: when,
            productClass: const Value('Raw species sausage / wors'),
          ),
        );
    await seize('rawrmp', 'raw-1');
    expect(await sheetFor('raw-1'), _says('Raw species sausage / wors'));
  });

  test('a processed meat seizure names its class too', () async {
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: when,
          updatedAt: when,
          productClass:
              const Value('Comminuted, cured and heat treated products'),
        ));
    await seize('pmp', 'pmp-1', productName: 'Chicken Vienna');
    expect(await sheetFor('pmp-1'),
        _says('Comminuted, cured and heat treated products'));
  });

  test('a raw record whose class was never chosen is left blank, not N/A',
      () async {
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-2',
            inspectedAt: when,
            updatedAt: when,
          ),
        );
    await seize('rawrmp', 'raw-2');
    final text = await sheetFor('raw-2');
    expect(text, isNot(_says('N/A')),
        reason: 'the class applies to raw, it is simply not stated');
    expect(text, isNot(_says('Marking and labelling checked on site.')),
        reason: 'that sentence is a description, not a product class');
  });

  test('what the inspector typed themselves is never overwritten', () async {
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-3',
            inspectedAt: when,
            updatedAt: when,
            productClass: const Value('Raw species sausage / wors'),
          ),
        );
    await seizures.record(SeizuresCompanion.insert(
      clientUuid: 'seizure-raw-3',
      recordUuid: 'raw-3',
      recordKind: 'rawrmp',
      issuedAt: when,
      updatedAt: when,
      clientName: const Value('Herti Deli (Q Meats) /Essmor'),
      productName: const Value('Cheese Boerewors'),
      // Typed through "Edit seizure particulars".
      productClass: const Value('Boerewors, Grade A'),
      quantity: const Value('5 packs (2.106 kg)'),
    ));
    final text = await sheetFor('raw-3');
    expect(text, _says('Boerewors, Grade A'));
    expect(text, _says('5 packs (2.106 kg)'));
    expect(text, isNot(_says('Raw species sausage / wors')));
  });

  test('an egg seizure reads N/A: eggs have no class', () async {
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          inspectedAt: when,
          updatedAt: when,
        ));
    await seize('egg', 'egg-1', productName: 'Eggs');
    expect(await sheetFor('egg-1'), _says('N/A'));
  });

  test('a poultry seizure reads N/A: poultry is graded, not classed',
      () async {
    await db.into(db.poultryInspections).insert(
          PoultryInspectionsCompanion.insert(
            clientUuid: 'poultry-1',
            inspectedAt: when,
            updatedAt: when,
          ),
        );
    await seize('poultry', 'poultry-1', productName: 'Whole chicken');
    expect(await sheetFor('poultry-1'), _says('N/A'));
  });

  test('a poultry labelling seizure reads N/A too', () async {
    await seize('poultry_label', 'poultry-label-1',
        productName: 'Label/Container');
    expect(await sheetFor('poultry-label-1'), _says('N/A'));
  });

  test('a QUID seizure reads N/A as well', () async {
    await db.into(db.poultryQuidInspections).insert(
          PoultryQuidInspectionsCompanion.insert(
            clientUuid: 'quid-1',
            inspectedAt: when,
            updatedAt: when,
            isWaterChilled: const Value(true),
            isWholeCarcass: const Value(true),
            directionRequired: const Value(true),
          ),
        );
    await db.into(db.poultryQuidInjectors).insert(
          PoultryQuidInjectorsCompanion.insert(
            inspectionUuid: 'quid-1',
            name: const Value('Injector 1'),
            position: 1,
          ),
        );
    await seize('quid', 'quid-1', productName: 'Brined chicken');
    expect(await sheetFor('quid-1'), _says('N/A'));
  });

  test('an egg with a size and grade declared still reads N/A', () async {
    // The size and grade are not a class, and the Product class column is
    // not where they belong.
    await db.into(db.eggSizes).insert(EggSizesCompanion.insert(
        id: const Value(4),
        name: 'Large',
        minMassG: 51,
        maxMassG: const Value(59)));
    await db.into(db.eggGrades).insert(EggGradesCompanion.insert(
        id: const Value(1), name: 'Grade 1', rank: 1));
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-2',
          inspectedAt: when,
          updatedAt: when,
          declaredSizeId: const Value(4),
          declaredGradeId: const Value(1),
        ));
    await seize('egg', 'egg-2', productName: 'Eggs');
    final eggText = await sheetFor('egg-2');
    expect(eggText, _says('N/A'));
    expect(eggText, isNot(_says('Sold as Grade 1 Large')));
  });

  test('the quantity is only filled where the record actually holds one',
      () async {
    // Eggs and QUID are the only commodities that capture how much was
    // taken; the meat and poultry forms never ask, and the sample size
    // they do ask for is a different quantity (Cinga, 2026-10-26).
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-3',
          inspectedAt: when,
          updatedAt: when,
        ));
    await db.into(db.eggDirections).insert(EggDirectionsCompanion.insert(
          clientUuid: 'egg-3-rejection',
          inspectionUuid: const Value('egg-3'),
          issuedAt: when,
          updatedAt: when,
          quantityRemoved: const Value(24),
        ));
    await seize('egg', 'egg-3', productName: 'Eggs');
    expect(await sheetFor('egg-3'), _says('24'));
  });
}


// ---------------------------------------------------------------------------
// Reading the text back out of a finished PDF: the forms embed Lato as a
// subset, so the content streams hold glyph ids and the document cannot be
// searched directly. Each font carries a /ToUnicode CMap mapping those ids
// back to characters, which is what this walks.
// ---------------------------------------------------------------------------

Matcher _says(String sentence) => contains(_squash(sentence));

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

String _textOf(List<int> pdf) {
  final streams = _inflatedStreams(pdf);
  final toUnicode = <int, String>{};
  for (final s in streams) {
    if (s.contains('beginbfchar') || s.contains('beginbfrange')) {
      _readCMap(s, toUnicode);
    }
  }
  final out = StringBuffer();
  for (final s in streams) {
    if (s.contains('beginbfchar') || s.contains('beginbfrange')) continue;
    if (!s.contains('Tj') && !s.contains('TJ')) continue;
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(s)) {
      final hex = m.group(1)!;
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        out.write(toUnicode[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '');
      }
    }
  }
  return out.toString();
}

void _readCMap(String cmap, Map<int, String> into) {
  for (final block
      in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(cmap)) {
    for (final p in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
        .allMatches(block.group(1)!)) {
      into[int.parse(p.group(1)!, radix: 16)] = _utf16(p.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
      .allMatches(cmap)) {
    for (final r
        in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
            .allMatches(block.group(1)!)) {
      final lo = int.parse(r.group(1)!, radix: 16);
      final hi = int.parse(r.group(2)!, radix: 16);
      final dst = int.parse(r.group(3)!, radix: 16);
      for (var c = lo; c <= hi && c - lo < 0x10000; c++) {
        into[c] = String.fromCharCode(dst + (c - lo));
      }
    }
  }
}

String _utf16(String hex) {
  final units = <int>[];
  for (var i = 0; i + 4 <= hex.length; i += 4) {
    units.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  return String.fromCharCodes(units);
}

List<String> _inflatedStreams(List<int> pdf) {
  final out = <String>[];
  for (var i = 0; i + 6 < pdf.length; i++) {
    if (pdf[i] != 0x73 ||
        pdf[i + 1] != 0x74 ||
        pdf[i + 2] != 0x72 ||
        pdf[i + 3] != 0x65 ||
        pdf[i + 4] != 0x61 ||
        pdf[i + 5] != 0x6D) {
      continue;
    }
    var start = i + 6;
    while (start < pdf.length && (pdf[start] == 13 || pdf[start] == 10)) {
      start++;
    }
    final end = _indexOf(pdf, 'endstream', start);
    if (end < 0) continue;
    try {
      out.add(String.fromCharCodes(zlib.decode(pdf.sublist(start, end))));
    } catch (_) {
      // Not a Flate stream (an embedded JPEG, say) — nothing to read.
    }
  }
  return out;
}

int _indexOf(List<int> haystack, String needle, int from) {
  final n = needle.codeUnits;
  outer:
  for (var i = from; i <= haystack.length - n.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return i;
  }
  return -1;
}
