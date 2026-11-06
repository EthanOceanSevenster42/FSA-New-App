import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/domain/facility_address.dart';

/// The facility address is one box written to a fixed order.
///
/// APS holds the address in pieces and the bridge fills them by splitting
/// the handset's box on its commas. While the box was written freely, that
/// split put whatever sat in the second position into the Town field, and
/// bare postcodes landed there — nothing lost, but nothing that could be
/// grouped or trusted by town either.
///
/// Pinning the tail fixes it: province, then the four-digit code. These
/// hold that rule, and the leniencies that keep it usable at a counter.
void main() {
  group('reading an address', () {
    const good = '12 Mill Road, Epping, Cape Town, Western Cape, 7460';

    test('the example in the hint is itself well formed', () {
      expect(FacilityAddress.isWellFormed(FacilityAddress.example), isTrue,
          reason: 'inspectors copy the example; it has to pass');
    });

    test('a properly written address is accepted whole', () {
      expect(FacilityAddress.isWellFormed(good), isTrue);
      expect(FacilityAddress.problems(good), isEmpty);
      expect(FacilityAddress.provinceOf(good), 'Western Cape');
      expect(FacilityAddress.postalCodeOf(good), '7460');
    });

    test('a suburb is not demanded', () {
      // A farm or a depot has no suburb, and requiring one only invites a
      // filler word into the field.
      const farm = 'Plot 44 Rietfontein Road, Brits, North West, 0250';
      expect(FacilityAddress.isWellFormed(farm), isTrue);
    });

    test('the four parts are the minimum', () {
      expect(FacilityAddress.problems('Cape Town, Western Cape, 7460'),
          contains('Give the street and the town before the province.'));
    });
  });

  group('what it refuses', () {
    test('no postal code', () {
      expect(
        FacilityAddress.problems('12 Mill Road, Epping, Cape Town, '
            'Western Cape'),
        contains('End with the four-digit postal code.'),
      );
    });

    test('a postal code that is not four digits', () {
      for (final code in ['746', '74600', '7460A']) {
        expect(
          FacilityAddress.problems('12 Mill Road, Epping, Cape Town, '
              'Western Cape, $code'),
          contains('End with the four-digit postal code.'),
          reason: '$code is not a South African postal code',
        );
      }
    });

    test('no province', () {
      expect(
        FacilityAddress.problems('12 Mill Road, Epping, Cape Town, 7460'),
        contains('Name the province before the postal code.'),
      );
    });

    test('the province has to come before the code, not after', () {
      // The order is the whole point; a province at the end means the
      // bridge would read the code as the province.
      expect(
        FacilityAddress.isWellFormed('12 Mill Road, Epping, Cape Town, '
            '7460, Western Cape'),
        isFalse,
      );
    });

    test('one run-on line with no commas', () {
      expect(
        FacilityAddress.problems('12 Mill Road Epping Cape Town 7460'),
        isNotEmpty,
      );
    });

    test('a blank box is not scolded about its format', () {
      // Whether an address is required at all is the form's question. A box
      // nobody has typed in yet must not show an error.
      expect(FacilityAddress.problems(''), isEmpty);
      expect(FacilityAddress.problems('   '), isEmpty);
      expect(FacilityAddress.isWellFormed(''), isFalse,
          reason: 'blank is not well formed either, just not complained at');
    });
  });

  group('the spellings it forgives', () {
    test('every province is recognised as the Department spells it', () {
      for (final province in FacilityAddress.provinces) {
        expect(
          FacilityAddress.provinceOf('1 Main Road, Town, $province, 1234'),
          province,
        );
      }
    });

    test('case does not matter', () {
      expect(
        FacilityAddress.provinceOf('1 Main Road, Town, western cape, 1234'),
        'Western Cape',
      );
    });

    test('the short forms inspectors actually type are taken', () {
      const seen = {
        'KZN': 'KwaZulu-Natal',
        'KwaZulu Natal': 'KwaZulu-Natal',
        'North-West': 'North West',
        'GP': 'Gauteng',
        'WC': 'Western Cape',
      };
      seen.forEach((typed, kept) {
        expect(FacilityAddress.provinceOf('1 Main Road, Town, $typed, 1234'),
            kept,
            reason: '$typed names a real province');
      });
    });
  });

  group('tidying', () {
    test('spacing and stray commas are evened out', () {
      expect(
        FacilityAddress.tidy('12  Mill Road ,,Epping,Cape   Town , '
            'Western Cape , 7460 '),
        '12 Mill Road, Epping, Cape Town, Western Cape, 7460',
      );
    });

    test('a forgiven province is written back the long way', () {
      expect(
        FacilityAddress.tidy('1 Main Road, Durban, kzn, 4001'),
        '1 Main Road, Durban, KwaZulu-Natal, 4001',
      );
    });

    test('a street name keeps its own capitals', () {
      // "de Waal" is how the street is spelled; tidying is not a licence to
      // re-case what somebody wrote.
      expect(
        FacilityAddress.tidy('2 de Waal Drive, Vredehoek, Cape Town, '
            'Western Cape, 8001'),
        startsWith('2 de Waal Drive'),
      );
    });

    test('tidying an empty box gives an empty box', () {
      expect(FacilityAddress.tidy('  ,, , '), '');
    });

    test('tidying never breaks an address that was already good', () {
      const good = '12 Mill Road, Epping, Cape Town, Western Cape, 7460';
      expect(FacilityAddress.tidy(good), good);
      expect(FacilityAddress.isWellFormed(FacilityAddress.tidy(good)), isTrue);
    });
  });
}
