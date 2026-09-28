import 'package:flutter/foundation.dart';

/// PMP checklist rules.
///
/// The screen's tick-list is five sections, each behind its own "... Present"
/// switch: marking label, scale label, container, display fridge, and notice
/// boards. A section that is not present contributes nothing — its rows are
/// not findings, because the requirement does not arise. That is the same
/// distinction the poultry label screen draws for its outer container, and
/// getting it wrong fails a consignment for lacking a fridge it never had.
///
/// A TICK MEANS COMPLIANT, as everywhere else in the original: the column
/// header is "No Deviation", so the unticked rows of a present section are
/// the deviations.

enum PmpSection { marking, scale, container, fridge, notice }

@immutable
class PmpChecklistItemRef {
  const PmpChecklistItemRef({
    required this.id,
    required this.section,
    required this.originalId,
    required this.description,
    required this.regulationReference,
    this.minLetteringHeight = '',
  });

  final int id;
  final PmpSection section;
  final int originalId;
  final String description;
  final String regulationReference;
  final String minLetteringHeight;
}

@immutable
class PmpRef {
  const PmpRef({required this.id, required this.name});
  final int id;
  final String name;
}

abstract final class PmpRules {
  /// The rows that apply, given which sections are present.
  static List<PmpChecklistItemRef> applicable({
    required List<PmpChecklistItemRef> items,
    required Set<PmpSection> present,
  }) =>
      [
        for (final item in items)
          if (present.contains(item.section)) item,
      ];

  /// The unticked rows of the present sections — the deviations.
  static List<PmpChecklistItemRef> findings({
    required List<PmpChecklistItemRef> items,
    required Set<PmpSection> present,
    required Set<int> compliantItemIds,
  }) =>
      [
        for (final item in applicable(items: items, present: present))
          if (!compliantItemIds.contains(item.id)) item,
      ];

  // --------------------------------------------------------------------
  // FSA-SOP-APS-001, Annexure B (Processed Meat Products — Non-Conformance
  // Table, 11 June 2026). What each deviation leads to is the annexure's
  // ruling, not the inspector's to pick (Ethan, 2026-09-26):
  //
  //   Product name omitted ............ immediate seizure
  //   Product name incomplete / wrong . 30-day rectification
  //   Additions to product name ....... 30-day rectification
  //   Name and address ................ 30-day rectification
  //   Batch identification / dating ... immediate seizure
  //   Country of origin ............... 30-day rectification
  //   Restricted particulars .......... 30-day rectification
  //   Container / outer container ..... immediate seizure / rectify at once
  //   Display fridge labelling ........ 3-day rectification
  //
  // Whether the product name was omitted or merely wrong is the
  // inspector's answer when the row is unticked ([productNameAbsent]).
  // --------------------------------------------------------------------

  /// What the annexure prescribes for one deviation.
  static PmpAction actionFor(PmpChecklistItemRef item,
      {required bool productNameAbsent}) {
    if (item.section == PmpSection.container) return PmpAction.seizeOrRectifyNow;
    if (item.section == PmpSection.fridge) return PmpAction.rectify3Days;
    if (isBatchRow(item)) return PmpAction.seize;
    if (isProductNameRow(item)) {
      return productNameAbsent ? PmpAction.seize : PmpAction.rectify30Days;
    }
    return PmpAction.rectify30Days;
  }

  /// The product-name requirement itself — "Product Name" on the marking
  /// and scale labels, not the additions to it.
  static bool isProductNameRow(PmpChecklistItemRef item) =>
      item.description.trim().toLowerCase() == 'product name';

  /// "Date Marking/Batch Identification" on either label.
  static bool isBatchRow(PmpChecklistItemRef item) =>
      item.description.toLowerCase().contains('batch');

  /// Days the annexure allows to put a deviation right, counted from the
  /// inspection. A deviation it seizes on has none; should the inspector
  /// carry on instead of seizing, the rejection runs from today.
  static int daysFor(PmpAction action) => switch (action) {
        PmpAction.seize => 0,
        PmpAction.seizeOrRectifyNow => 0,
        PmpAction.rectify3Days => 3,
        PmpAction.rectify30Days => 30,
      };

  /// The findings the annexure seizes on.
  static List<PmpChecklistItemRef> seizureFindings({
    required List<PmpChecklistItemRef> items,
    required Set<PmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
  }) =>
      [
        for (final item in findings(
            items: items, present: present, compliantItemIds: compliantItemIds))
          if (actionFor(item, productNameAbsent: productNameAbsent) ==
                  PmpAction.seize ||
              actionFor(item, productNameAbsent: productNameAbsent) ==
                  PmpAction.seizeOrRectifyNow)
            item,
      ];

  /// Whether the seizure question has to be put.
  static bool seizureRequired({
    required List<PmpChecklistItemRef> items,
    required Set<PmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
  }) =>
      seizureFindings(
        items: items,
        present: present,
        compliantItemIds: compliantItemIds,
        productNameAbsent: productNameAbsent,
      ).isNotEmpty;

  /// The rectification period the rejection carries: the shortest the
  /// annexure gives any of the deviations. Null while nothing is wrong.
  static int? rectificationDays({
    required List<PmpChecklistItemRef> items,
    required Set<PmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
  }) {
    int? shortest;
    for (final item in findings(
        items: items, present: present, compliantItemIds: compliantItemIds)) {
      final d = daysFor(actionFor(item, productNameAbsent: productNameAbsent));
      if (shortest == null || d < shortest) shortest = d;
    }
    return shortest;
  }

  /// "Correct by/on" — the inspection date plus the period, as a date.
  static DateTime? correctByDate({
    required DateTime inspectedAt,
    required int? days,
  }) =>
      days == null
          ? null
          : DateTime(inspectedAt.year, inspectedAt.month, inspectedAt.day)
              .add(Duration(days: days));

  /// How the period reads on the form and the sheet.
  static String periodLabel(int days) => switch (days) {
        0 => 'Rectify immediately',
        3 => '3-day rectification notice',
        30 => '30-day rectification notice',
        _ => '$days-day rectification notice',
      };
}

/// What FSA-SOP-APS-001 Annexure B prescribes for a deviation.
enum PmpAction {
  /// Seized under section 8 of the APS Act, no period given.
  seize,

  /// The container rows: "Immediate seizure / Rectify immediately".
  seizeOrRectifyNow,
  rectify3Days,
  rectify30Days,
}
