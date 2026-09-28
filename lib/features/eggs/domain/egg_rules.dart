import '../../../core/data/local_database.dart';
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
    //
    // Heaviest first, by mass rather than by the picker's display order.
    // Regulation R.345 Table 2 defines every size as "more than" its floor
    // (Medium: more than 43 g), so an egg sitting exactly on a boundary is
    // still the lighter size — 43 g is Small, and 33 g is no size at all.
    // Deriving this from sortOrder would have tied the result to however the
    // list happens to read on screen.
    final sorted = [
      for (final band in bands)
        if (band.isMassBand) band,
    ]..sort((a, b) => b.minMassG.compareTo(a.minMassG));
    for (final band in sorted) {
      final aboveFloor = massG > band.minMassG;
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
    // A grade can only be determined if some deviation is able to lower
    // it. With none in the reference carrying a downgrade — which is how
    // the Agency's list ships: the original never determined a grade, only
    // counted deviations against their bands — every egg came out as the
    // best grade whatever was found on it, and a decayed sample read
    // "Grade 1". Better to say nothing than to say that.
    if (!deviations.any((d) => d.downgradesToGradeId != null)) return null;
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
  /// The band the Agency allows for [deviationId] on a consignment declared
  /// [sizeId] and [gradeId], or null where the table has no row — which
  /// [isDeviationPermissible] reads as "any occurrence is a finding".
  static DeviationTolerance? toleranceFor({
    required int deviationId,
    required int sizeId,
    required int gradeId,
    required Iterable<DeviationTolerance> tolerances,
  }) {
    for (final t in tolerances) {
      if (t.deviationId == deviationId &&
          t.sizeId == sizeId &&
          t.gradeId == gradeId) {
        return t;
      }
    }
    return null;
  }

  /// What the count column says beside a tally, so a green count reads as
  /// "counted, and within what is allowed" rather than as nothing having
  /// happened. The Agency's table allows up to 100 of some deviations — more
  /// than a sample holds — and that is said plainly as no limit.
  static String toleranceLabel({
    required int count,
    required int deviationId,
    required int sizeId,
    required int gradeId,
    required Iterable<DeviationTolerance> tolerances,
    int sampleSize = 60,
  }) {
    final band = toleranceFor(
      deviationId: deviationId,
      sizeId: sizeId,
      gradeId: gradeId,
      tolerances: tolerances,
    );
    if (band == null) return '$count - not permitted';
    // A band pinned to one value is named before the width test: a band of
    // 60 to 60 on a 60-egg sample is not "no limit", it is exactly 60.
    if (band.minimum > 0 && band.maximum == band.minimum) {
      return '$count - exactly ${band.maximum} allowed';
    }
    if (band.maximum >= sampleSize) return '$count - no limit';
    return '$count of ${band.maximum} allowed';
  }

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
      checklists.values
          .any((ids) => ids.intersection(failedRequirementIds).isNotEmpty);

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

  // ------------------------------------------------------------------
  // Automatic deviations — the ticks the original's grading engine makes
  // by itself (`DoEggPoultryGradingAnalysis`), not the inspector. Two
  // families: the egg's weight against the declared size's minimum, and
  // its Haugh unit against the declared grade's reference value. They are
  // anchored on the deviation *descriptions* exactly as the original
  // anchors them, quirks included.
  // ------------------------------------------------------------------

  /// `AcceptableWeightToleranceBandGrams` — the 2 g band under a size's
  /// minimum that stays a within-band deviation.
  static const weightToleranceBandG = 2.0;

  /// `AcceptableHaughValueBelowMinAllowedValueToleranceBand` — the 5-unit
  /// band under the grade's reference Haugh value.
  static const haughShortfallBandUnits = 5.0;

  static const _overBandDescription = 'Egg Weight Difference >= 2g';
  static const _haughWithinDescription =
      'Haugh Value at least 55/35 units, Not more than 5 units lower than '
      'minimum';
  static const _haughBeyondDescription =
      'Haugh Value at least 55/35 units, More than 5 units lower than minimum';
  static const _pasteurisedWithinDescription =
      'Pasteurised 65 units, Not more than 5 units lower than minimum';
  static const _pasteurisedBeyondDescription =
      'Pasteurised 65 units, More than 5 units lower than minimum';

  static List<DeviationRef> _byIdOrder(List<DeviationRef> deviations) =>
      [...deviations]..sort((a, b) => a.id.compareTo(b.id));

  static int? _lastIdWhere(
    List<DeviationRef> deviations,
    bool Function(DeviationRef) test,
  ) {
    // The original selects with `LastOrDefault()` over the id-ordered seed;
    // that ordering is what makes "Jumbo" resolve to "Jumbo - <= 2g of
    // Min. Weight" rather than the Super Jumbo row it also matches.
    int? found;
    for (final d in _byIdOrder(deviations)) {
      if (test(d)) found = d.id;
    }
    return found;
  }

  /// Every deviation id the automatic logic may set or clear. The capture
  /// form strips these before re-deriving, so a stale automatic tick never
  /// survives the reading that no longer justifies it — the original clears
  /// them the same way when a weight is corrected.
  static Set<int> autoManagedDeviationIds(List<DeviationRef> deviations) => {
        for (final d in deviations)
          if (d.description.contains('<= 2g of Min. Weight') ||
              d.description == _overBandDescription ||
              d.description == _haughWithinDescription ||
              d.description == _haughBeyondDescription ||
              d.description == _pasteurisedWithinDescription ||
              d.description == _pasteurisedBeyondDescription)
            d.id,
      };

  /// The weight deviations this egg's mass forces, against the *declared*
  /// size — the original's underweight handling, exactly:
  ///
  /// - Grade 3 skips the weight checks entirely, unless the declared size is
  ///   Super Jumbo.
  /// - At or under the minimum (a difference of exactly 0 counts — the
  ///   original tests `weightDiff <= 0`, and R.345 Table 2 reads "more than"
  ///   the floor): within 2 g ticks the declared size's own "<= 2g of Min.
  ///   Weight" row; beyond 2 g ticks "Egg Weight Difference >= 2g". Small is
  ///   the exception the original makes and this now makes again: within 2 g
  ///   it ticks nothing at all, beyond 2 g it ticks the over-band row like
  ///   every other size. See the note at the exclusion below.
  /// - Above the minimum, nothing is ticked (and the form clears any earlier
  ///   automatic tick).
  static Set<int> autoWeightDeviationIds({
    required double? massG,
    required EggSizeBand? declaredSize,
    required EggGradeRef? declaredGrade,
    required List<DeviationRef> deviations,
  }) {
    if (massG == null || massG <= 0 || declaredSize == null) return const {};

    // "No Grade" is an FSA addition (2026-08-21) for consignments whose
    // label claims no grade at all. With nothing claimed there is nothing to
    // hold the weight against, so it takes Grade 3's path — the laxest the
    // original has.
    final grade3 =
        declaredGrade?.name == 'Grade 3' || declaredGrade?.name == 'No Grade';
    final superJumbo = declaredSize.name == 'Super Jumbo';
    if (grade3 && !superJumbo) return const {};

    final diff = massG - declaredSize.minMassG;
    if (diff > 0) return const {};

    final absDiff = diff.abs();
    if (absDiff <= weightToleranceBandG) {
      // Small is excluded from this band, as the original excludes it:
      //   if (absWeightDiff <= AcceptableWeightToleranceBandGrams
      //       && (SmallId != model.SelectedPoultryEggSizeTypeId))
      // (PoultryEggManager.cs:1270, dated 2022-06-23). A Small egg within 2 g
      // of the minimum therefore falls between the two branches and ticks
      // nothing — the over-band branch below needs more than 2 g.
      //
      // This reverses the 2026-08-28 reading of R.345 Table 4 item 9(a), which
      // held Small to the same rule as every other size. Restored to the
      // original's behaviour on Ethan's instruction, 2026-09-14, so the table
      // reads as the old app's does.
      if (declaredSize.name == 'Small') return const {};
      final id = _lastIdWhere(
        deviations,
        (d) => d.description.contains(declaredSize.name),
      );
      return id == null ? const {} : {id};
    }
    final id = _lastIdWhere(
      deviations,
      (d) => d.description == _overBandDescription,
    );
    return id == null ? const {} : {id};
  }

  /// The albumen-quality deviations this egg's Haugh unit forces, against
  /// the declared grade's reference — the original's logic, exactly:
  ///
  /// - Only an egg with a computed Haugh value above zero is examined.
  /// - Pasteurised consignments compare against 65 units for every grade,
  ///   and use *strict* inequalities: a shortfall of exactly 5 units ticks
  ///   neither row. (The original wrote `<` and `>` here where the fresh-egg
  ///   branch wrote `<=` — the boundary case slips through, and it ships.)
  /// - Fresh consignments compare against Grade 1 = 55, Grade 2 = 35,
  ///   Grade 3 = 0: within 5 units ticks the "Not more than 5" row, beyond
  ///   it the "More than 5" row.
  static Set<int> autoAlbumenDeviationIds({
    required double? haughUnit,
    required EggGradeRef? declaredGrade,
    required bool pasteurised,
    required List<DeviationRef> deviations,
  }) {
    if (haughUnit == null || haughUnit <= 0 || declaredGrade == null) {
      return const {};
    }

    if (pasteurised) {
      final diff = haughUnit - 65.0;
      if (diff >= 0) return const {};
      final absDiff = diff.abs();
      String? wanted;
      if (absDiff < haughShortfallBandUnits) {
        wanted = _pasteurisedWithinDescription;
      } else if (absDiff > haughShortfallBandUnits) {
        wanted = _pasteurisedBeyondDescription;
      }
      if (wanted == null) return const {};
      final id = _lastIdWhere(deviations, (d) => d.description == wanted);
      return id == null ? const {} : {id};
    }

    final reference = switch (declaredGrade.name) {
      'Grade 1' => 55.0,
      'Grade 2' => 35.0,
      _ => 0.0,
    };
    final diff = haughUnit - reference;
    if (diff >= 0) return const {};
    final absDiff = diff.abs();
    final wanted = absDiff <= haughShortfallBandUnits
        ? _haughWithinDescription
        : _haughBeyondDescription;
    final id = _lastIdWhere(deviations, (d) => d.description == wanted);
    return id == null ? const {} : {id};
  }

  /// `MinHaughMeterReadings` — the below-70 average is only evaluated once
  /// this many eggs have a computed Haugh unit.
  static const haughMinimumReadings = 2;

  /// `Constants.MaxHaughMeterReadings` — how many Haugh readings the sample
  /// set needs before the inspection can be signed off. The original counts
  /// the eggs carrying a reading above zero and calls the set complete at
  /// this many.
  static const haughReadingsRequired = 6;

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
    final measured = haughUnits.whereType<double>().length;
    // The original only evaluates the average once the minimum number of
    // readings exists (`MinHaughMeterReadings`).
    if (measured < haughMinimumReadings) return 0;
    final mean = meanHaughUnit(haughUnits);
    if (mean == null || mean >= haughAdditionalSampleThreshold) return 0;

    // With no baseline recorded, the shortfall is being evaluated for the
    // first time: the eggs on hand now are the baseline.
    final baseline = baselineCount ?? sampledCount;
    final shortfall = (baseline + haughAdditionalSampleCount) - sampledCount;
    return shortfall > 0 ? shortfall : 0;
  }

  // ---------------------------------------------------------------- seizure

  /// Why this consignment must be seized rather than given a period to put
  /// right, or empty when it need not be.
  ///
  /// Annexure D of FSA-SOP-APS-001 draws the line at *omission*: a size or
  /// grade designation that is not indicated at all, or a missing tray-size
  /// indication, is an immediate seizure under section 8, while a wrong or
  /// misleading indication is a 30-day rectification like any other
  /// deviation. The handset treated both the same, so a consignment the SOP
  /// says to seize went out with a rectification date on it.
  ///
  /// Each answer comes from the inspector saying "Not indicated" on the
  /// picker; nothing is inferred from a blank, because a blank means the
  /// question has not been reached yet.
  static List<String> seizureReasons({
    required bool sizeNotIndicated,
    required bool gradeNotIndicated,
    required bool trayNotIndicated,
    bool eggsExpressionAbsent = false,
    bool bestBeforeAbsent = false,
    bool looseQuantityFailed = false,
    bool qualityStandardFailed = false,
  }) =>
      [
        if (sizeNotIndicated)
          'The size designation is not indicated on the pack (Reg. 10).',
        if (gradeNotIndicated)
          'The grade designation is not indicated on the pack (Reg. 10).',
        if (trayNotIndicated)
          'The tray packaging size is not indicated on the pack (Reg. 10).',
        if (eggsExpressionAbsent)
          'The expression "Eggs" is not indicated on the pack (Reg. 8(1)(b)).',
        if (bestBeforeAbsent)
          'No best-before date is indicated on the pack (Reg. 8(1)(f)).',
        if (looseQuantityFailed)
          'Eggs sold loose without the size and grade indicated (Reg. 12).',
        if (qualityStandardFailed)
          'The eggs do not meet the size or grade standard they are sold as '
              '(Reg. 3 and 5).',
      ];

  /// Whether the findings require a seizure rather than a rejection.
  static bool seizureRequired({
    required bool sizeNotIndicated,
    required bool gradeNotIndicated,
    required bool trayNotIndicated,
    bool eggsExpressionAbsent = false,
    bool bestBeforeAbsent = false,
    bool looseQuantityFailed = false,
    bool qualityStandardFailed = false,
  }) =>
      seizureReasons(
        sizeNotIndicated: sizeNotIndicated,
        gradeNotIndicated: gradeNotIndicated,
        trayNotIndicated: trayNotIndicated,
        eggsExpressionAbsent: eggsExpressionAbsent,
        bestBeforeAbsent: bestBeforeAbsent,
        looseQuantityFailed: looseQuantityFailed,
        qualityStandardFailed: qualityStandardFailed,
      ).isNotEmpty;

  // --------------------------------------------------------------------
  // FSA-SOP-APS-001, Annexure D (Eggs — Non-Conformance Table, 11 June
  // 2026). The period a rejection carries follows from the deviation, not
  // from the inspector's choice (Ethan, 2026-09-26):
  //
  //   Container / outer container (Reg. 6) .... rectify immediately
  //   Size and grade designation (Reg. 10) .... seizure if omitted; 30 days
  //   Expression "Eggs" (Reg. 8(1)(b)) ......... seizure if omitted; 30 days
  //   Indication of packer (Reg. 11) ........... 30 days
  //   Best before (Reg. 8(1)(f)) ............... seizure if omitted; 30 days
  //   "Oiled" (Reg. 8(1)(g)) ................... 30 days
  //   Production method (Reg. 8(2)–(5)) ........ 30 days
  //   Imported / country of origin (Reg. 8(8)) . 3 days
  //   Loose quantities (Reg. 12) ............... seizure / rectify at once
  //   Restricted particulars (Reg. 13) ......... 30 days
  //   Species (Reg. 8(1)(e)) ................... 30 days
  //   Size and grade standards (Reg. 3, 5) ..... seizure / rectify at once
  //
  // Whether "Eggs" or the best-before date was omitted rather than wrong
  // is the inspector's answer when the row is unticked.
  // --------------------------------------------------------------------

  static bool isEggsExpressionRow(EggRequirement r) =>
      r.description.contains('Expressions: Eggs');
  static bool isBestBeforeRow(EggRequirement r) =>
      r.description.contains('Best Before');
  static bool isLooseQuantityRow(EggRequirement r) =>
      r.description.contains('Loose Quanti');
  static bool isCountryOfOriginRow(EggRequirement r) =>
      r.description.toLowerCase().contains('country of origin');

  /// What the annexure prescribes for one failed requirement.
  static EggAction actionForRequirement(
    EggRequirement r, {
    required bool eggsExpressionAbsent,
    required bool bestBeforeAbsent,
  }) {
    if (r.kind == 'packing') return EggAction.rectifyNow;
    if (isLooseQuantityRow(r)) return EggAction.seizeOrRectifyNow;
    if (isEggsExpressionRow(r)) {
      return eggsExpressionAbsent ? EggAction.seize : EggAction.rectify30Days;
    }
    if (isBestBeforeRow(r)) {
      return bestBeforeAbsent ? EggAction.seize : EggAction.rectify30Days;
    }
    if (isCountryOfOriginRow(r)) return EggAction.rectify3Days;
    return EggAction.rectify30Days;
  }

  /// Days the annexure allows, counted from the inspection. A deviation it
  /// seizes on has none; should the inspector carry on instead of seizing,
  /// the rejection runs from today.
  static int daysFor(EggAction action) => switch (action) {
        EggAction.seize => 0,
        EggAction.seizeOrRectifyNow => 0,
        EggAction.rectifyNow => 0,
        EggAction.rectify3Days => 3,
        EggAction.rectify30Days => 30,
      };

  /// The labelling part's period: the shortest the annexure gives any of
  /// the failed rows, or none when nothing failed. A designation omitted
  /// altogether ([designationOmitted]) is a seizure, so it runs from today.
  static int? labellingRectificationDays({
    required Iterable<EggRequirement> failed,
    required bool eggsExpressionAbsent,
    required bool bestBeforeAbsent,
    bool designationOmitted = false,
  }) {
    int? shortest = designationOmitted ? 0 : null;
    for (final r in failed) {
      final d = daysFor(actionForRequirement(r,
          eggsExpressionAbsent: eggsExpressionAbsent,
          bestBeforeAbsent: bestBeforeAbsent));
      if (shortest == null || d < shortest) shortest = d;
    }
    return shortest;
  }

  /// The quality part: eggs not meeting the size or grade standard they
  /// are sold as are seized or put right at once (Reg. 3 and 5).
  static const int qualityRectificationDays = 0;

  /// "Correct by" — the inspection date plus the period, as a date.
  static DateTime correctBy({required DateTime inspectedAt, required int days}) =>
      DateTime(inspectedAt.year, inspectedAt.month, inspectedAt.day)
          .add(Duration(days: days));

  /// How the period reads on the form and the sheet.
  static String periodLabel(int days) => switch (days) {
        0 => 'Rectify immediately',
        3 => '3-day rectification notice',
        30 => '30-day rectification notice',
        _ => '$days-day rectification notice',
      };
}

/// What FSA-SOP-APS-001 Annexure D prescribes for a deviation.
enum EggAction {
  seize,

  /// "Immediate seizure / rectify immediately".
  seizeOrRectifyNow,
  rectifyNow,
  rectify3Days,
  rectify30Days,
}

/// Field-level validation, kept beside the rules it enforces.
///
/// Each message belongs to a check the capture form
/// performed, so an inspector moving between the two apps sees the same
/// constraints.
abstract final class EggValidation {
  /// Whether the record has to carry weighed eggs.
  ///
  /// At a retailer the inspector may record that no weighing was possible —
  /// eggs cannot be broken open on the shop floor. That takes the sizing and
  /// grading block off the screen, so the saved record cannot be expected to
  /// hold samples: demanding one there blocks the save with an instruction
  /// the form no longer offers any way to satisfy.
  static bool samplesRequired({required bool weighingNotRequired}) =>
      !weighingNotRequired;

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

  /// Message: "Maximum number of samples reached!". The original's
  /// `MaxPoultryEggSampleSetSize` — 60 in the production build (5 only under
  /// its internal-testing compile flag).
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
  /// Whether the best-before date as written on the pack is acceptable
  /// input. Any date is: the inspector records what the label says.
  ///
  /// The original refused anything before tomorrow ("Best before date
  /// cannot be prior to today's date"), which meant a pack already past its
  /// date — the very thing an inspector is there to find — could not be
  /// captured at all. A passed date is a finding for the checklist and the
  /// rejection, not a reason to refuse the record (Ethan, 2026-09-23).
  static String? bestBefore(DateTime? date, {DateTime? now}) => null;

  /// Whether the date on the pack has already passed, for the note the form
  /// shows beside it. Today counts as passed: a "best before" is the last
  /// day the claim holds, so stock still on sale on that day is already at
  /// the edge of it.
  static bool bestBeforeHasPassed(DateTime? date, {DateTime? now}) {
    if (date == null) return false;
    final today = now ?? DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(today.year, today.month, today.day);
    return !d.isAfter(t);
  }
}

/// The reference number a rejection carries, built the way the original app
/// built `UniqueReferenceNumber` (NewPoultyEggInspectionPage, 2021-05-14):
/// `{client id}-{inspector id}-{yyyyMMdd}-{sequence:000}`, where the sequence
/// counts the rejections this inspector has issued today, starting at 1.
///
/// Generated, never typed: the original showed no field for it, and a number
/// an inspector invents cannot be traced back to a client, an inspector and a
/// day the way this one can.
abstract final class EggDirectionNumber {
  static String generate({
    required int clientId,
    required int inspectorId,
    required DateTime on,
    required int issuedTodayBefore,
  }) {
    final date = '${on.year}'
        '${on.month.toString().padLeft(2, '0')}'
        '${on.day.toString().padLeft(2, '0')}';
    final sequence = (issuedTodayBefore + 1).toString().padLeft(3, '0');
    return '$clientId-$inspectorId-$date-$sequence';
  }
}
