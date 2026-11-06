import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/poultry/domain/quid_determination.dart';
import 'package:fsa_app/features/poultry/domain/quid_flow.dart';

/// An injector over its QUID limit has to end in a rejection.
///
/// Kutlwano weighed four sets at Country fair product on 29 October 2026.
/// The injectors were set to 15%, the product was cut portions. Three of the
/// four averaged over the 16.5% then allowed (16.777, 17.425 and 18.067), all
/// finished on the first round, none asked for a second set, and none raised
/// a rejection.
///
/// The cut-portion tolerance has since gone to 2.5% (Ethan, 2026-11-05), so
/// the limit on a 15% injector is 17.5%: of her four sets only 18.067 is
/// over it. Her real figures are held here so the rule — over the limit
/// means a rejection — cannot quietly come undone again.
void main() {
  // Her four sets, as the handset recorded them.
  const countryFair = <String, List<String>>{
    'Injector 4, first set': [
      '14.532', '10.911', '17.861', '18.660', '19.954'    // avg 16.384
    ],
    'Injector 2, first set': [
      '12.415', '17.060', '16.742', '21.303', '22.813'    // avg 18.067
    ],
    'Injector 4, second set': [
      '19.575', '4.798', '22.525', '19.870', '17.119'     // avg 16.777
    ],
    'Injector 2, second set': [
      '17.714', '18.731', '13.603', '17.895', '19.181'    // avg 17.425
    ],
  };

  QuidInjectorVerdict verdictFor(List<String> carcasses) => quidVerdicts(
        injectors: const [
          (position: 1, name: 'Injector 4', quidPercent: '15'),
        ],
        weighings: [
          for (final percent in carcasses)
            (assignedInjector: 1, quidPercent: percent),
        ],
        isWholeCarcass: false,
      ).single;

  test('the limit is the set figure plus the cut-portion tolerance', () {
    expect(verdictFor(countryFair['Injector 4, first set']!).limitPercent,
        15 + quidCutPortionTolerance);
    expect(quidCutPortionTolerance, 2.5);
    expect(verdictFor(countryFair['Injector 4, first set']!).limitPercent,
        17.5);
  });

  test('the sets inside the 17.5% limit pass', () {
    for (final name in const [
      'Injector 4, first set',
      'Injector 4, second set',
      'Injector 2, second set',
    ]) {
      final v = verdictFor(countryFair[name]!);
      expect(v.passes, isTrue,
          reason: '$name averaged ${v.averagePercent}%, under the 17.5 allowed');
    }
  });

  test('the set over the limit fails', () {
    final v = verdictFor(countryFair['Injector 2, first set']!);
    expect(v.averagePercent, '18.067');
    expect(v.passes, isFalse,
        reason: '18.067 is over the 17.5 allowed');
  });

  test('a first failure asks for another set, the last one rejects', () {
    expect(quidOnFailure(1), QuidFailureStep.repeat);
    expect(quidOnFailure(quidMaxIterations), QuidFailureStep.reject);
  });

  test('fewer than five carcasses is not judged either way', () {
    final v = verdictFor(const ['19.954', '18.660', '17.861']);
    expect(v.passes, isNull,
        reason: 'three carcasses cannot carry a verdict, and must not be '
            'read as a pass');
  });
}
