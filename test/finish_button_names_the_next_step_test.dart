import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// The button at the foot of an egg inspection inside a visit said "DONE —
/// NEXT INSPECTION" whatever came next. It now names it: another egg
/// inspection, the next commodity, or finalising the last one planned
/// (Ethan, 2026-09-29).
void main() {
  ({
    String kind,
    String single,
    String short,
    int planned,
    int members,
    int completed
  }) row(String kind, String single, String short,
          {int planned = 0, int members = 0, int completed = 0}) =>
      (
        kind: kind,
        single: single,
        short: short,
        planned: planned,
        members: members,
        completed: completed,
      );

  List<
      ({
        String kind,
        String single,
        String short,
        int planned,
        int members,
        int completed
      })> plan({int eggs = 1, int poultry = 0, int eggsDone = 0, int eggsBegun = 0}) => [
        row('egg', 'Egg Inspection', 'Eggs',
            planned: eggs, members: eggsBegun, completed: eggsDone),
        row('poultry', 'Poultry Inspection', 'Poultry', planned: poultry),
        row('rawrmp', 'Certain Raw Processed Meat Product Inspection', 'Raw'),
        row('pmp', 'Processed Meat Product Inspection', 'Processed Meat'),
      ];

  test('the only inspection planned is finalised', () {
    expect(finishLabelFor(kind: 'egg', resuming: false, plan: plan()),
        'FINALISE EGG INSPECTION');
  });

  test('a commodity still to come is named', () {
    expect(
        finishLabelFor(kind: 'egg', resuming: false, plan: plan(poultry: 1)),
        'DONE — NEXT COMMODITY: POULTRY');
  });

  test('another egg inspection comes before the next commodity', () {
    expect(
        finishLabelFor(
            kind: 'egg', resuming: false, plan: plan(eggs: 2, poultry: 1)),
        'DONE — NEXT EGG INSPECTION');
  });

  test('the last of two egg inspections, resumed, is finalised', () {
    expect(
        finishLabelFor(
            kind: 'egg',
            resuming: true,
            plan: plan(eggs: 2, eggsBegun: 2, eggsDone: 1)),
        'FINALISE EGG INSPECTION');
  });
}
