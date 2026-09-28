import 'package:drift/drift.dart';

/// One store visit: the facility captured once, shared by every inspection
/// made under it, and signed once at the end.
///
/// The visit is a capture convenience, not a server concept — each member
/// inspection still uploads as its own complete record, carrying the
/// facility details and the signatures the visit stamped into it. The
/// backend never needs to know visits exist.
class StoreVisits extends Table {
  TextColumn get uuid => text()();

  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityPhone => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get contactEmail => text().withDefault(const Constant(''))();
  TextColumn get representative => text().withDefault(const Constant(''))();
  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();

  /// Anyone else who should receive the documents for this visit — head
  /// office, a group quality manager. The original asks for these on every
  /// commodity form ("Email address #1 / #2"); a visit is one errand to one
  /// site, so they are asked once here and carried onto each record.
  TextColumn get additionalEmail1 => text().withDefault(const Constant(''))();
  TextColumn get additionalEmail2 => text().withDefault(const Constant(''))();

  /// A third, offered only once the first two are used — some groups copy
  /// head office as well as the store and its quality manager.
  TextColumn get additionalEmail3 => text().withDefault(const Constant(''))();

  /// What the invoice is billed on, for the whole trip.
  ///
  /// One journey to one facility, so it is asked once at the door rather
  /// than on every inspection captured there. It used to live only on the
  /// raw record: two raw inspections in a visit asked for it twice and the
  /// invoice kept whichever it read first.
  RealColumn get distanceTravelledKm => real().nullable()();

  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();

  /// How many of each commodity the inspector planned for this visit —
  /// "2 poultry and 2 raw" — set up front, so the flow can walk them
  /// through the plan commodity by commodity.
  IntColumn get plannedEggs => integer().withDefault(const Constant(0))();
  IntColumn get plannedPoultry => integer().withDefault(const Constant(0))();
  IntColumn get plannedLabels => integer().withDefault(const Constant(0))();
  IntColumn get plannedRaw => integer().withDefault(const Constant(0))();
  IntColumn get plannedPmp => integer().withDefault(const Constant(0))();

  /// The commodities in the order the inspector planned them, comma
  /// separated — "rawrmp,egg".
  ///
  /// The flow used to walk a fixed list, so it always opened eggs first
  /// however the plan was set. An inspector who is doing the raw counter
  /// first and the eggs after was made to work in the app's order rather
  /// than the store's. The order the counters were raised in is the order
  /// the work is actually done in, so it is what the plan is walked in.
  TextColumn get planOrder => text().withDefault(const Constant(''))();

  /// Answered at the door: is this visit an occurrence report? The report
  /// itself lives on APS; the handset only carries the answer.
  BoolColumn get isOccurrenceReport =>
      boolean().withDefault(const Constant(false))();

  /// Chosen once at the door for the whole group, by name, so each
  /// commodity's form can find its own row for it.
  TextColumn get facilityType => text().withDefault(const Constant(''))();

  /// Why the inspector is here, answered once at the door for the whole
  /// group, by name — the commodity lists spell it differently ("Follow Up"
  /// against "Follow-up Inspection"), so each form matches its own row.
  /// Before this the same question was put again on every inspection inside
  /// the visit.
  TextColumn get inspectionReason => text().withDefault(const Constant(''))();

  /// The occurrence report as written at the door: when the inspector was
  /// there, the premises' registration code, and what happened. The
  /// photographs live in [VisitOccurrencePhotos].
  TextColumn get occurrenceTimeOfVisit =>
      text().withDefault(const Constant(''))();
  TextColumn get occurrenceRegistrationCode =>
      text().withDefault(const Constant(''))();
  TextColumn get occurrenceDescription =>
      text().withDefault(const Constant(''))();

  /// The closing signatures, kept on the visit itself so a visit with no
  /// inspections (an occurrence report) still has them for its document.
  TextColumn get managerSignaturePath =>
      text().withDefault(const Constant(''))();
  TextColumn get inspectorSignaturePath =>
      text().withDefault(const Constant(''))();

  DateTimeColumn get startedAt => dateTime()();

  /// Set when the closing signatures have been taken and stamped into every
  /// member inspection. A completed visit no longer accepts members.
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Whether the signed-off group itself has reached the server. The
  /// members upload through their own commodity endpoints; this is the
  /// group that ties them together, and the office's record is made from
  /// it.
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();

  /// When the inspector approved the visit in Inspection Management, after
  /// it reached the server and its documents were looked over.
  DateTimeColumn get approvedAt => dateTime().nullable()();

  /// Whether the server holds the current answer — approved, or taken back
  /// again (Ethan, 2026-09-24). False only after the inspector has changed
  /// it; Server Sync sends any that are still waiting.
  BoolColumn get approvalSent => boolean().withDefault(const Constant(true))();

  /// The producer / supplier, asked once for the whole visit and filled in
  /// on every inspection under it (Ethan, 2026-09-24).
  TextColumn get producerName => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {uuid};
}

/// Photographs taken for an occurrence report; bound into the Occurrence
/// Document (PDF) when the visit is uploaded.
class VisitOccurrencePhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get visitUuid => text()();
  TextColumn get filePath => text()();
  DateTimeColumn get capturedAt => dateTime()();
}
