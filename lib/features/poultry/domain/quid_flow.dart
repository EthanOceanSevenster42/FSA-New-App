import 'dart:convert';

import 'quid_determination.dart';

/// The order a QUID determination is weighed in, and what each stage needs
/// before the next one opens — as the original's weighing screen runs it
/// (`ContinuePoultryInjectionInspectionPage`, with `DIRECTION_ITERATION_
/// CHECK_ON` defined).
///
/// 1. **Chilling.** Each carcass is weighed on the way in; water-chilled
///    carcasses are weighed again off the chiller. The stage closes with at
///    least five carcasses. For water chilling the average pick-up may not
///    exceed 7% — over it, the sample set is weighed again, and over it on
///    the second round a rejection is issued.
/// 2. **Injector.** Each carcass is assigned to an injector and weighed on
///    and off it. The stage closes with at least five carcasses per
///    injector.
/// 3. **Determination of QUID.** Each carcass is weighed off the process;
///    its QUID is (final − initial) / final × 100 against the initial
///    weight from stage 1. The stage closes with at least five per injector.
///    An injector over its limit on the first round means the whole
///    determination is repeated; over it on the second, a rejection.
///
/// Two rounds at most (`MaxInspectionIterationCount`).

/// `MaxAcceptableWaterPickUpPercentage` / `MaxWaterChillingPickupPercentage`.
const double quidMaxWaterPickupPercent = 7.0;

/// `MaxInspectionIterationCount`.
const int quidMaxIterations = 2;

/// The regulated QUID an injector is held to when the plant has no
/// dispensation: 10% on whole carcasses, 15% on cuts.
double quidRegulatedPercent({required bool isWholeCarcass}) =>
    isWholeCarcass ? quidWholeCarcassMaximum : quidCutPortionMaximum;

/// Where a determination stands.
enum QuidStage { chilling, injector, determination, finished }

QuidStage quidStage({
  required bool chillingComplete,
  required bool injectorComplete,
  required bool determinationComplete,
}) {
  if (!chillingComplete) return QuidStage.chilling;
  if (!injectorComplete) return QuidStage.injector;
  if (!determinationComplete) return QuidStage.determination;
  return QuidStage.finished;
}

/// Whether a carcass's water pick-up is within the 7%.
bool quidWaterPickupPasses(String percent) {
  final p = quidNumber(percent);
  return p != null && p <= quidMaxWaterPickupPercent;
}

/// One carcass, as the stage checks see it.
typedef QuidStageSample = ({
  String initial,
  String waterFinal,
  int? injector,
  String injectorAfter,
  String quidPercent,
});

/// What stops the chilling stage closing, or null when it may.
String? quidChillingBlocked(List<QuidStageSample> samples,
    {required bool isWaterChilled}) {
  final done = samples
      .where(
          (s) => quidNumber(isWaterChilled ? s.waterFinal : s.initial) != null)
      .length;
  if (done < quidMinimumSampleSet) {
    return 'A minimum of five (5) samples is required, before an average '
        'Pickup percentage can calculated.';
  }
  return null;
}

/// What stops the injector stage closing, or null when it may.
String? quidInjectorBlocked(
    List<QuidStageSample> samples, List<int> injectorPositions) {
  for (final position in injectorPositions) {
    final count = samples
        .where((s) =>
            s.injector == position && quidNumber(s.injectorAfter) != null)
        .length;
    if (count < quidMinimumSampleSet) {
      return 'At least one or more of the Injectors has not all the min. of '
          'samples captured. Please address.';
    }
  }
  return null;
}

/// What stops the determination closing, or null when it may.
String? quidDeterminationBlocked(
    List<QuidStageSample> samples, List<int> injectorPositions) {
  for (final position in injectorPositions) {
    final count = samples
        .where(
            (s) => s.injector == position && quidNumber(s.quidPercent) != null)
        .length;
    if (count < quidMinimumSampleSet) {
      return 'An insufficient number of samples for QUID calculation has been '
          'completed for each Injector.';
    }
  }
  return null;
}

/// What happens when a stage closes on a failure.
enum QuidFailureStep {
  /// Weigh a new sample set: this was the first round.
  repeat,

  /// Issue a rejection: there is no round left.
  reject,
}

QuidFailureStep quidOnFailure(int iteration) => iteration < quidMaxIterations
    ? QuidFailureStep.repeat
    : QuidFailureStep.reject;

/// `MinDirectionPhotos`: the photographs a rejection needs before the
/// checklist can be submitted. The original takes them from the rejection
/// block itself ("Add Photo [0/2]") and asks for none when there is no
/// rejection — the weighing has no photo button of its own.
const int quidMinRejectionPhotos = 2;

/// Whether a rejection still owes photographs.
bool quidRejectionPhotosOutstanding(int taken) =>
    taken < quidMinRejectionPhotos;

/// One "Verification of Records" entry. The original keeps a list — Add
/// puts the entry on it and clears the boxes for the next document — and
/// each entry carries a photograph of the document: its "Take Photo" opens
/// once the document is named, and Add only once the photo is taken.
class QuidVerificationRecord {
  const QuidVerificationRecord({
    required this.date,
    required this.documentName,
    required this.verified,
    required this.deviationPresent,
    this.deviationComment = '',
    this.photoPath = '',
  });

  final DateTime? date;
  final String documentName;
  final bool verified;
  final bool deviationPresent;
  final String deviationComment;

  /// Where the photograph of the document lives on the handset. It is also
  /// on the record's photo list, kind `document`, which is how it reaches
  /// the server.
  final String photoPath;

  bool get hasPhoto => photoPath.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
        'date': date?.toIso8601String().split('T').first,
        'document_name': documentName,
        'verified': verified,
        'deviation_present': deviationPresent,
        'deviation_comment': deviationComment,
        'photo_path': photoPath,
      };

  static QuidVerificationRecord fromJson(Map<String, Object?> j) =>
      QuidVerificationRecord(
        date: DateTime.tryParse('${j['date'] ?? ''}'),
        documentName: '${j['document_name'] ?? ''}',
        verified: j['verified'] == true,
        deviationPresent: j['deviation_present'] == true,
        deviationComment: '${j['deviation_comment'] ?? ''}',
        photoPath: '${j['photo_path'] ?? ''}',
      );

  static String encode(List<QuidVerificationRecord> records) =>
      records.isEmpty ? '' : jsonEncode([for (final r in records) r.toJson()]);

  static List<QuidVerificationRecord> decode(String stored) {
    if (stored.trim().isEmpty) return const [];
    try {
      final raw = jsonDecode(stored);
      if (raw is! List) return const [];
      return [
        for (final row in raw)
          if (row is Map) fromJson(row.cast<String, Object?>()),
      ];
    } on FormatException {
      return const [];
    }
  }
}

/// The carcasses of the last round weighed — the round a determination is
/// judged on. A first round that failed stays on the record, but it is the
/// repeat that decides.
List<T> quidLastRound<T>(List<T> samples, int Function(T) iterationOf) {
  if (samples.isEmpty) return samples;
  final last = samples.map(iterationOf).reduce((a, b) => a > b ? a : b);
  return [
    for (final s in samples)
      if (iterationOf(s) == last) s,
  ];
}
