import 'composition_checklist.dart';
import 'package:flutter/foundation.dart';

/// RawRMP checklist rules.
///
/// The screen's tick-list is five sections, each behind its own "... Present"
/// switch: marking label, scale label, container, display fridge, and notice
/// boards — the same shape as PMP, with RawRMP's own wording and regulation
/// references. A section that is not present contributes nothing — its rows
/// are not findings, because the requirement does not arise.
///
/// A TICK MEANS COMPLIANT, as everywhere else in the original: the column
/// header is "No Deviation", so the unticked rows of a present section are
/// the deviations.

enum RawRmpSection { marking, scale, container, fridge, notice }

@immutable
class RawRmpChecklistItemRef {
  const RawRmpChecklistItemRef({
    required this.id,
    required this.section,
    required this.originalId,
    required this.description,
    required this.regulationReference,
    this.minLetteringHeight = '',
  });

  final int id;
  final RawRmpSection section;
  final int originalId;
  final String description;
  final String regulationReference;
  final String minLetteringHeight;
}

@immutable
class RawRmpRef {
  const RawRmpRef({required this.id, required this.name});
  final int id;
  final String name;
}

abstract final class RawRmpRules {
  /// The product photographs a record cannot be finished without: a front
  /// view and a rear view, which is what the tick-list is read against. The
  /// original asks for them one at a time, by name, before it opens the
  /// Mark/Label checklist.
  static const requiredProductPhotos = 2;

  /// Whether the record still owes photographs. Anything past the required
  /// two is welcome and optional.
  static bool photographsOutstanding(int taken) =>
      taken < requiredProductPhotos;

  /// The rows that apply, given which sections are present.
  static List<RawRmpChecklistItemRef> applicable({
    required List<RawRmpChecklistItemRef> items,
    required Set<RawRmpSection> present,
  }) =>
      [
        for (final item in items)
          if (present.contains(item.section)) item,
      ];

  /// The unticked rows of the present sections — the deviations.
  static List<RawRmpChecklistItemRef> findings({
    required List<RawRmpChecklistItemRef> items,
    required Set<RawRmpSection> present,
    required Set<int> compliantItemIds,
  }) =>
      [
        for (final item in applicable(items: items, present: present))
          if (!compliantItemIds.contains(item.id)) item,
      ];

  // --------------------------------------------------------------------
  // Seizure. Added at the FSA's request (2026-08-20): on this commodity a
  // missing product name or batch code is not an ordinary deviation to be
  // corrected later — the consignment cannot be identified at all, so it is
  // seized.
  //
  // The product name carries a distinction the batch code does not. A name
  // that is shown but deficient is a deviation like any other; a name that
  // is not indicated at all is a seizure. The inspector answers that when
  // they untick the row, and the answer arrives here as
  // [productNameAbsent] — nothing is inferred from the tick alone.
  // --------------------------------------------------------------------

  /// Whether a row is the product-name requirement. The marking section
  /// words it "Appropriate Product Name" and the scale section "Product
  /// Appropriate Name", so both orderings are matched rather than either
  /// exact string.
  static bool isProductNameRow(RawRmpChecklistItemRef item) {
    // The display-fridge row also says "appropriate product name", but it
    // is the fridge signage (Reg. 12), not the label's product name.
    if (item.section == RawRmpSection.fridge) return false;
    final text = item.description.toLowerCase();
    if (text.contains('additions to')) return false;
    // The two sections word it differently — "Appropriate Product Name" in
    // marking, "Product Appropriate Name" on the scale label — so the words
    // are matched rather than either phrase.
    return text.contains('appropriate') &&
        text.contains('product') &&
        text.contains('name');
  }

  /// Whether a row is the batch-code requirement — "Date Marking/Batch
  /// Code/Batch Number" in both label sections.
  static bool isBatchCodeRow(RawRmpChecklistItemRef item) =>
      item.description.toLowerCase().contains('batch code');

  /// The findings that force a seizure rather than a direction.
  ///
  /// An unticked batch code always qualifies. An unticked product name
  /// qualifies only when the inspector said the name is not indicated at
  /// all. A container row qualifies too: Annexure A reads "Immediate
  /// seizure / Rectify immediately" for a container that does not comply.
  static List<RawRmpChecklistItemRef> seizureFindings({
    required List<RawRmpChecklistItemRef> items,
    required Set<RawRmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
  }) =>
      [
        for (final item in findings(
          items: items,
          present: present,
          compliantItemIds: compliantItemIds,
        ))
          if (actionFor(item, productNameAbsent: productNameAbsent) ==
                  RawRmpAction.seize ||
              actionFor(item, productNameAbsent: productNameAbsent) ==
                  RawRmpAction.seizeOrRectifyNow)
            item,
      ];

  // --------------------------------------------------------------------
  // FSA-SOP-APS-001, Annexure A (Certain Raw Processed Meat Products —
  // Enforcement Table, 11 June 2026). What each deviation leads to is the
  // annexure's ruling, not the inspector's to pick (Ethan, 2026-09-26):
  //
  //   Compositional standards ......... immediate seizure
  //   Container / outer container ..... immediate seizure / rectify at once
  //   Product name omitted ............ immediate seizure
  //   Product name incomplete / wrong . 30-day rectification
  //   Additions to product name ....... 30-day rectification
  //   Name and address ................ 30-day rectification
  //   Batch identification / dating ... immediate seizure
  //   Country of origin ............... 30-day rectification
  //   Restricted particulars .......... 30-day rectification
  //   Display fridge labelling ........ 3-day rectification
  // --------------------------------------------------------------------

  /// What the annexure prescribes for one deviation.
  static RawRmpAction actionFor(RawRmpChecklistItemRef item,
      {required bool productNameAbsent}) {
    if (item.section == RawRmpSection.container) {
      return RawRmpAction.seizeOrRectifyNow;
    }
    if (item.section == RawRmpSection.fridge) return RawRmpAction.rectify3Days;
    if (isBatchCodeRow(item)) return RawRmpAction.seize;
    if (isProductNameRow(item)) {
      return productNameAbsent ? RawRmpAction.seize : RawRmpAction.rectify30Days;
    }
    return RawRmpAction.rectify30Days;
  }

  /// Days the annexure allows, counted from the inspection. A deviation it
  /// seizes on has none; should the inspector carry on instead of seizing,
  /// the rejection runs from today.
  static int daysFor(RawRmpAction action) => switch (action) {
        RawRmpAction.seize => 0,
        RawRmpAction.seizeOrRectifyNow => 0,
        RawRmpAction.rectify3Days => 3,
        RawRmpAction.rectify30Days => 30,
      };

  /// A compositional checklist with a deviation marked on any requirement
  /// fails the compositional standard (Reg. 5), which the annexure seizes on.
  static bool compositionFails(List<CompositionAnswer> answers) =>
      answers.any((a) => a.deviation == true);

  /// The rectification period the rejection carries: the shortest the
  /// annexure gives any of the deviations, with a failed composition at
  /// nought. Null while nothing is wrong.
  static int? rectificationDays({
    required List<RawRmpChecklistItemRef> items,
    required Set<RawRmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
    bool compositionFailed = false,
  }) {
    int? shortest = compositionFailed ? 0 : null;
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

  /// Whether this inspection must be seized.
  static bool seizureRequired({
    required List<RawRmpChecklistItemRef> items,
    required Set<RawRmpSection> present,
    required Set<int> compliantItemIds,
    required bool productNameAbsent,
  }) =>
      seizureFindings(
        items: items,
        present: present,
        compliantItemIds: compliantItemIds,
        productNameAbsent: productNameAbsent,
      ).isNotEmpty;
}

/// What FSA-SOP-APS-001 Annexure A prescribes for a deviation.
enum RawRmpAction {
  /// Seized under section 8 of the APS Act, no period given.
  seize,

  /// The container rows: "Immediate seizure / Rectify immediately".
  seizeOrRectifyNow,
  rectify3Days,
  rectify30Days,
}
