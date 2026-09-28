import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';

/// How many photographs a poultry label or QUID record needs.
///
/// The original counts to two on both screens and will not let the checklist
/// be completed until they are on the record — `[n / 2]` and
/// `switchIsLabelandPackListComplete` on the label page, `MinDirectionPhotos`
/// on the QUID page. One more than that is allowed and optional.
void main() {
  test('two are required, three are allowed', () {
    expect(PoultryRules.requiredPhotos, 2);
    expect(PoultryRules.maxPhotos, 3);
    expect(PoultryRules.maxPhotos, PoultryRules.requiredPhotos + 1);
  });

  test('a record owes photographs until it has the minimum', () {
    expect(PoultryRules.photographsOutstanding(0), isTrue);
    expect(PoultryRules.photographsOutstanding(1), isTrue);
    expect(PoultryRules.photographsOutstanding(2), isFalse);
    // The third is extra, not a new obligation.
    expect(PoultryRules.photographsOutstanding(3), isFalse);
  });
}
