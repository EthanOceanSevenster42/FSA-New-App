import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A mass band. [maxMassG] is null on the open-topped band (Jumbo).
@immutable
class EggSizeBand {
  const EggSizeBand({
    required this.id,
    required this.name,
    required this.minMassG,
    required this.maxMassG,
    required this.sortOrder,
    this.isMassBand = true,
  });

  final int id;
  final String name;
  final double minMassG;
  final double? maxMassG;
  final int sortOrder;

  /// False for a size that is declared on the pack rather than measured.
  /// "Mixed Size" describes an assorted consignment, so no single egg is one.
  final bool isMassBand;
}

/// A grade the consignment can take. Lower [rank] is better.
@immutable
class EggGradeRef {
  const EggGradeRef({
    required this.id,
    required this.name,
    required this.rank,
  });

  final int id;
  final String name;
  final int rank;
}

/// A tickable deviation. [downgradesToGradeId] is null when the deviation is
/// recorded but does not by itself change the grade.
@immutable
class DeviationRef {
  const DeviationRef({
    required this.id,
    required this.categoryId,
    required this.description,
    required this.downgradesToGradeId,
  });

  final int id;
  final int categoryId;
  final String description;
  final int? downgradesToGradeId;
}

/// How many of a deviation a consignment may carry before it is a finding.
///
/// Keyed on the deviation together with the consignment's *declared* size and
/// grade — the same deviation is tolerated differently on Grade 1 Jumbo than on
/// Grade 3 Small. The original holds 630 of these.
@immutable
class DeviationTolerance {
  const DeviationTolerance({
    required this.deviationId,
    required this.sizeId,
    required this.gradeId,
    required this.minimum,
    required this.maximum,
  });

  final int deviationId;
  final int sizeId;
  final int gradeId;
  final int minimum;
  final int maximum;
}

/// Which of the three labelling checklists a requirement belongs to.
///
/// The original tracks each checklist as a bitmask of ticked "No Deviation"
/// boxes and calls it a pass only when every box is ticked.
enum LabelChecklist { innerLabel, outerLabel, container }

/// Whether each part of a direction is required, and therefore whether one has
/// to be issued at all.
@immutable
class DirectionRequirement {
  const DirectionRequirement({
    required this.labelling,
    required this.quality,
  });

  /// The mark/pack part — the original's `IsMarkPackDirectivePartPresent`.
  final bool labelling;

  /// The grade/size part — the original's `IsGradeSizeDirectivePartPresent`.
  final bool quality;

  /// A direction is served when either part applies. Both can apply at once,
  /// which is one document with two deadlines rather than two documents.
  bool get any => labelling || quality;
}

/// Egg-specific calculations.
///
/// Pure functions with no database, network or widget dependencies, so the
/// parts that decide a regulatory outcome can be tested exhaustively. The
/// rules stay out of the presentation layer entirely.
abstract final class EggRules {
  /// The size band a mass falls into, or null when it falls outside every
  /// band. Null is a real answer — an egg lighter than the smallest band is
  /// not "Small", it is unclassified, and forcing it into a band would
  /// misreport the consignment.
  static EggSizeBand? sizeFor(double? massG, List<EggSizeBand> bands) {
    if (massG == null || massG <= 0 || bands.isEmpty) return null;
    // Declarations are excluded outright rather than relied on to sort last:
    // "Mixed Size" shares its 33 g floor with Small, so if the ladder's floor
    // ever rose above 33 an ordering argument would quietly start deriving it.
    final sorted = [
      for (final band in bands)
        if (band.isMassBand) band,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final band in sorted) {
      final aboveFloor = massG >= band.minMassG;
      final belowCeiling = band.maxMassG == null || massG <= band.maxMassG!;
      if (aboveFloor && belowCeiling) return band;
    }
    return null;
  }

  /// Haugh unit — the standard measure of albumen quality.
  ///
  ///   HU = 100 × log10(h − 1.7·w^0.37 + 7.6)
  ///
  /// where h is albumen height in mm and w is egg mass in g (Haugh, 1937).
  /// Returns null when the inputs are missing or produce a non-positive
  /// logarithm argument, rather than returning 0 — a Haugh unit of 0 would
  /// read as "worst possible albumen", which is a different claim from
  /// "not measured".
  static double? haughUnit({double? albumenHeightMm, double? massG}) {
    if (albumenHeightMm == null || massG == null) return null;
    if (albumenHeightMm <= 0 || massG <= 0) return null;

    final inner = albumenHeightMm - 1.7 * math.pow(massG, 0.37) + 7.6;
    if (inner <= 0) return null;
    return 100 * (math.log(inner) / math.ln10);
  }

  /// Grade for a single egg, given the deviations ticked on it.
  ///
  /// Starts at the best grade and takes the worst downgrade any ticked
  /// deviation forces. Returns null if no grades are defined.
  static EggGradeRef? gradeForEgg({
    required Set<int> tickedDeviationIds,
    required List<DeviationRef> deviations,
    required List<EggGradeRef> grades,
  }) {
    if (grades.isEmpty) return null;
    final sorted = [...grades]..sort((a, b) => a.rank.compareTo(b.rank));
    var worst = sorted.first;

    final byId = {for (final d in deviations) d.id: d};
    final gradeById = {for (final g in grades) g.id: g};

    for (final id in tickedDeviationIds) {
      final target = byId[id]?.downgradesToGradeId;
      if (target == null) continue;
      final grade = gradeById[target];
      if (grade != null && grade.rank > worst.rank) worst = grade;
    }
    return worst;
  }

  /// Consignment grade: the worst grade across the sampled eggs.
  ///
  /// Eggs with no determined grade are skipped rather than counted as the
  /// best — an unmeasured egg must not improve the result.
  static EggGradeRef? consignmentGrade(List<EggGradeRef?> perEggGrades) {
    final graded = perEggGrades.whereType<EggGradeRef>().toList();
    if (graded.isEmpty) return null;
    return graded.reduce((a, b) => a.rank >= b.rank ? a : b);
  }

  /// Whether a deviation seen [count] times is within tolerance.
  ///
  /// A count of zero is not a deviation at all. Otherwise the count must fall
  /// within the band for this deviation at the consignment's declared size and
  /// grade.
  ///
  /// A combination with no rule is treated as a band of 0–0, so any occurrence
  /// at all is a finding. That is deliberately what the original does: it reads
  /// the tolerance with `FirstOrDefault()`, and the default of a C# `int` is
  /// zero. Defaulting to "no tolerance" also fails safe — an unlisted
  /// combination raises a direction rather than silently waving the
  /// consignment through.
  static bool isDeviationPermissible({
    required int deviationId,
    required int count,
    required int sizeId,
    required int gradeId,
    required Iterable<DeviationTolerance> tolerances,
  }) {
    if (count <= 0) return true;

    for (final t in tolerances) {
      if (t.deviationId == deviationId &&
          t.sizeId == sizeId &&
          t.gradeId == gradeId) {
        return count >= t.minimum && count <= t.maximum;
      }
    }
    return false;
  }

  /// Whether the quality (grade and size) part of a direction is required.
  ///
  /// Required as soon as one deviation exceeds its tolerance.
  /// [countsByDeviationId] is how many eggs in the sample showed each
  /// deviation.
  static bool isQualityDirectionRequired({
    required Map<int, int> countsByDeviationId,
    required int sizeId,
    required int gradeId,
    required Iterable<DeviationTolerance> tolerances,
  }) {
    // Materialised once: the caller may pass a lazy iterable, and this walks it
    // per deviation.
    final rules = tolerances.toList(growable: false);
    return countsByDeviationId.entries.any(
      (e) => !isDeviationPermissible(
        deviationId: e.key,
        count: e.value,
        sizeId: sizeId,
        gradeId: gradeId,
        tolerances: rules,
      ),
    );
  }

  /// Whether the labelling (mark and pack) part of a direction is required.
  ///
  /// The original ticks a "No Deviation" box against each labelling
  /// requirement and passes a checklist only when every box on it is ticked;
  /// all three checklists must pass. It starts with every box ticked — "set
  /// this to initial pass conditions" — so an untouched inspection passes, and
  /// a requirement is failed by being explicitly marked as failing.
  ///
  /// That makes this the same statement as "any requirement failed", but it is
  /// written per checklist because the direction document reports them
  /// separately and because a checklist can be removed or extended without
  /// this rule changing shape.
  static bool isLabelDirectionRequired({
    required Set<int> failedRequirementIds,
    required Map<LabelChecklist, Set<int>> checklists,
  }) =>
      checklists.values.any((ids) => ids.intersection(failedRequirementIds).isNotEmpty);

  /// Both parts of the direction decision for a finished inspection.
  ///
  /// The original computes these separately and stores them on one direction
  /// record, each with its own correct-by date.
  static DirectionRequirement directionRequired({
    required Map<int, int> countsByDeviationId,
    required int sizeId,
    required int gradeId,
    required Iterable<DeviationTolerance> tolerances,
    required Set<int> failedRequirementIds,
    required Map<LabelChecklist, Set<int>> checklists,
  }) =>
      DirectionRequirement(
        quality: isQualityDirectionRequired(
          countsByDeviationId: countsByDeviationId,
          sizeId: sizeId,
          gradeId: gradeId,
          tolerances: tolerances,
        ),
        labelling: isLabelDirectionRequired(
          failedRequirementIds: failedRequirementIds,
          checklists: checklists,
        ),
      );

  /// Six additional samples are required when the mean Haugh unit
  /// of those measured fell below this threshold.
  static const haughAdditionalSampleThreshold = 70.0;

  /// How many extra eggs are required when the mean falls short.
  static const haughAdditionalSampleCount = 6;

  /// Mean Haugh unit across eggs that have one. Null when none were measured —
  /// not 0, which would trip the "below 70" rule on an unmeasured sample.
  static double? meanHaughUnit(Iterable<double?> haughUnits) {
    final measured = haughUnits.whereType<double>().toList();
    if (measured.isEmpty) return null;
    return measured.reduce((a, b) => a + b) / measured.length;
  }

  /// How many more eggs the Haugh rule requires, or 0 if none.
  ///
  /// Message: "The average value of the available Haugh Value samples is below
  /// 70 HU. An additional six (6) samples is required."
  ///
  /// [baselineCount] is how many eggs the inspection held when the mean was
  /// first seen below the threshold. The requirement is six *more than that* —
  /// a single escalation that can actually be satisfied.
  ///
  /// An earlier version derived the target from the current measured count, so
  /// every egg added and measured pushed the target six further out and the
  /// inspection could never be saved. Anchoring on the baseline is what makes
  /// it terminate.
  ///
  /// NOTE: this escalates once. Whether the FSA expects a further six when the
  /// mean is *still* below 70 after the extra samples is not settled here and
  /// needs confirming with them.
  static int additionalSamplesRequired({
    required Iterable<double?> haughUnits,
    required int sampledCount,
    int? baselineCount,
  }) {
    final mean = meanHaughUnit(haughUnits);
    if (mean == null || mean >= haughAdditionalSampleThreshold) return 0;

    // With no baseline recorded, the shortfall is being evaluated for the
    // first time: the eggs on hand now are the baseline.
    final baseline = baselineCount ?? sampledCount;
    final shortfall = (baseline + haughAdditionalSampleCount) - sampledCount;
    return shortfall > 0 ? shortfall : 0;
  }
}

/// Field-level validation, kept beside the rules it enforces.
///
/// Each message belongs to a check the capture form
/// performed, so an inspector moving between the two apps sees the same
/// constraints.
abstract final class EggValidation {
  /// Message: "A weight reading must be entered for this sample, before any
  /// egg deviations can be noted."
  static bool canRecordDeviations(double? massG) => massG != null && massG > 0;

  static const deviationsNeedMass =
      'A weight reading must be entered for this egg before any deviations '
      'can be noted.';

  /// Message: "No weight has been entered for this sample. No Haugh Unit can
  /// be calculated." Same precondition, different consequence.
  static const haughNeedsMass =
      'No weight has been entered for this egg, so no Haugh unit can be '
      'calculated.';

  /// Upper sanity bound on a single egg. NOT a regulation — an earlier version
  /// warned "Entered weight is too high. Please recheck the scale's reading",
  /// which is a mis-keyed-input guard. Adjust if a heavier species is ever
  /// inspected.
  static const maxPlausibleEggMassG = 150.0;

  /// Message: "Maximum number of samples reached!". This ceiling is not
  /// recoverable from the source, so this is a generous working limit rather
  /// than a claimed regulation.
  static const maxSamples = 60;

  /// Message: "Entered weight is too high. Please recheck the scale's reading."
  static String? eggMass(double? massG) {
    if (massG == null) return null;
    if (massG <= 0) return 'A weight of zero or less is not allowed.';
    if (massG > maxPlausibleEggMassG) {
      return "Entered weight is too high. Please recheck the scale's reading.";
    }
    return null;
  }

  /// Message: "The email address does not meet standard conventions."
  /// Blank is allowed — the check is on format, not presence.
  static String? email(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
    if (!pattern.hasMatch(trimmed)) {
      return 'The email address does not meet standard conventions. Please '
          'check and correct.';
    }
    return null;
  }

  /// Message: "The Haugh meter value cannot be 0 or less."
  static String? albumenHeight(double? value) {
    if (value == null) return null; // Not entered is allowed.
    if (value <= 0) {
      return 'The Haugh meter value cannot be 0 or less. Please check and '
          'correct.';
    }
    return null;
  }

  /// Rule: expiry may be neither in the past nor today.
  static String? bestBefore(DateTime? date, {DateTime? now}) {
    if (date == null) return null;
    final today = now ?? DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(today.year, today.month, today.day);
    if (d.isBefore(t)) {
      return "Best before date cannot be prior to today's date. Please "
          'correct.';
    }
    if (d.isAtSameMomentAs(t)) {
      return "Best before date cannot be set to today's date. Please correct.";
    }
    return null;
  }
}
