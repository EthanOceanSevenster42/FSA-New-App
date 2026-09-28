import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The upgrade blocks must run oldest-first: a later block may ALTER a table
/// an earlier block CREATEs, and a handset upgrading across many versions
/// executes them all in source order. A pre-visits database crashed on
/// `ALTER TABLE store_visits` because the new blocks sat above the one that
/// created the table.
void main() {
  test('migration blocks are in ascending order', () {
    final source = File('lib/core/data/local_database.dart').readAsStringSync();
    final begin = source.indexOf('onUpgrade:');
    expect(begin, greaterThan(0));
    final matches = RegExp(r'if \(from < (\d+)\)')
        .allMatches(source.substring(begin))
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(matches.length, greaterThan(30), reason: 'the blocks were found');
    final sorted = [...matches]..sort();
    expect(matches, sorted,
        reason: 'every "if (from < n)" block must come after the ones with '
            'smaller n, so creates precede the alters that touch them');
  });
}
