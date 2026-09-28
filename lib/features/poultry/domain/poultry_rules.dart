import 'package:flutter/foundation.dart';

/// Grading and classification rules, as the original applies them.
///
/// Two things here are easy to get wrong and are therefore stated in one place
/// rather than spread through the form:
///
///   A designation may only carry certain grades, and which ones depends on
///   the meat type. Offering every grade for every designation would let an
///   inspector record a combination the original refuses, and the record would
///   then disagree with the paper trail it exists to match.
///
///   A ticked box means COMPLIANT. The original's column header reads "NO
///   Deviation" and the section "Deviation (Tick if No Deviation)". Every
///   other checklist in this codebase ticks to record a problem, so this one
///   is inverted relative to the reader's expectation — including, once, mine.

@immutable
class PoultryMeatTypeRef {
  const PoultryMeatTypeRef({required this.id, required this.name});
  final int id;
  final String name;
}

@immutable
class PoultryGradeRef {
  const PoultryGradeRef({
    required this.id,
    required this.name,
    required this.rank,
  });

  final int id;
  final String name;

  /// Null on "Undergrade" and "No Grade" — outcomes, not tiers. Ranking them
  /// would imply an ordering the original never states.
  final int? rank;
}

@immutable
class PoultryDesignationRef {
  const PoultryDesignationRef({required this.id, required this.name});
  final int id;
  final String name;
}

/// A (meat type, designation, grade) triple the original permits.
@immutable
class PoultryGradeLink {
  const PoultryGradeLink({
    required this.meatTypeId,
    required this.designationId,
    required this.gradeId,
  });

  final int meatTypeId;
  final int designationId;
  final int gradeId;
}

/// Which checklist a tick-box belongs to.
///
/// The Label/Container screen splits its lettering rows in two: the same nine
/// requirements are asked once of the product label and again of the outer
/// container. They are separate kinds because an inspector can find one
/// compliant and the other not, and the record has to say which.
enum PoultryChecklistKind {
  grading,
  portion,
  pack,
  labelInner,
  labelOuter,
  container,

  /// The label screen's own copies of the grading and portion lists. Spelled
  /// differently from the grading screen's ("Freshiness" against
  /// "Fleshiness"), and reproduced rather than reconciled.
  labelGrading,
  labelPortion,
}

@immutable
class PoultryChecklistItemRef {
  const PoultryChecklistItemRef({
    required this.id,
    required this.kind,
    required this.originalId,
    required this.description,
    required this.regulationReference,
    this.minLetteringHeight = '',
  });

  final int id;
  final PoultryChecklistKind kind;

  /// The number the original gives the box, so the two systems line up.
  final int originalId;
  final String description;
  final String regulationReference;

  /// Minimum lettering height in millimetres, where the row states one.
  /// Empty on every row that does not — which is most of them.
  final String minLetteringHeight;
}

/// A checklist row the inspector did not tick, i.e. a deviation.
@immutable
class PoultryFinding {
  const PoultryFinding({required this.item});
  final PoultryChecklistItemRef item;
}

abstract final class PoultryRules {
  /// How many photographs a label or QUID record needs before it is
  /// finished.
  ///
  /// The original will not let the label checklist be completed until two
  /// have been taken: `NewPoultryLabelChecklistPage` counts to `[n / 2]` and
  /// only then enables `switchIsLabelandPackListComplete`. The QUID screen
  /// asks for its two only when a rejection is issued
  /// (`quidMinRejectionPhotos`).
  static const requiredPhotos = 2;

  /// One more than the minimum. The extra shot is there for the view the
  /// first two could not fit — a second container face, a smudged lot code —
  /// and a ceiling keeps a record from arriving as an album the office has
  /// to sift.
  static const maxPhotos = requiredPhotos + 1;

  /// Whether the record still owes the photographs it cannot be finished
  /// without.
  static bool photographsOutstanding(int taken) => taken < requiredPhotos;

  /// Grades permitted for [designationId] under [meatTypeId].
  ///
  /// Returns them in the order [grades] is given, so the form presents the
  /// same sequence the reference data does rather than link order.
  ///
  /// An unknown pairing yields nothing rather than everything: showing the
  /// full list when the rule is missing is how an unsupported grade gets
  /// recorded, and the empty case is visible to the inspector.
  static List<PoultryGradeRef> gradesFor({
    required int? meatTypeId,
    required int? designationId,
    required List<PoultryGradeLink> links,
    required List<PoultryGradeRef> grades,
  }) {
    if (meatTypeId == null || designationId == null) return const [];
    final allowed = {
      for (final link in links)
        if (link.meatTypeId == meatTypeId &&
            link.designationId == designationId)
          link.gradeId,
    };
    return [
      for (final grade in grades)
        if (allowed.contains(grade.id)) grade,
    ];
  }

  /// Designations that carry at least one grade under [meatTypeId].
  ///
  /// A designation with no link for this meat type cannot be graded at all, so
  /// offering it would strand the inspector on the next field.
  static List<PoultryDesignationRef> designationsFor({
    required int? meatTypeId,
    required List<PoultryGradeLink> links,
    required List<PoultryDesignationRef> designations,
  }) {
    if (meatTypeId == null) return const [];
    final allowed = {
      for (final link in links)
        if (link.meatTypeId == meatTypeId) link.designationId,
    };
    return [
      for (final designation in designations)
        if (allowed.contains(designation.id)) designation,
    ];
  }

  /// The rows that were NOT ticked — the deviations.
  ///
  /// Takes the compliant set rather than the failing set because that is what
  /// the screen collects and what the record stores; deriving the complement
  /// in one place keeps the inversion from being re-implemented per screen.
  static List<PoultryFinding> findings({
    required List<PoultryChecklistItemRef> items,
    required Set<int> compliantItemIds,
  }) =>
      [
        for (final item in items)
          if (!compliantItemIds.contains(item.id)) PoultryFinding(item: item),
      ];

  /// True when every row on every list was ticked.
  static bool isFullyCompliant({
    required List<PoultryChecklistItemRef> items,
    required Set<int> compliantItemIds,
  }) =>
      items.isNotEmpty &&
      findings(items: items, compliantItemIds: compliantItemIds).isEmpty;

  /// Whether a direction has to be served.
  ///
  /// Any unticked row is a deviation, and a deviation is what a direction
  /// cites. The original leaves serving one to the inspector's judgement, so
  /// this reports the condition rather than acting on it.
  static bool directionRequired({
    required List<PoultryChecklistItemRef> items,
    required Set<int> compliantItemIds,
  }) =>
      findings(items: items, compliantItemIds: compliantItemIds).isNotEmpty;

  // --------------------------------------------------------------------
  // FSA-SOP-APS-001, Annexure C (Poultry Meat — Non-Conformance Table,
  // 11 June 2026). What each deviation leads to is the annexure's ruling,
  // not the inspector's to pick (Ethan, 2026-09-26):
  //
  //   Container (Reg. 6) ................ immediate seizure / rectify at once
  //   Packing (Reg. 7) .................. immediate seizure / rectify at once
  //   Class designation omitted ......... immediate seizure
  //   Class designation wrong ........... 30-day rectification
  //   Grade designation omitted ......... immediate seizure
  //   Grade designation wrong ........... 30-day rectification
  //   Packer (Reg. 11) .................. 30-day rectification
  //   Country of origin (Reg. 11(4)) .... 30-day rectification
  //   Production lot (Reg. 12) .......... immediate seizure
  //   Fresh / chilled / frozen .......... 30-day rectification
  //   Giblets / trimmed ................. 30-day rectification
  //   Restricted particulars (Reg. 13) .. 30-day rectification
  //   Poultry species ................... 30-day rectification
  //   QUID / quality standards .......... immediate seizure
  //
  // A grading or portion row failed is the carcass not meeting the grade it
  // is marked with — an incorrect grade designation — and takes the 30
  // days. Whether the class or grade designation was omitted or merely
  // wrong is the inspector's answer when that row is unticked.
  // --------------------------------------------------------------------

  static bool _isLabelRow(PoultryChecklistItemRef item) =>
      item.kind == PoultryChecklistKind.labelInner ||
      item.kind == PoultryChecklistKind.labelOuter;

  /// "Class or Other Designation Indication" on either label.
  static bool isClassRow(PoultryChecklistItemRef item) =>
      _isLabelRow(item) && item.description.toLowerCase().contains('class');

  /// "Grade Designation" on either label.
  static bool isGradeRow(PoultryChecklistItemRef item) =>
      _isLabelRow(item) &&
      item.description.toLowerCase().startsWith('grade designation');

  /// "Number and Code to Identify Production Lot" on either label.
  static bool isLotRow(PoultryChecklistItemRef item) =>
      _isLabelRow(item) &&
      item.description.toLowerCase().contains('production lot');

  /// What the annexure prescribes for one deviation.
  static PoultryAction actionFor(
    PoultryChecklistItemRef item, {
    required bool classOmitted,
    required bool gradeOmitted,
  }) {
    switch (item.kind) {
      case PoultryChecklistKind.container:
      case PoultryChecklistKind.pack:
        return PoultryAction.seizeOrRectifyNow;
      case PoultryChecklistKind.labelInner:
      case PoultryChecklistKind.labelOuter:
        if (isLotRow(item)) return PoultryAction.seize;
        if (isClassRow(item)) {
          return classOmitted
              ? PoultryAction.seize
              : PoultryAction.rectify30Days;
        }
        if (isGradeRow(item)) {
          return gradeOmitted
              ? PoultryAction.seize
              : PoultryAction.rectify30Days;
        }
        return PoultryAction.rectify30Days;
      case PoultryChecklistKind.grading:
      case PoultryChecklistKind.portion:
      case PoultryChecklistKind.labelGrading:
      case PoultryChecklistKind.labelPortion:
        return PoultryAction.rectify30Days;
    }
  }

  /// Days the annexure allows to put a deviation right, counted from the
  /// inspection. A deviation it seizes on has none; should the inspector
  /// carry on instead of seizing, the rejection runs from today.
  static int daysFor(PoultryAction action) => switch (action) {
        PoultryAction.seize => 0,
        PoultryAction.seizeOrRectifyNow => 0,
        PoultryAction.rectify30Days => 30,
      };

  /// The deviations the annexure seizes on.
  static List<PoultryChecklistItemRef> seizureFindings({
    required Iterable<PoultryChecklistItemRef> deviations,
    required bool classOmitted,
    required bool gradeOmitted,
  }) =>
      [
        for (final item in deviations)
          if (actionFor(item,
                  classOmitted: classOmitted, gradeOmitted: gradeOmitted) !=
              PoultryAction.rectify30Days)
            item,
      ];

  /// Whether the seizure question has to be put.
  static bool seizureRequired({
    required Iterable<PoultryChecklistItemRef> deviations,
    required bool classOmitted,
    required bool gradeOmitted,
  }) =>
      seizureFindings(
        deviations: deviations,
        classOmitted: classOmitted,
        gradeOmitted: gradeOmitted,
      ).isNotEmpty;

  /// The rectification period the rejection carries: the shortest the
  /// annexure gives any of the deviations. Null while nothing is wrong.
  static int? rectificationDays({
    required Iterable<PoultryChecklistItemRef> deviations,
    required bool classOmitted,
    required bool gradeOmitted,
  }) {
    int? shortest;
    for (final item in deviations) {
      final d = daysFor(actionFor(item,
          classOmitted: classOmitted, gradeOmitted: gradeOmitted));
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
        30 => '30-day rectification notice',
        _ => '$days-day rectification notice',
      };
}

/// What FSA-SOP-APS-001 Annexure C prescribes for a deviation.
enum PoultryAction {
  /// Seized under section 8 of the APS Act, no period given.
  seize,

  /// The container and packing rows: "Immediate seizure / Rectify
  /// immediately".
  seizeOrRectifyNow,
  rectify30Days,
}
