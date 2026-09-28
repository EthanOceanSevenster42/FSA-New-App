import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/platform/downloads.dart';

/// A downloaded document is named the way the office names it.
///
/// The inspector and the office look at the same form from two systems, so
/// the file in Downloads carries the same name the record carries. It also
/// has to survive whatever a facility is called: apostrophes, slashes and
/// hyphens are all legal in a client name and none of them are legal in a
/// file name.
void main() {
  test('names the document as the office does', () {
    expect(
      Downloads.documentName(
          'Kroon Foods Test Store', 'RFI', DateTime(2026, 8, 22)),
      'FSA-Kroon-Foods-Test-Store-RFI-260822.pdf',
    );
  });

  test('pads a single-digit month and day', () {
    expect(
      Downloads.documentName('L Gromer', 'RFI', DateTime(2026, 1, 5)),
      'FSA-L-Gromer-RFI-260105.pdf',
    );
  });

  test('a punctuated facility name still makes a legal file name', () {
    expect(
      Downloads.documentName(
        "Spar Nick's Foods / King William's Town",
        'RFI',
        DateTime(2026, 12, 31),
      ),
      'FSA-Spar-Nick-s-Foods-King-William-s-Town-RFI-261231.pdf',
    );
  });
}
