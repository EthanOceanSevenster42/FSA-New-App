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
}
