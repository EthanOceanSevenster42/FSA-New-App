/// Which raw record this is: the raw inspection, or the compositional
/// checklist on its own (Ethan, 2026-09-24).
///
/// Asked when the record is started, the way poultry asks between labelling
/// and QUID, so the form shows only the part the inspector is there to do.
/// Records captured before the question existed hold neither answer and
/// keep showing both parts, as they did.
enum RawRecordKind {
  /// Before the question was asked: both parts, as they were.
  both(''),

  /// Labels, containers, sampling and the laboratory.
  inspection('inspection'),

  /// SOP-APS-RAW-003, the compositional requirements checklist.
  composition('composition');

  const RawRecordKind(this.stored);

  final String stored;

  static RawRecordKind of(String stored) => values.firstWhere(
        (k) => k.stored == stored,
        orElse: () => RawRecordKind.both,
      );

  bool get showsInspection => this != RawRecordKind.composition;
  bool get showsComposition => this != RawRecordKind.inspection;

  /// What the record is called in a visit and on the form.
  String get title => switch (this) {
        RawRecordKind.composition => 'Compositional Checklist',
        _ => 'Certain Raw Processed Meat Product Inspection',
      };
}
