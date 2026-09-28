@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// What a brand-new handset ends up holding after one sync.
///
/// Walks the real path in order — bundle first, then the network — and
/// counts what is actually in each table afterwards, so "not everything came
/// through" can be pinned to a table rather than guessed at.
///
///     FSA_LIVE_BASE_URL=http://10.0.0.203:8010 \
///     flutter test test/live_reference_counts_test.dart --tags live
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs an HttpOverrides that answers every
  // request with a 400 and never touches the network. This suite is
  // deliberately the opposite: it talks to a real server.
  HttpOverrides.global = null;

  final baseUrl = Platform.environment['FSA_LIVE_BASE_URL'];
  if (baseUrl == null) {
    test('reference counts', () {}, skip: 'FSA_LIVE_BASE_URL not set.');
    return;
  }

  test('a fresh handset ends up with every reference row', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final eggs = EggsRepository(database: db, baseUrl: baseUrl);

    Future<Map<String, int>> counts() async {
      Future<int> n(String table) async => (await db
              .customSelect('SELECT COUNT(*) AS c FROM $table')
              .getSingle())
          .read<int>('c');
      return {
        'clients': await n('egg_clients'),
        'facilities': await n('egg_facilities'),
        'suppliers': await n('egg_suppliers'),
        'sizes': await n('egg_sizes'),
        'grades': await n('egg_grades'),
        'tray_sizes': await n('egg_tray_sizes'),
        'facility_types': await n('egg_facility_types'),
        'inspection_reasons': await n('egg_inspection_reasons'),
        'requirements': await n('egg_requirements'),
        'deviations': await n('egg_deviations'),
        'deviation_tolerances': await n('egg_deviation_tolerances'),
        'restricted_particulars': await n('egg_restricted_particulars'),
        'direction_remarks': await n('egg_direction_remarks'),
      };
    }

    // 1. The bundle, exactly as the first launch loads it.
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(jsonDecode(
            await File('assets/reference/eggs_reference.json').readAsString())
        as Map<String, dynamic>);
    final afterBundle = await counts();
    stdout.writeln('after the bundle:');
    afterBundle.forEach((k, v) => stdout.writeln('  ${k.padRight(24)}$v'));
    stdout.writeln('  cursor: ${await db.readSyncState(EggsRepository.cursorKey)}');

    // 2. The sync the inspector taps.
    final watch = Stopwatch()..start();
    final written = await eggs.syncReference();
    watch.stop();
    stdout.writeln('\nsync wrote $written rows in ${watch.elapsed.inSeconds}s');
    final afterSync = await counts();
    stdout.writeln('after the sync:');
    afterSync.forEach((k, v) => stdout.writeln('  ${k.padRight(24)}$v'));
    stdout.writeln('  cursor: ${await db.readSyncState(EggsRepository.cursorKey)}');

    // 3. What the pickers themselves would show — active rows only.
    stdout.writeln('\nwhat the pickers show:');
    stdout.writeln('  suppliers      ${(await eggs.suppliers()).length}');
    stdout.writeln('  clients        ${(await eggs.clients()).length}');
    stdout.writeln('  facilities     ${(await eggs.facilities()).length}');
    stdout.writeln('  facility types ${(await eggs.facilityTypes()).length}');
    stdout.writeln('  reasons        ${(await eggs.reasons()).length}');
    stdout.writeln('  tray sizes     ${(await eggs.traySizes()).length}');
    stdout.writeln('  grades         ${(await eggs.grades()).length}');

    // 4. Against what the server actually holds.
    final server = jsonDecode((await HttpClient()
                .getUrl(Uri.parse('$baseUrl/api/eggs/reference/'))
                .then((r) => r.close())
                .then((r) => r.transform(utf8.decoder).join())))
        as Map<String, dynamic>;
    final serverCounts = (server['counts'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    stdout.writeln('\nserver holds:');
    serverCounts.forEach((k, v) => stdout.writeln('  ${k.padRight(24)}$v'));

    final short = <String>[
      for (final entry in serverCounts.entries)
        if (afterSync.containsKey(entry.key) &&
            afterSync[entry.key]! < entry.value)
          '${entry.key}: ${afterSync[entry.key]} of ${entry.value}',
    ];
    await db.close();
    expect(short, isEmpty, reason: 'rows the handset did not receive: $short');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
