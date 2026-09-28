import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The grading form against the screen it replaces.
///
/// The captions are not decoration. An inspector fills this in beside the
/// original's paper output and, during the changeover, beside the original app
/// itself; a field called something else is a field they have to stop and
/// translate. Retyping them is how they drift, so this reads the original's
/// XAML and checks the wording is still there.
///
/// Skips rather than fails when the legacy source is not beside the app — it
/// is a reference checkout, not a build dependency.
void main() {
  final legacy = File(
    '../original/EInspectorFood/View/DetailViews/'
    'NewPoultryGradingInspectionPage.xaml',
  );
  final form = File(
    'lib/features/poultry/presentation/poultry_inspection_form.dart',
  );

  /// Every caption the original attaches to an input, keyed by the input name.
  ///
  /// The caption is the *nearest* preceding label. Allowing an element to sit
  /// between the two picks up the row above instead — which is how this test
  /// first claimed the form was missing "Reg." when the field is captioned
  /// "Name or Trading Name of New Facility", the label actually next to it.
  Map<String, String> captions(String xaml) {
    final element = RegExp(
      r'<(Label|Entry|Picker|Editor|DatePicker)([^>]*)>',
      dotAll: true,
    );
    final text = RegExp(r'Text="([^"]*)"');
    final name = RegExp(r'x:Name="([A-Za-z0-9_]+)"');

    final out = <String, String>{};
    String? pending;
    for (final m in element.allMatches(xaml)) {
      final attributes = m.group(2)!;
      if (m.group(1) == 'Label') {
        pending = text.firstMatch(attributes)?.group(1)?.trim();
        continue;
      }
      final input = name.firstMatch(attributes)?.group(1);
      if (input != null && pending != null) out[input] = pending;
      pending = null;
    }
    return out;
  }

  test('every field carries the original\'s caption', () {
    if (!legacy.existsSync()) {
      markTestSkipped('legacy source not checked out beside the app');
      return;
    }

    final source = form.readAsStringSync();
    final original = captions(legacy.readAsStringSync());

    // The inputs this screen reproduces, mapped to the original's name for
    // them. Anything absent here is a field the form does not yet carry, and
    // saying so out loud is the point — see the list at the end.
    const reproduced = {
      'InspectionReasonPicker',
      'InspectionLocationPicker',
      'entryFacilityName',
      'entryProducerNewFacility',
      'editorNewFacilityAddress',
      'entryCompanyRegNumber',
      'entryNewContactPerson',
      'entryNewContactPersonEmail',
      'PickerPoultryType',
      'PickerPortionType',
      'PickerClassDesignation',
      'PickerAlternativeClassDesignation',
      'PickerGrade',
      'entryProductDetails',
      'entrySampleNumber',
      'pickerDirectionRemark',
      'editorDirectionRemarks',
      'entryManagerName',
      'entryManagerEmail',
      'entryClientEmail1',
      'entryClientEmail12',
      'editorInspectionComments',
    };

    // Where the FSA asked for different words than the original's, the
    // wording they asked for is the one the form must carry. Listing them
    // here keeps the divergence deliberate and visible rather than letting
    // the parity check quietly stop covering the field.
    const reworded = {
      // "Direction" in the original; the FSA calls this a rejection.
      'editorDirectionComments': 'Comments/Remarks on Rejection',
      // A cellphone is as good as a landline for reaching the facility
      // (Ethan, 2026-09-24).
      'entryNewFacilityTelephone':
          'Facility Primary Contact Telephone / Cellphone Number',
    };
    for (final entry in reworded.entries) {
      expect(
        original[entry.key],
        isNotNull,
        reason: '${entry.key} is no longer in the original XAML',
      );
      expect(
        source.contains("'${entry.value}'"),
        isTrue,
        reason: '${entry.key} should read "${entry.value}"',
      );
    }

    final missing = <String>[];
    for (final name in reproduced) {
      final caption = original[name];
      expect(
        caption,
        isNotNull,
        reason: '$name is no longer in the original XAML — the extractor and '
            'this list disagree about what that screen contains',
      );
      if (!source.contains("'$caption'")) {
        missing.add('$name -> "$caption"');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'captions absent from the form:\n  ${missing.join('\n  ')}',
    );
  });

  test('the original\'s own spelling is preserved', () {
    if (!legacy.existsSync()) {
      markTestSkipped('legacy source not checked out beside the app');
      return;
    }

    final source = form.readAsStringSync();

    // "Classifcation" is the original's spelling of its own section heading.
    // Correcting it would be the one change an inspector actually notices,
    // and would leave the two systems reading differently.
    expect(legacy.readAsStringSync(), contains('Classifcation'));
    expect(source, contains('Classifcation and Grading Checklist'));
  });

  test('the signature refusal keeps the original\'s caption', () {
    // `switchNoClientSignaturePresent` is not on the form itself: the control
    // lives in the shared evidence section beside the signature blocks, so
    // there is one tick-box rather than two that can disagree. The wording an
    // inspector reads is still the original's.
    final evidence = File(
      'lib/features/poultry/presentation/poultry_evidence_section.dart',
    ).readAsStringSync();

    expect(evidence, contains('No Client Signature is available'));
  });
}
