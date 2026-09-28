/// The store-level facts a visit shares with every inspection in it.
///
/// One store visit can hold several inspections — three poultry and three
/// egg captures at the same supermarket is a normal morning. Before this,
/// each form asked for the facility, the contact and the manager again, six
/// times over, and each record was signed separately. The visit captures the
/// store once; every inspection opened from it starts with these fields
/// already filled, and the signatures taken at the end of the visit are
/// written to every record in it.
///
/// This is a plain value object rather than a repository handle so the
/// commodity forms can accept it without depending on the visits feature.
class VisitPrefill {
  const VisitPrefill({
    required this.uuid,
    required this.facilityName,
    required this.facilityAddress,
    required this.facilityPhone,
    required this.contactPerson,
    required this.contactEmail,
    required this.representative,
    required this.managerName,
    required this.managerEmail,
    this.additionalEmail1 = '',
    this.additionalEmail2 = '',
    this.additionalEmail3 = '',
    this.facilityType = '',
    this.inspectionReason = '',
    this.distanceTravelledKm,
    this.producer = '',
  });

  /// The visit this inspection belongs to; stored on the record so the
  /// closing signatures can find their way back to it.
  final String uuid;

  final String facilityName;
  final String facilityAddress;
  final String facilityPhone;
  final String contactPerson;
  final String contactEmail;
  final String representative;
  final String managerName;
  final String managerEmail;

  /// Anyone else the documents go to, asked once on the visit rather than
  /// on each commodity form.
  final String additionalEmail1;
  final String additionalEmail2;
  final String additionalEmail3;

  /// The facility type chosen at the door, by name; empty when not chosen.
  final String facilityType;

  /// Why the inspector is here, chosen at the door, by name; empty when not
  /// chosen or on a visit started before the question moved there.
  final String inspectionReason;

  /// The producer / supplier named once on the visit, so every inspection
  /// under it starts with it filled in (Ethan, 2026-09-24).
  final String producer;

  /// The kilometres for the trip, asked once at the door. Null on a visit
  /// captured before the question moved there, and on a standalone record
  /// that has no visit behind it.
  final double? distanceTravelledKm;
}
