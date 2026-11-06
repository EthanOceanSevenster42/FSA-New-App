import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The size an egg consignment is sold as has to reach the record.
///
/// Every egg member filed as a bare "Eggs", so on APS, in the document
/// filename and in the folder the documents land in, an Extra Large check
/// and a Medium one at the same shop were indistinguishable — and the
/// labelling report showed only the tray count, "30" (Ethan, 2026-10-23).
void main() {
  group('tray count', () {
    test('drops the word Pack, which adds nothing beside Eggs', () {
      expect(VisitRepository.trayCount('30-Pack'), '30');
      expect(VisitRepository.trayCount('12-Pack'), '12');
      expect(VisitRepository.trayCount('6 Pack'), '6');
      expect(VisitRepository.trayCount('18-pack'), '18');
    });

    test('a tray named without Pack is left alone', () {
      expect(VisitRepository.trayCount('30'), '30');
      expect(VisitRepository.trayCount('Loose'), 'Loose');
    });

    test('nothing in, nothing out', () {
      expect(VisitRepository.trayCount(''), '');
      expect(VisitRepository.trayCount('   '), '');
    });
  });

  group('the product name the record carries', () {
    // The join the repository performs once it has the size and tray.
    String productName(String size, String tray) =>
        [size, 'Eggs', VisitRepository.trayCount(tray)]
            .where((p) => p.isNotEmpty)
            .join(' ');

    test('reads as the inspector would say it', () {
      expect(productName('Extra Large', '30-Pack'), 'Extra Large Eggs 30');
      expect(productName('Medium', '18-Pack'), 'Medium Eggs 18');
      expect(productName('Jumbo', '6 Pack'), 'Jumbo Eggs 6');
    });

    test('degrades sensibly when a part is missing', () {
      expect(productName('Large', ''), 'Large Eggs');
      expect(productName('', '30-Pack'), 'Eggs 30');
      expect(productName('', ''), 'Eggs');
    });
  });
}
