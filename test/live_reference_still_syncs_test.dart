// The reference feed a handset in the field actually receives today.
//
// `live_eggs.json` / `live_poultry.json` were pulled from the inspector
// backend on 2026-10-20, after the lettering-height and Reg. 3(1) changes
// went out. The question this answers is not "does the new column work" —
// other tests cover that — but "does a handset that syncs this come out of
// it whole": the right number of rows, nothing blanked, and the two
// simulated older feeds (one with no `min_lettering_height` key at all, as
// a build from before today would have been served) handled without loss.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the live egg feed lands whole, heights and all', () async {
    final repo = EggsRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repo.writeReferenceForTest(_load('live_eggs.json'));

    final rows = await db.select(db.eggRequirements).get();
    final label = rows.where((r) => r.kind.startsWith('label')).toList();
    expect(label, hasLength(20), reason: 'ten container, ten outer');
    // Nothing the older feed carried is lost.
    expect(label.every((r) => r.description.isNotEmpty), isTrue);
    expect(label.every((r) => r.regulation.isNotEmpty), isTrue);
    // Table 1: packer is 1 mm on the container, 5 mm on the outer.
    String heightOf(String kind, String cite) => label
        .firstWhere((r) =>
            r.kind == kind && r.regulation.replaceAll(' ', '').contains(cite))
        .minLetteringHeight;
    expect(heightOf('label_pack', '8(1)(d)'), '1');
    expect(heightOf('label_outer', '8(1)(d)'), '5');
    expect(heightOf('label_pack', '8(1)(g)'), '3');
    // Restricted particulars has no line in Table 1 and stays blank.
    expect(heightOf('label_pack', '[Reg.13]'), '');
  });

  test('a feed from before the column leaves the stored height alone',
      () async {
    final repo = EggsRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repo.writeReferenceForTest(_load('live_eggs.json'));

    // The same feed as an older backend served it: no such key at all.
    final older = _load('live_eggs.json');
    final data = older['data'] as Map<String, dynamic>;
    for (final row in (data['requirements'] as List).cast<Map<String, dynamic>>()) {
      row.remove('min_lettering_height');
    }
    // ignore: invalid_use_of_visible_for_testing_member
    await repo.writeReferenceForTest(older);

    final again = await db.select(db.eggRequirements).get();
    final packer = again.firstWhere((r) =>
        r.kind == 'label_pack' &&
        r.regulation.replaceAll(' ', '').contains('8(1)(d)'));
    expect(packer.minLetteringHeight, '1',
        reason: 'an upsert replaces the row; an absent field must not wipe it');
    expect(again.where((r) => r.kind.startsWith('label')), hasLength(20));
  });

  test('the live poultry feed carries Reg. 3(1) on every grading row',
      () async {
    final repo =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repo.writeReferenceForTest(_load('live_poultry.json'));

    final items = await db.select(db.poultryChecklistItems).get();
    final grading = items.where((i) => i.kind == 'grading').toList();
    expect(grading, hasLength(13));
    expect(grading.every((i) => i.regulationReference == '3(1)'), isTrue);
    // The rows that already cited one are untouched, and the lettering
    // heights the labelling sheet prints are still there.
    final portion = items.where((i) => i.kind == 'portion');
    expect(portion.every((i) => i.regulationReference.startsWith('5(')), isTrue);
    final inner = items.where((i) => i.kind == 'label_inner');
    expect(inner.any((i) => i.minLetteringHeight == '4.0'), isTrue);
  });
}
