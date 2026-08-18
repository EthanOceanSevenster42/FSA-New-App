import 'package:flutter/foundation.dart';

/// A grading tolerance: for [defectGroupId] on a commodity, class [gradeId]
/// (rank [gradeRank]) permits at most [maxPercentage] of the sample.
@immutable
class Tolerance {
  const Tolerance({
    required this.defectGroupId,
    required this.gradeId,
    required this.gradeRank,
    required this.gradeName,
    required this.maxPercentage,
  });

  final int defectGroupId;
  final int gradeId;
  final int gradeRank;
  final String gradeName;
  final double maxPercentage;
}

/// A measured defect on the sample.
@immutable
class DefectMeasurement {
  const DefectMeasurement({
    required this.defectGroupId,
    required this.defectGroupName,
    this.count,
    this.weightG,
  });

  final int defectGroupId;
  final String defectGroupName;

  /// External defects are counted against the sample's unit count.
  final int? count;

  /// Internal defects are weighed against the sample's mass.
  final double? weightG;
}

/// Why a particular defect group forced the class it did.
@immutable
class GradeReason {
  const GradeReason({
    required this.defectGroupName,
    required this.percentage,
    required this.gradeName,
    required this.toleranceApplied,
  });

  final String defectGroupName;
  final double percentage;
  final String gradeName;

  /// The band the measurement fell within, or null when it exceeded them all.
  final double? toleranceApplied;
}

@immutable
class GradingResult {
  const GradingResult({
    required this.gradeId,
    required this.gradeName,
    required this.reasons,
    required this.percentages,
  });

  /// Null when no tolerance table covers the commodity — the engine refuses to
  /// guess. Defaulting to a class in that situation would be a fabrication.
  final int? gradeId;
  final String gradeName;

  /// One entry per measured defect group, worst first.
  final List<GradeReason> reasons;

  /// defectGroupId -> percentage of sample.
  final Map<int, double> percentages;

  bool get isDetermined => gradeId != null;
}

/// Determines the class of a Fruit & Veg sample from measured defects.
///
/// Grading expressed as a
/// pure function over synced tolerance data. Pure and synchronous by design:
/// it takes data in and returns a result, so it can be exhaustively tested
/// without a database, a network, or a widget tree.
///
/// Rules:
///  * Each defect group's measurement is converted to a percentage of sample.
///  * The group takes the best class whose tolerance it does not exceed.
///  * The overall result is the WORST class across all groups.
///  * Exceeding every band yields the lowest-ranked grade available.
abstract final class GradingEngine {
  /// [sampleUnitCount] is used for counted defects, [sampleWeightG] for
  /// weighed ones. A measurement whose denominator is missing or zero is
  /// skipped rather than treated as 0% — silently scoring it as clean would
  /// be the dangerous failure here.
  static GradingResult grade({
    required List<DefectMeasurement> defects,
    required List<Tolerance> tolerances,
    int? sampleUnitCount,
    double? sampleWeightG,
  }) {
    if (tolerances.isEmpty) {
      return const GradingResult(
        gradeId: null,
        gradeName: 'No grading rules for this commodity',
        reasons: [],
        percentages: {},
      );
    }

    final byGroup = <int, List<Tolerance>>{};
    for (final t in tolerances) {
      (byGroup[t.defectGroupId] ??= []).add(t);
    }
    for (final list in byGroup.values) {
      list.sort((a, b) => a.gradeRank.compareTo(b.gradeRank));
    }

    // The worst class the tolerance table knows about — used when a
    // measurement exceeds every band.
    final worstAvailable = tolerances.reduce(
      (a, b) => a.gradeRank >= b.gradeRank ? a : b,
    );
    // The best class, which is the result when nothing is wrong.
    final bestAvailable = tolerances.reduce(
      (a, b) => a.gradeRank <= b.gradeRank ? a : b,
    );

    final percentages = <int, double>{};
    final reasons = <GradeReason>[];
    Tolerance worst = bestAvailable;

    for (final d in defects) {
      final pct = percentageFor(
        defect: d,
        sampleUnitCount: sampleUnitCount,
        sampleWeightG: sampleWeightG,
      );
      if (pct == null) continue;
      percentages[d.defectGroupId] = pct;

      final bands = byGroup[d.defectGroupId];
      if (bands == null || bands.isEmpty) {
        // Measured a defect with no rule for it. Do not silently ignore.
        reasons.add(
          GradeReason(
            defectGroupName: d.defectGroupName,
            percentage: pct,
            gradeName: 'No rule',
            toleranceApplied: null,
          ),
        );
        continue;
      }

      Tolerance? matched;
      for (final band in bands) {
        if (pct <= band.maxPercentage) {
          matched = band;
          break;
        }
      }
      final applied = matched ?? worstAvailable;
      if (applied.gradeRank > worst.gradeRank) worst = applied;

      reasons.add(
        GradeReason(
          defectGroupName: d.defectGroupName,
          percentage: pct,
          gradeName: applied.gradeName,
          toleranceApplied: matched?.maxPercentage,
        ),
      );
    }

    reasons.sort((a, b) => b.percentage.compareTo(a.percentage));

    return GradingResult(
      gradeId: worst.gradeId,
      gradeName: worst.gradeName,
      reasons: reasons,
      percentages: percentages,
    );
  }

  /// Percentage of the sample a measurement represents, or null when it cannot
  /// be computed. Never returns 0 as a stand-in for "unknown".
  @visibleForTesting
  static double? percentageFor({
    required DefectMeasurement defect,
    int? sampleUnitCount,
    double? sampleWeightG,
  }) {
    if (defect.weightG != null) {
      if (sampleWeightG == null || sampleWeightG <= 0) return null;
      return (defect.weightG! / sampleWeightG) * 100;
    }
    if (defect.count != null) {
      if (sampleUnitCount == null || sampleUnitCount <= 0) return null;
      return (defect.count! / sampleUnitCount) * 100;
    }
    return null;
  }
}
