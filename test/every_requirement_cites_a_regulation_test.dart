import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every checklist row the app ships cites the regulation it enforces.
///
/// Four egg labelling rows carried "XXX", "XXXX" or nothing, and the handset
/// printed them as they were — on the checklist, on the labelling sheet and
/// on the rejection notice the client is handed. A rejection that cites
/// "XXX" is not one the office can defend, so a placeholder anywhere in the
/// bundle fails the build rather than reaching a tablet.
void main() {
  Future<Map<String, dynamic>> bundle(String name) async =>
      (jsonDecode(await File('assets/reference/$name').readAsString())
          as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  bool placeholder(String? value) =>
      value == null ||
      value.trim().isEmpty ||
      RegExp(r'x{2,}', caseSensitive: false).hasMatch(value);

  test('eggs', () async {
    final rows = (await bundle('eggs_reference.json'))['requirements']
        as List<dynamic>;
    final bad = [
      for (final r in rows.cast<Map<String, dynamic>>())
        if (placeholder(r['regulation'] as String?))
          '${r['id']} ${r['description']}: "${r['regulation']}"',
    ];
    expect(bad, isEmpty, reason: 'egg rows without a citation: $bad');
  });

  test('poultry, raw and processed meat', () async {
    for (final (file, table, field) in [
      ('poultry_reference.json', 'checklist_items', 'regulation_reference'),
      ('rawrmp_reference.json', 'checklist_items', 'regulation_reference'),
      ('pmp_reference.json', 'checklist_items', 'regulation_reference'),
    ]) {
      final rows = (await bundle(file))[table] as List<dynamic>;
      final bad = [
        for (final r in rows.cast<Map<String, dynamic>>())
          // Only a placeholder is a defect here: some meat rows cite nothing
          // by design, and an empty citation reads as empty on the sheet.
          if (RegExp(r'x{2,}', caseSensitive: false)
              .hasMatch((r[field] as String?) ?? ''))
            '${r['id']} ${r['description']}: "${r[field]}"',
      ];
      expect(bad, isEmpty, reason: '$file rows citing a placeholder: $bad');
    }
  });
}
