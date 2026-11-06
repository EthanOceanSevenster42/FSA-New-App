import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// The non-conformance comments belong on the egg rejection, not only on
/// the checklist (Cinga, 2026-10-26).
///
/// The inspector writes one note about what was wrong with the
/// consignment. It reached the Egg Labelling Checklist and was dropped
/// from the rejection — the document actually served on the client — so
/// the client was told which requirement failed but not what the
/// inspector had recorded about it. Raw, PMP and poultry have all put
/// their comments in ACTIONS AND REMARK from the start; eggs was the one
/// commodity that did not.
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;
  late Directory work;

  const comment =
      'Consignment held in the cold room pending relabelling by the producer.';

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
    work = await Directory.systemTemp.createTemp('egg-rejection-comments-');
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
  });

  tearDown(() async {
    await db.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  const uuid = 'cinga-egg';

  Future<void> seed({
    String comments = '',
    String additionalRemarks = '',
  }) async {
    final when = DateTime(2026, 10, 26, 9, 0);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: uuid,
          inspectedAt: when,
          updatedAt: when,
          inspectorUsername: const Value('inspector1'),
          facilityName: const Value('Nulaid Retail'),
          clientName: const Value('Nulaid Retail'),
          producerSupplier: const Value('Nulaid'),
          nonConformanceComments: Value(comments),
          failedRequirementIds: const Value('1'),
        ));
    await eggs.saveDirection(EggDirectionsCompanion.insert(
      clientUuid: '$uuid-rejection',
      inspectionUuid: const Value(uuid),
      issuedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('inspector1'),
      status: const Value('completed'),
      directionNumber: const Value('PR-IND-IND-9001-001'),
      labellingPart: const Value(true),
      labelCorrectBy: Value(DateTime(2026, 11, 6)),
      clientName: const Value('Nulaid Retail'),
      producerSupplier: const Value('Nulaid'),
      additionalRemarks: Value(additionalRemarks),
    ));
  }

  test('the comments the inspector wrote are on the rejection served',
      () async {
    await seed(comments: comment);
    final out = await eggs.buildDirection(uuid, into: work);
    expect(out, isNotNull, reason: 'the rejection must still be produced');

    expect(_textOf(await out!.readAsBytes()), _says(comment),
        reason: 'ACTIONS AND REMARK must carry the non-conformance '
            'comments, as it does on raw, PMP and poultry');
  });

  test('and still on the labelling checklist, which already had them',
      () async {
    await seed(comments: comment);
    // The checklist prints the Agency's requirement rows, so it needs
    // some. Two are enough; the bundled reference carries 5,009 suppliers
    // besides and inserting those row by row takes minutes.
    for (final (id, text) in [
      (1, 'Product name'),
      (2, 'Date of minimum durability'),
    ]) {
      await db.into(db.eggRequirements).insert(EggRequirementsCompanion.insert(
            id: Value(id),
            kind: 'label_pack',
            description: text,
            sortOrder: Value(id),
          ));
    }
    final out = await eggs.buildLabellingChecklist(uuid, into: work);
    expect(out, isNotNull);
    expect(_textOf(await out!.readAsBytes()), _says(comment));
  });

  test('a rejection with no comments reads as it always did', () async {
    await seed(additionalRemarks: 'Relabel before re-offering for sale.');
    final out = await eggs.buildDirection(uuid, into: work);
    final text = _textOf(await out!.readAsBytes());
    expect(text, _says('Relabel before re-offering for sale.'));
    expect(text, isNot(_says(comment)));
  });

  test('the typed remark and the comment both appear, remark first',
      () async {
    await seed(
        comments: comment,
        additionalRemarks: 'Relabel before re-offering for sale.');
    final text = _squash(_textOf(
        await (await eggs.buildDirection(uuid, into: work))!.readAsBytes()));
    final remarkAt = text.indexOf(_squash('Relabel before re-offering for '
        'sale.'));
    final commentAt = text.indexOf(_squash(comment));
    expect(remarkAt, greaterThan(-1));
    expect(commentAt, greaterThan(-1));
    expect(commentAt, greaterThan(remarkAt),
        reason: 'the comments are added after the remarks, as on the '
            'other commodities');
  });
}

/// The document says this sentence.
///
/// The forms place each word with its own positioning operator rather than
/// writing space glyphs, so the decoded text comes back without spaces.
/// Both sides are squashed so the assertion can still be written as the
/// sentence a reader would see on the sheet.
Matcher _says(String sentence) => contains(_squash(sentence));

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

// ---------------------------------------------------------------------------
// Reading the text back out of a finished PDF.
//
// The forms embed Lato as a subset, so the content streams hold glyph ids
// rather than letters and the document cannot simply be searched. Each
// font also carries a /ToUnicode CMap mapping those ids back to
// characters, which is what this walks: inflate every stream, build the
// map from the CMaps, then decode the hex strings in the content streams
// through it.
// ---------------------------------------------------------------------------

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
      for (var i = 0; i + 3 < hex.length + 1; i += 4) {
        if (i + 4 > hex.length) break;
        final code = int.parse(hex.substring(i, i + 4), radix: 16);
        out.write(toUnicode[code] ?? '');
      }
    }
  }
  return out.toString();
}

/// `<src> <dst>` pairs and `<lo> <hi> <dst>` ranges out of a ToUnicode CMap.
void _readCMap(String cmap, Map<int, String> into) {
  for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true)
      .allMatches(cmap)) {
    final pairs =
        RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(block.group(1)!);
    for (final p in pairs) {
      into[int.parse(p.group(1)!, radix: 16)] = _utf16(p.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
      .allMatches(cmap)) {
    final rows = RegExp(
            r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
        .allMatches(block.group(1)!);
    for (final r in rows) {
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
