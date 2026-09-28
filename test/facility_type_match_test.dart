import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/visits/domain/facility_type_match.dart';

/// The facility type is chosen once at the door and each commodity finds its
/// own row for it, spelling differences and all.
void main() {
  const eggs = ['Retailer/Distr. Center', 'Import', 'Producer', 'Pack House'];
  const poultry = [
    'Retailer/Shops/Distr. Centers', 'Import', 'Producer', 'Pack House',
    'Abattoir', 'Repacker',
  ];
  const raw = [
    'Retailer/Shops/Distr. Centers', 'Import', 'Producer', 'Pack House',
    'Butchery',
  ];

  test('the two retailer spellings are the same kind of premises', () {
    expect(FacilityTypeMatch.indexOf('Retailer/Shops/Distr. Centers', eggs), 0);
    expect(FacilityTypeMatch.indexOf('Retailer/Distr. Center', poultry), 0);
  });

  test('a plain match is found regardless of case and punctuation', () {
    expect(FacilityTypeMatch.indexOf('pack house', raw), 3);
    expect(FacilityTypeMatch.indexOf('PACK-HOUSE', eggs), 3);
  });

  test('a kind a commodity does not have is not forced onto it', () {
    expect(FacilityTypeMatch.indexOf('Butchery', eggs), isNull,
        reason: 'the egg form must ask instead');
    expect(FacilityTypeMatch.indexOf('Butchery', raw), 4);
    expect(FacilityTypeMatch.indexOf('', raw), isNull);
  });

  test('the door-side list has each kind once, in first-seen order', () {
    expect(FacilityTypeMatch.union([eggs, poultry, raw]), [
      'Retailer/Distr. Center', 'Import', 'Producer', 'Pack House',
      'Abattoir', 'Repacker', 'Butchery',
    ]);
  });
}
