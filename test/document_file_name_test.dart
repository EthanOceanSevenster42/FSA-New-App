import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

void main() {
  String name(String facility, String kind, String product) =>
      FsaForm.documentFileName(
          facility: facility,
          kind: kind,
          record: '767b840f-0a15-4e3d-942c-efdcbb526e89',
          product: product);

  test('the product sits between the facility and the sheet', () {
    expect(name('Kroon Foods', 'Sampling-Checklist', 'Beef Sausage'),
        'FSA-Kroon-Foods-Beef-Sausage-Sampling-Checklist-767b840f.pdf');
  });

  test('a word the product already says is not said twice', () {
    expect(name('Zeekoegat', 'Egg-Weighing-Checklist', 'Eggs'),
        'FSA-Zeekoegat-Eggs-Weighing-Checklist-767b840f.pdf');
    expect(name('Zeekoegat', 'Egg-Labelling-Checklist', 'Eggs'),
        'FSA-Zeekoegat-Eggs-Labelling-Checklist-767b840f.pdf');
    expect(name('Zeekoegat', 'Egg-Rejection', 'Eggs'),
        'FSA-Zeekoegat-Eggs-Rejection-767b840f.pdf');
  });

  test('no product leaves the old name untouched', () {
    expect(name('Zeekoegat', 'Egg-Weighing-Checklist', ''),
        'FSA-Zeekoegat-Egg-Weighing-Checklist-767b840f.pdf');
  });

  test('the sheet is never emptied by the stripping', () {
    expect(name('Kroon Foods', 'Rejection', 'Rejection'),
        'FSA-Kroon-Foods-Rejection-Rejection-767b840f.pdf');
  });

  test('punctuation in a product name is hyphenated', () {
    expect(name('Kroon Foods', 'Sampling-Checklist', 'Boerewors (Pty) Ltd.'),
        'FSA-Kroon-Foods-Boerewors-Pty-Ltd-Sampling-Checklist-767b840f.pdf');
  });
}
