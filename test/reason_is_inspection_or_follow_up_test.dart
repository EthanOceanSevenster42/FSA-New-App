import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/visits/domain/inspection_reason_match.dart';

/// Reason for Inspection is Inspection or Follow Up — nothing else, as the
/// original app offers it (Ethan, 2026-09-24).
void main() {
  test('only the two are offered', () {
    expect(InspectionReasonMatch.offered, ['Inspection', 'Follow Up']);
  });

  test('every spelling of follow-up counts, a complaint does not', () {
    expect(InspectionReasonMatch.isOffered('Inspection'), isTrue);
    expect(InspectionReasonMatch.isOffered('Follow Up'), isTrue);
    expect(InspectionReasonMatch.isOffered('Follow-up Inspection'), isTrue);
    expect(InspectionReasonMatch.isOffered('Complaint'), isFalse);
  });

  test('every commodity still has a row for both answers', () {
    for (final name in ['eggs', 'poultry', 'rawrmp', 'pmp']) {
      final bundle = jsonDecode(
              File('assets/reference/${name}_reference.json').readAsStringSync())
          as Map<String, dynamic>;
      final reasons = [
        for (final r in (bundle['data'] as Map)['inspection_reasons'] as List)
          (r as Map)['name'] as String,
      ];
      for (final offered in InspectionReasonMatch.offered) {
        expect(InspectionReasonMatch.indexOf(offered, reasons), isNotNull,
            reason: '$name has no row for $offered');
      }
    }
  });
}
