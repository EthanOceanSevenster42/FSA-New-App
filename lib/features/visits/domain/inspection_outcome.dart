/// What an inspection came to: the deviations found, and whether the
/// product met the regulation.
///
/// The office reads this off the record rather than pressing a compliant /
/// non-compliant button, so it has to be derived the same way every time.
/// Keeping it here — plain values, no database, no widgets — is what lets
/// it be exercised directly.
class InspectionOutcome {
  const InspectionOutcome({required this.findings, required this.isCompliant});

  /// The deviations, as the checklist words them, in the order the
  /// requirements are listed and without repeats.
  final List<String> findings;

  /// True when nothing was found, false when something was, and **null when
  /// the checklist was never worked**.
  ///
  /// The three are different answers and APS shows them differently. An
  /// inspection nobody assessed must not arrive looking like a pass.
  final bool? isCompliant;

  /// The findings as the office system carries them: one per line.
  String get findingsText => findings.join('\n');

  static const none = InspectionOutcome(findings: [], isCompliant: null);
}

/// One requirement on a checklist, as the rule needs to see it.
typedef ChecklistRequirement = ({
  int id,
  String section,
  String description,
  String regulation,
});

abstract final class InspectionFindings {
  /// The outcome of a tick-the-compliant-rows checklist.
  ///
  /// Every commodity works the same way: the inspector says which blocks
  /// were present at the premises and ticks the requirements that were met,
  /// so a deviation is an applicable requirement that was *not* ticked.
  ///
  /// [checklistWorked] is what separates "nothing was wrong" from "nobody
  /// looked". A record with no ticks at all has not been assessed, and
  /// saying otherwise would put a pass on the file the inspector never
  /// gave.
  static InspectionOutcome fromChecklist({
    required List<ChecklistRequirement> requirements,
    required Set<String> sectionsPresent,
    required Set<int> compliantIds,
    required bool checklistWorked,
    List<String> extraFindings = const [],
  }) {
    final applicable = [
      for (final r in requirements)
        if (sectionsPresent.contains(r.section)) r,
    ];
    final found = <String>[];
    // An unticked row is only a deviation if the checklist was worked at
    // all. On a checklist nobody opened, every row is unticked — reading
    // those as findings would put deviations on the record that no
    // inspector ever saw.
    if (checklistWorked) {
      for (final requirement in applicable) {
        if (compliantIds.contains(requirement.id)) continue;
        found
            .add('${requirement.description} ${requirement.regulation}'.trim());
      }
    }
    // A deviation the inspector wrote in their own words counts too, but it
    // is not evidence that the checklist was worked.
    for (final extra in extraFindings) {
      final trimmed = extra.trim();
      if (trimmed.isNotEmpty) found.add(trimmed);
    }
    final deduped = found.toSet().toList();

    if (!checklistWorked || applicable.isEmpty) {
      // Nothing was worked through, so there is nothing to pass. A
      // deviation the inspector wrote in their own words is different:
      // they saw it, so the product failed on it whatever the checklist
      // says.
      return InspectionOutcome(
        findings: deduped,
        isCompliant: deduped.isEmpty ? null : false,
      );
    }
    return InspectionOutcome(findings: deduped, isCompliant: deduped.isEmpty);
  }
}
