import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/data/sqlite_connection.dart';
import '../../../core/services/in_app_camera.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/search_picker.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import 'poultry_evidence_section.dart';
import 'poultry_form_widgets.dart';
import '../domain/poultry_rules.dart';
import '../../../core/widgets/correct_by_date_field.dart';

/// New Grading and Classification Checklist.
///
/// Follows the original screen's order so an inspector working from the paper
/// form fills the two in the same sequence: where and why, then the facility,
/// then what is being inspected, then the three tick-lists, then remarks.
///
/// The tick-lists read "No deviation" because that is what a tick means here —
/// the original's column header. Labelling them "Deviation" would invert every
/// record captured.
///
/// Restricted particulars are not asked here. The original's grading screen
/// has no such block — they are a labelling matter, and the Label/Container
/// checklist is where they are captured.
/// What a label checklist hands to the grading checklist that follows it.
class PoultryLabelCarryOver {
  const PoultryLabelCarryOver({
    required this.registrationNumber,
    required this.productDetails,
  });

  final String registrationNumber;
  final String productDetails;
}

/// What the grading takes from the Label/Container Checklist it sits under,
/// read each time it is written, so a correction made up there reaches the
/// grading record too.
typedef PoultryGradingHost = ({
  int? reasonId,
  int? locationId,
  String facilityName,
  String tradingName,
  String facilityAddress,
  String facilityTelephone,
  String registrationNumber,
  String contactPerson,
  String contactEmail,
  String productName,
  String managerName,
  String managerEmail,
  String clientEmail,
  String clientEmail2,
});

/// Lets the label checklist the grading sits under finish or save it with
/// its own buttons.
class PoultryGradingController {
  Future<bool> Function({bool hostSeized})? _finish;
  Future<void> Function()? _save;

  /// Whether the grading is on the form to be asked.
  bool get attached => _finish != null;

  /// Checks the grading is complete, marking what is not, and records it
  /// as finished. False while something is still to do.
  /// [hostSeized]: the label checklist it sits under was seized, so the
  /// grading closes with it and asks nothing more.
  Future<bool> finish({bool hostSeized = false}) =>
      _finish?.call(hostSeized: hostSeized) ?? Future.value(false);

  /// Keeps the grading as it stands, as a draft.
  Future<void> save() => _save?.call() ?? Future.value();
}

class PoultryInspectionForm extends StatefulWidget {
  const PoultryInspectionForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.existingUuid,
    this.visit,
    this.carriedOver,
    this.embedded = false,
    this.controller,
    this.host,
    this.onNoGrade,
    this.onSeized,
    this.hostSeized = false,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;

  /// What the label checklist already captured about this product, when
  /// grading follows it.
  final PoultryLabelCarryOver? carriedOver;

  /// Set when resuming a draft.
  final String? existingUuid;

  /// Set when this inspection belongs to a store visit: the facility fields
  /// arrive filled and the signatures are taken once, at the end of the
  /// visit.
  final VisitPrefill? visit;

  /// Drawn underneath the labelling on the Label/Container Checklist rather
  /// than on a screen of its own: what that form already asks — the reason,
  /// the facility, the registration number, the product name, signatures
  /// and its buttons — is not asked again (Ethan, 2026-09-29).
  final bool embedded;

  /// How the label checklist finishes or saves it.
  final PoultryGradingController? controller;

  /// What the label checklist has captured.
  final PoultryGradingHost Function()? host;

  /// "No Grade" chosen on the label checklist: grading is answered NO there
  /// instead of leaving the form.
  final VoidCallback? onNoGrade;

  /// Under the label checklist, a seizure raised here: that form finishes
  /// both, since it holds the Complete (Ethan, 2026-09-30).
  final VoidCallback? onSeized;

  /// The label checklist this sits under has been seized: the product is
  /// taken, so no grade or sample is asked here (Ethan, 2026-09-30).
  final bool hostSeized;

  @override
  State<PoultryInspectionForm> createState() => _PoultryInspectionFormState();
}

class _Reference {
  _Reference({
    required this.meatTypes,
    required this.grades,
    required this.portionTypes,
    required this.designations,
    required this.altDesignations,
    required this.links,
    required this.altLinks,
    required this.checklist,
    required this.reasons,
    required this.locations,
    required this.remarks,
    required this.facilities,
  });

  final List<PoultryMeatTypeRef> meatTypes;
  final List<PoultryGradeRef> grades;
  final List<PoultryDesignationRef> portionTypes;
  final List<PoultryDesignationRef> designations;
  final List<PoultryDesignationRef> altDesignations;
  final List<PoultryGradeLink> links;
  final List<PoultryGradeLink> altLinks;
  final List<PoultryChecklistItemRef> checklist;
  final List<PoultryDesignationRef> reasons;
  final List<PoultryDesignationRef> locations;
  final List<PoultryDesignationRef> remarks;

  /// The premises directory, shared with the egg module, so the same
  /// abattoir is spelled the same way on every record.
  final List<EggFacility> facilities;
}

class _PoultryInspectionFormState extends State<PoultryInspectionForm>
    with AutomaticKeepAliveClientMixin {
  late Future<_Reference> _reference;

  /// Under the labelling the grading is one entry of a long list: kept while
  /// scrolled out of sight, or its ticks would go with it.
  @override
  bool get wantKeepAlive => widget.embedded;

  final _formKey = GlobalKey<FormState>();

  late final String _clientUuid = widget.existingUuid ?? const Uuid().v4();

  int? _locationId;

  /// True when the door-side facility type settled [_locationId], so the
  /// form does not ask again.
  bool _locationFromVisit = false;
  int? _reasonId;

  /// True when the reason chosen at the door settled [_reasonId], so the
  /// group is not asked why it is here a second time.
  bool _reasonFromVisit = false;
  int? _meatTypeId;
  int? _portionTypeId;
  int? _designationId;
  int? _altDesignationId;
  int? _gradeId;
  int? _remarkTypeId;

  final _facilityName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityTelephone = TextEditingController();
  final _companyReg = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _newFacilityName = TextEditingController();
  final _producerTradingName = TextEditingController();
  final _productDetails = TextEditingController();
  final _sampleNumber = TextEditingController();
  final _inspectionComments = TextEditingController();
  final _directionComments = TextEditingController();
  final _directionRemarks = TextEditingController();

  /// Ticked = compliant. Starts empty, so an inspector who saves without
  /// working through the lists records every row as a deviation rather than
  /// silently passing the consignment.
  final _compliant = <int>{};

  /// "Correct by/on" — set by FSA-SOP-APS-001 Annexure C from the
  /// deviations, not typed.
  final _correctByDate = TextEditingController();
  DateTime? _correctBy;

  /// The annexure's own date for [_correctBy], and whether the inspector has
  /// moved the rejection to a later one of their choosing.
  DateTime? _sopCorrectBy;
  bool _correctByPicked = false;

  /// Whether the seizure question has been put on this visit to the form,
  /// and what the inspector answered.
  bool _seizureAsked = false;

  /// The findings the last answer to the seizure question covered; null
  /// until known (a resumed record takes what stands when first checked).
  Set<String>? _answeredFindings;
  SeizureDecision? _seizureDecision;

  /// The original has five whole-carcass samples, each with its own grading
  /// answers. Cuts have a single sample and do not show the portions list.
  final _gradingBySample = <int, Set<int>>{};
  final _gradingRowIds = <int>{};
  int _currentSample = 1;

  /// The grading photographs already on this record, one per sample.
  List<PoultryPhoto> _gradingPhotos = const [];
  bool _capturingSample = false;

  /// Where the sample block starts, so finishing one can bring the next to
  /// the top of the screen instead of leaving the inspector halfway down a
  /// form they have already filled in.
  final _sampleAnchor = GlobalKey();

  /// The required fields a refused save flagged, so the page can take the
  /// inspector to the first and mark each red.
  final _missing = MissingFields();

  /// A photograph is tied to its sample by its caption, which is also what
  /// the printed sheet shows beside it.
  static String _sampleCaption(int sample) => 'Sample $sample';

  int _photosForSample(int sample) => _gradingPhotos
      .where((photo) => photo.caption == _sampleCaption(sample))
      .length;
  Position? _position;

  /// When the consignment was inspected — set once, and restored on resume.
  /// Stamping every save with "now" instead silently moved a draft between
  /// days each time it was touched, changing which date filter finds it.
  late DateTime _inspectedAt = DateTime.now();

  bool _saving = false;

  /// On the Poultry Type list in the reference data, but not poultry types.
  static const _notPoultryTypes = {'portions', 'other'};

  /// The record was already finished when it was opened: going back
  /// leaves it so, rather than turning it into a draft.
  bool _wasCompleted = false;

  @override
  void initState() {
    super.initState();
    _applyVisitPrefill();
    _reference = _loadReference();
    if (widget.existingUuid != null) _restore(widget.existingUuid!);
    unawaited(_carryRegistrationNumber());
    // Where the inspection is happening is not a decision, so it is not a
    // question: taken in the background as the form opens, and silent
    // whether it succeeds or not.
    unawaited(_captureLocation(silent: true));
    widget.controller
      ?.._finish = _finishEmbedded
      .._save = _saveEmbedded;
    // Typing keeps the draft too. Only this form's own boxes: the facility
    // ones are refilled from the label checklist on every keep.
    for (final c in [
      _directionRemarks,
      _directionComments,
      _inspectionComments
    ]) {
      c.addListener(_autosave);
    }
  }

  /// Kept as it is filled in (Ethan, 2026-09-30), so an app closed mid-way
  /// — by the phone, a flat battery, an update — loses nothing.
  Timer? _autosaveTimer;

  /// Set once the grading is being finished, so a pending keep cannot turn
  /// the finished record back into a draft.
  bool _finishing = false;

  void _autosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      // A finished record is only changed by Complete, as on leaving.
      if (!mounted || _finishing || _wasCompleted) return;
      unawaited(_persist(completed: false));
    });
  }

  /// Every answer that redraws the form — a slider, a picker, a sample —
  /// is kept as well.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _autosave();
  }

  /// The label checklist's Complete: the same checks as this form's own.
  Future<bool> _finishEmbedded({bool hostSeized = false}) async {
    final reference = await _reference;
    if (!mounted) return false;
    return _complete(reference, hostSeized: hostSeized);
  }

  /// The label checklist's Save draft.
  Future<void> _saveEmbedded() async {
    if (mounted) await _persist(completed: false);
  }

  /// Takes what the label checklist holds: its answers are this record's.
  /// Only what it has filled in — a blank there leaves this record's own
  /// value, the visit's facility among them, where it is.
  void _takeFromHost() {
    final host = widget.host?.call();
    if (host == null) return;
    _reasonId = host.reasonId ?? _reasonId;
    _locationId = host.locationId ?? _locationId;
    void take(TextEditingController field, String value) {
      if (value.trim().isNotEmpty) field.text = value;
    }

    take(_facilityName, host.facilityName);
    take(_producerTradingName, host.tradingName);
    take(_facilityAddress, host.facilityAddress);
    take(_facilityTelephone, host.facilityTelephone);
    take(_companyReg, host.registrationNumber);
    take(_contactPerson, host.contactPerson);
    take(_contactEmail, host.contactEmail);
    take(_productDetails, host.productName);
    take(_managerName, host.managerName);
    take(_managerEmail, host.managerEmail);
    take(_clientEmail, host.clientEmail);
    take(_clientEmail2, host.clientEmail2);
  }

  /// Takes the registration number from whichever poultry record in this
  /// visit captured it first — the premises has one, and it is not worth
  /// typing on each record.
  ///
  /// Only ever fills an empty field, so a resumed draft and anything the
  /// inspector has already typed win over the carried value.
  Future<void> _carryRegistrationNumber() async {
    final visit = widget.visit;
    if (visit == null || _companyReg.text.trim().isNotEmpty) return;
    final carried =
        await widget.captureRepository.registrationNumberForVisit(visit.uuid);
    if (!mounted || carried.isEmpty || _companyReg.text.trim().isNotEmpty) {
      return;
    }
    setState(() => _companyReg.text = carried);
  }

  /// The same pack the label checklist was just read against, so the same
  /// registration number and product details. Only ever fills an empty
  /// field, so a resumed draft keeps its own.
  void _applyCarryOver() {
    final carried = widget.carriedOver;
    if (carried == null) return;
    if (_companyReg.text.trim().isEmpty) {
      _companyReg.text = carried.registrationNumber;
    }
    if (_productDetails.text.trim().isEmpty) {
      _productDetails.text = carried.productDetails;
    }
  }

  /// Fields the visit already knows arrive filled; only empty ones take the
  /// value, so a resumed draft keeps its own.
  void _applyVisitPrefill() {
    _applyCarryOver();
    final visit = widget.visit;
    if (visit == null) return;
    void fill(TextEditingController field, String value) {
      if (field.text.trim().isEmpty && value.isNotEmpty) field.text = value;
    }

    fill(_facilityName, visit.facilityName);
    fill(_facilityAddress, visit.facilityAddress);
    fill(_facilityTelephone, visit.facilityPhone);
    fill(_contactPerson, visit.contactPerson);
    fill(_contactEmail, visit.contactEmail);
    fill(_managerName, visit.managerName);
    fill(_managerEmail, visit.managerEmail);
    fill(_clientEmail, visit.contactEmail);
  }

  static Set<int> _idSet(String csv) => {
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  /// Puts a saved draft back on screen.
  ///
  /// Without this, "Resume" opened a blank form over the saved record — and
  /// completing it overwrote everything the inspector had already entered
  /// with empty values.
  Future<void> _restore(String uuid) async {
    final saved = await widget.repository.inspectionByUuid(uuid);
    if (saved == null || !mounted) return;
    setState(() {
      _inspectedAt = saved.inspectedAt;
      _wasCompleted = saved.status != 'draft';
      _locationId = saved.locationId;
      _reasonId = saved.reasonId;
      _meatTypeId = saved.meatTypeId;
      _portionTypeId = saved.portionTypeId;
      _designationId = saved.designationClassId;
      _altDesignationId = saved.altDesignationClassId;
      _gradeId = saved.gradeId;
      _remarkTypeId = saved.directionRemarkTypeId;
      _facilityName.text = saved.facilityName;
      _facilityAddress.text = saved.facilityAddress;
      _facilityTelephone.text = saved.facilityTelephone;
      _companyReg.text = saved.companyRegNumber;
      _contactPerson.text = saved.contactPerson;
      _contactEmail.text = saved.contactPersonEmail;
      _managerName.text = saved.managerName;
      _managerEmail.text = saved.managerEmail;
      _clientEmail.text = saved.clientEmail;
      _clientEmail2.text = saved.clientEmail2;
      _newFacilityName.text = saved.newFacilityName;
      _producerTradingName.text = saved.producerTradingName;
      _productDetails.text = saved.productDetails;
      _sampleNumber.text = saved.sampleNumber;
      _inspectionComments.text = saved.inspectionComments;
      _directionComments.text = saved.directionComments;
      _directionRemarks.text = saved.directionRemarks;
      _compliant
        ..clear()
        ..addAll(_idSet(saved.compliantItemIds));
      _gradingBySample
        ..clear()
        ..addAll(_decodeGrading(saved.gradingBySample));
      _seizureDecision = SeizureDecision.of(saved.seizureDecision);
      _seizureAsked = _seizureDecision != null;
    });
    // The correct-by date follows from the ticks, so it is worked out again
    // rather than trusted from the draft; the question is not put again.
    unawaited(_applySop(ask: false));
  }

  /// Marks every checklist row Compliant, for a record nobody has answered
  /// yet.
  // Every requirement starts Compliant, so the inspector marks only what
  // is wrong.
  //
  // The rows used to start as deviations, on the reasoning that the app
  // must not claim a requirement was met before anyone had looked. In the
  // field that inverts the work: a compliant consignment means moving
  // every row one at a time, and any row missed in that sweep becomes a
  // deviation the inspector never intended. A deviation is the exception,
  // so it is the exception that gets marked (FSA, 2026-09-07 for eggs;
  // carried to every commodity 2026-09-23).
  //
  // Seeded before any saved draft is restored, so a resumed record keeps
  // the answers it was saved with.
  void _startCompliant(List<PoultryChecklistItemRef> checklist) {
    if (_compliant.isNotEmpty) return;
    _compliant.addAll([for (final item in checklist) item.id]);
  }

  /// The reference read, capped so a stuck or locked local database surfaces
  /// a retry instead of an endless spinner. A local read is near-instant;
  /// twenty seconds means something is wrong, not slow (Ethan, 2026-10-14).
  Future<_Reference> _loadReference() =>
      _load().timeout(const Duration(seconds: 20));

  void _retryReference() {
    if (!mounted) return;
    setState(() => _reference = _loadReference());
  }

  Future<_Reference> _load() async {
    final repo = widget.repository;
    final checklist = await repo.checklistItems();
    _startCompliant(checklist);
    return _Reference(
      meatTypes: await repo.meatTypes(),
      grades: await repo.grades(),
      portionTypes: await repo.portionTypes(),
      designations: await repo.designationClasses(),
      altDesignations: await repo.alternativeDesignationClasses(),
      links: await repo.designationGradeLinks(),
      altLinks: await repo.alternativeGradeLinks(),
      checklist: checklist,
      reasons: await repo.inspectionReasons(),
      locations: await repo.inspectionLocations(),
      remarks: await repo.directionRemarks(),
      facilities: await repo.facilities(),
    );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    final controller = widget.controller;
    if (controller != null && controller._finish == _finishEmbedded) {
      controller
        .._finish = null
        .._save = null;
    }
    for (final c in [
      _facilityName,
      _facilityAddress,
      _facilityTelephone,
      _companyReg,
      _contactPerson,
      _contactEmail,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _newFacilityName,
      _producerTradingName,
      _productDetails,
      _sampleNumber,
      _inspectionComments,
      _directionComments,
      _directionRemarks,
      _correctByDate,
    ]) {
      c.dispose();
    }
    _missing.dispose();
    super.dispose();
  }

  /// Writes the form to the local store, without ceremony.
  ///
  /// Split from [_save] so the evidence section can persist a draft the
  /// moment a photograph or signature lands: the record must exist for the
  /// evidence to belong to, and the camera is precisely when Android is most
  /// likely to reclaim the process and lose unsaved state.
  void _toggleCompliant(int id) {
    setState(() {
      if (!_compliant.remove(id)) _compliant.add(id);
    });
    unawaited(_applySop());
  }

  static Map<int, Set<int>> _decodeGrading(String raw) {
    final result = <int, Set<int>>{};
    for (final part in raw.split(';')) {
      final halves = part.split(':');
      final sample = int.tryParse(halves.first.trim());
      if (halves.length != 2 || sample == null) continue;
      result[sample] = _idSet(halves.last);
    }
    return result;
  }

  String _encodeGrading() => [
        for (final entry in _gradingBySample.entries)
          if (entry.value.isNotEmpty)
            '${entry.key}:${(entry.value.toList()..sort()).join(',')}',
      ].join(';');

  /// The grading ticks for the sample on screen.
  ///
  /// A sample seen for the first time starts with every row Compliant, as
  /// every other checklist in the app does, and the inspector marks what the
  /// carcass fails. It used to start empty — and because the record reads
  /// these sets as the rows that *passed*, a fresh sample nobody had
  /// touched went into the record as failing every grading standard, and a
  /// compliant consignment raised a direction. [_gradingRowIds] is filled by
  /// the block's own Builder before this is first read.
  Set<int> get _currentGrading => _gradingBySample.putIfAbsent(
      _currentSample, () => <int>{..._gradingRowIds});

  void _toggleGrading(int id) {
    _toggleGradingTicks(id);
    unawaited(_applySop());
  }

  /// The deviations on the lists this screen asks.
  ///
  /// Only those lists: the reference store also carries the Label/Container
  /// screen's 37 rows, and counting those said "57 deviations" on a form
  /// that shows 23 tick-boxes. Portion rows count only where the portions
  /// list was actually asked — keyed off the sample count they also counted
  /// on a record whose portion type was never answered. And no grading row
  /// is a finding where nothing is graded: an untouched grading list would
  /// otherwise have read as thirteen deviations on a product that is not
  /// graded at all.
  List<PoultryFinding> _findings(_Reference reference) {
    final sampleCount = _sampleCount(reference);
    final portionsHere = _isPortions(reference.portionTypes);
    final commonItems = <PoultryChecklistItemRef>[
      for (final item in reference.checklist)
        if (item.kind == PoultryChecklistKind.pack ||
            (item.kind == PoultryChecklistKind.portion && portionsHere))
          item,
    ];
    final gradingItems = [
      if (_gradingApplies(reference))
        for (final item in reference.checklist)
          if (item.kind == PoultryChecklistKind.grading) item,
    ];
    return [
      ...PoultryRules.findings(
          items: commonItems, compliantItemIds: _compliant),
      for (var sample = 1; sample <= sampleCount; sample++)
        ...PoultryRules.findings(
          items: gradingItems,
          // A sample the inspector never opened has no ticks of its own; it
          // is judged as every untouched row is — compliant unless marked —
          // rather than as failing every standard at once.
          compliantItemIds: _gradingBySample[sample] ??
              {for (final item in gradingItems) item.id},
        ),
    ];
  }

  Iterable<PoultryChecklistItemRef> _deviations(_Reference reference) =>
      _findings(reference).map((f) => f.item);

  /// FSA-SOP-APS-001, Annexure C: the rectification period follows from
  /// the deviations ticked, and a deviation the annexure seizes on puts the
  /// seizure question — once, on the premises.
  Future<void> _applySop({bool ask = true}) async {
    final reference = await _reference;
    if (!mounted) return;
    final days = PoultryRules.rectificationDays(
      deviations: _deviations(reference),
      classOmitted: false,
      gradeOmitted: false,
    );
    setState(() {
      _sopCorrectBy =
          PoultryRules.correctByDate(inspectedAt: _inspectedAt, days: days);
      // The inspector's own date stands while the annexure still gives a
      // period to move; none, or an immediate one, puts the annexure's back.
      if (!_correctByPicked || !CorrectByDateField.isFuture(_sopCorrectBy)) {
        _correctBy = _sopCorrectBy;
        _correctByPicked = false;
      }
      _correctByDate.text = _correctBy == null ? '' : _dmy(_correctBy!);
    });
    if (ask) await _askAboutSeizureIfNeeded(reference);
  }

  Future<void> _askAboutSeizureIfNeeded(_Reference reference) async {
    final rows = PoultryRules.seizureFindings(
      deviations: _deviations(reference),
      classOmitted: false,
      gradeOmitted: false,
    );
    if (rows.isEmpty) {
      _forgetSeizureQuestion();
      return;
    }
    // A finding the last answer did not cover is asked about afresh: a
    // second omission is a second reason to seize. A seizure already
    // recorded covers the consignment, whatever else is found.
    final findings = {for (final r in rows) '${r.id}'};
    if (_seizureDecision == SeizureDecision.seize || !mounted) return;
    if (_seizureAsked &&
        (_answeredFindings ??= findings).containsAll(findings)) {
      return;
    }
    _seizureAsked = true;
    final answer = await askAboutSeizure(context, reason: _seizureReason(rows));
    if (answer == null || !mounted) {
      _seizureAsked = false;
      return;
    }
    _answeredFindings = findings;
    setState(() => _seizureDecision = answer);
    // Seized: the Annexure E sheet is drawn up here, on the premises.
    if (answer == SeizureDecision.seize) {
      _takeFromHost();
      await recordSeizure(
        context,
        database: widget.repository.database,
        draft: SeizureDraft(
          recordUuid: _clientUuid,
          recordKind: 'poultry',
          visitUuid: widget.visit?.uuid ?? '',
          inspectorUsername: widget.inspectorName,
          natureOfDeviation: _seizureReason(rows),
          regulation: 'R.946 of 27 March 1992',
          clientName: _facilityName.text,
          clientAddress: _facilityAddress.text,
          clientTelephone: _facilityTelephone.text,
          clientEmail: _contactEmail.text,
          inspectionPoint: reference.locations
              .where((l) => l.id == _locationId)
              .map((l) => l.name)
              .firstWhere((_) => true, orElse: () => ''),
          productName: _productDetails.text,
          receiverName: _managerName.text,
        ),
      );
      if (!mounted) return;
      // Seized: the product is taken, so the inspection ends here — only
      // its photographs are still asked for (Ethan, 2026-09-30). Under the
      // label checklist, that form finishes both.
      if (widget.embedded) {
        widget.onSeized?.call();
      } else {
        await _save(reference, completed: true);
      }
    }
  }

  /// The findings no longer call for a seizure — a row was marked back
  /// compliant — so the answer given to them lapses and the question is put
  /// again should a finding return (Ethan, 2026-09-29). A seizure actually
  /// recorded stands: its sheet has been drawn up.
  void _forgetSeizureQuestion() {
    if (_seizureDecision == SeizureDecision.seize) return;
    if (!_seizureAsked && _seizureDecision == null) return;
    _seizureAsked = false;
    _answeredFindings = null;
    if (mounted) {
      setState(() => _seizureDecision = null);
    } else {
      _seizureDecision = null;
    }
  }

  /// Why this consignment is to be seized, in the annexure's terms.
  String _seizureReason(List<PoultryChecklistItemRef> rows) {
    final reasons = <String>[
      if (rows.any((r) => r.kind == PoultryChecklistKind.pack))
        'the product is not packed in accordance with Regulation 7',
      if (rows.any((r) => r.kind == PoultryChecklistKind.container))
        'the container does not comply with Regulation 6',
    ];
    return 'Seizure under FSA-SOP-APS-001 Annexure C: ${reasons.join('; ')}.';
  }

  /// The inspector moved the Correct by/on Date, or cleared it back to the
  /// annexure's.
  void _correctByChanged(DateTime? date) => setState(() {
        _correctBy = date;
        _correctByPicked =
            date != null && !DateUtils.isSameDay(date, _sopCorrectBy);
        _correctByDate.text = date == null ? '' : _dmy(date);
      });

  /// What the correct-by field says under its date.
  String _periodHelper(_Reference reference) {
    final days = PoultryRules.rectificationDays(
      deviations: _deviations(reference),
      classOmitted: false,
      gradeOmitted: false,
    );
    if (days == null) {
      return 'Set by FSA-SOP-APS-001 Annexure C from the deviations ticked.';
    }
    return '${PoultryRules.periodLabel(days)}, per FSA-SOP-APS-001 '
        'Annexure C, counted from the inspection date.';
  }

  /// A seizure, once recorded, stated on the form.
  Widget _seizureNotice() {
    const colour = AppColors.brandRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Seizure under section 8 of the APS Act recorded for this '
        'consignment (FSA-SOP-APS-001 Annexure C).',
        style: TextStyle(color: colour, fontSize: 13, height: 1.4),
      ),
    );
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _toggleGradingTicks(int id) => setState(() {
        final ticks = _currentGrading;
        if (!ticks.remove(id)) ticks.add(id);
        _compliant
          ..removeWhere(_gradingRowIds.contains)
          ..addAll({
            for (final sample in _gradingBySample.values) ...sample,
          });
      });

  bool _isWholeCarcass(List<PoultryDesignationRef> portionTypes) => portionTypes
      .where((portion) => portion.id == _portionTypeId)
      .any((portion) => portion.name.toLowerCase().contains('whole carcass'));

  /// Cuts and portions, said explicitly.
  ///
  /// Not simply "anything that is not a whole carcass": before the
  /// inspector has answered Portion Type at all, neither list applies, and
  /// asking the portions questions on a record whose product is still
  /// unknown invites answers about the wrong thing.
  bool _isPortions(List<PoultryDesignationRef> portionTypes) =>
      _portionTypeId != null && !_isWholeCarcass(portionTypes);

  /// The places poultry is graded: the carcass is assessed where it is
  /// dressed and packed, not where it is sold. A retailer, an importer or a
  /// repacker is inspected on its labelling and packing.
  static const _gradingLocations = ['abattoir', 'producer', 'pack house'];

  bool _isGradingLocation(List<PoultryDesignationRef> locations) => locations
      .where((location) => location.id == _locationId)
      .any((location) => _gradingLocations
          .any((name) => location.name.toLowerCase().contains(name)));

  /// Whether this inspection grades anything at all.
  ///
  /// Two things had been assumed and neither holds. Portions are not
  /// graded — the grades are carcass grades — so a cuts-and-portions
  /// inspection was being asked for a grade that does not exist for the
  /// product. And a retail outlet was walked straight into carcass grading
  /// as though it were an abattoir. Grading now needs both a whole carcass
  /// and a place that grades (FSA, 2026-09-07).
  ///
  /// Under the labelling the inspector has already said YES to grading, so
  /// it applies wherever they are, and always to a whole carcass (Ethan,
  /// 2026-09-30).
  bool _gradingApplies(_Reference reference) =>
      widget.embedded ||
      (_isWholeCarcass(reference.portionTypes) &&
          _isGradingLocation(reference.locations));

  /// Whether the carcasses are being sampled as a set of five.
  ///
  /// Sampling is the inspector's call, not a rule: a set of five is how a
  /// consignment is assessed when one is drawn, but grading a single carcass
  /// is a legitimate inspection. Portions never reach this — they are not
  /// graded at all.
  bool _sampleCarcasses = true;

  /// Five carcasses when a sample is drawn, otherwise the one in hand.
  /// Anything that is not graded is a single sample either way.
  /// Seized, here or on the label checklist above: nothing is graded.
  bool get _seizedAll =>
      _seizureDecision == SeizureDecision.seize || widget.hostSeized;

  /// Said where the grade and the sample walk would be.
  Widget _seizedNote() => const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 10),
        child: Text(
          'Seized — no grade or sample of carcasses is needed.',
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandRed),
        ),
      );

  int _sampleCount(_Reference reference) =>
      _gradingApplies(reference) && _sampleCarcasses ? 5 : 1;

  /// Drops back to the one carcass in hand.
  ///
  /// Ticks already recorded against samples 2–5 are cleared rather than left
  /// behind: they would keep counting towards the compliant set while no
  /// screen showed them, and the record would disagree with the form. Any
  /// photographs taken stay — evidence already captured is not thrown away.
  void _stopSampling() {
    _currentSample = 1;
    _sampleNumber.text = '1';
    _gradingBySample.removeWhere((sample, _) => sample > 1);
    _compliant
      ..removeWhere(_gradingRowIds.contains)
      ..addAll({
        for (final entry in _gradingBySample.entries) ...entry.value,
      });
  }

  Future<void> _reloadGradingPhotos() async {
    final photos = await widget.captureRepository.photosFor(_clientUuid);
    if (!mounted) return;
    setState(() => _gradingPhotos =
        photos.where((photo) => photo.kind == 'grading').toList());
  }

  /// The photograph taken for [sample], with a cross to remove it — the
  /// same x the other photo blocks carry (Ethan, 2026-09-30).
  Widget _sampleThumb(int sample) {
    final photo =
        _gradingPhotos.lastWhere((p) => p.caption == _sampleCaption(sample));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(photo.filePath),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            // A file Android has cleared is a missing photo, not a crash.
            errorBuilder: (_, __, ___) => Container(
              width: 64,
              height: 64,
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: InkWell(
            onTap: _capturingSample
                ? null
                : () => unawaited(_removeSamplePhoto(sample)),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.brandRed,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, size: 15, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// Takes [sample]'s photograph off the record; its chip loses its tick
  /// and the sample asks for one again.
  Future<void> _removeSamplePhoto(int sample) async {
    for (final photo in [
      for (final p in _gradingPhotos)
        if (p.caption == _sampleCaption(sample)) p,
    ]) {
      await widget.captureRepository.deletePhoto(photo.id);
    }
    await _reloadGradingPhotos();
    unawaited(_persist(completed: false));
  }

  /// One photograph of the carcass this sample was graded on.
  Future<void> _captureSamplePhoto() async {
    if (_capturingSample) return;
    final String? shot;
    try {
      shot = await capturePhoto(context, title: 'Sample $_currentSample');
    } on Object catch (e) {
      if (mounted) _toast('The camera could not be opened. $e');
      return;
    }
    if (shot == null || !mounted) return;
    setState(() => _capturingSample = true);
    final replaced = [
      for (final p in _gradingPhotos)
        if (p.caption == _sampleCaption(_currentSample)) p,
    ];
    try {
      final storage = await PhotoStorage.instance();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await storage.adopt(
        File(shot),
        name: 'poultry_${_clientUuid}_grading_$stamp.jpg',
      );
      await widget.captureRepository.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: _clientUuid,
          kind: 'grading',
          filePath: path,
          capturedAt: DateTime.now(),
          caption: Value(_sampleCaption(_currentSample)),
        ),
      );
      // A retake replaces the sample's photograph rather than sitting
      // beside it (Ethan, 2026-09-30).
      for (final old in replaced) {
        await widget.captureRepository.deletePhoto(old.id);
      }
      await _reloadGradingPhotos();
      // A photograph is evidence the moment it is taken, so the record it
      // belongs to has to exist.
      unawaited(_persist(completed: false));
      // And the sample is finished, so the next one comes up on its own.
      if (mounted) unawaited(_advanceAfterPhoto());
    } on Object catch (e) {
      if (mounted) _toast(photoSaveFailure(e));
    } finally {
      if (mounted) setState(() => _capturingSample = false);
    }
  }

  /// Moves on once this carcass has been photographed.
  ///
  /// Nothing to press: the photograph is the last thing a sample needs, so
  /// finishing it is the signal to bring up the next one. A short pause
  /// first, so the tick on the sample just finished is seen before the
  /// screen moves.
  Future<void> _advanceAfterPhoto() async {
    final count = _lastSampleCount;
    if (_currentSample >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _nextSample(count);
  }

  /// How many samples the form last drew, so the capture handler knows
  /// where the set ends without rebuilding the reference.
  int _lastSampleCount = 1;

  /// Moves on to the next carcass and puts it at the top of the screen.
  Future<void> _nextSample(int sampleCount) async {
    if (_currentSample >= sampleCount) return;
    setState(() {
      _currentSample += 1;
      _sampleNumber.text = '$_currentSample';
    });
    final anchor = _sampleAnchor.currentContext;
    if (anchor != null) {
      await Scrollable.ensureVisible(
        anchor,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0,
      );
    }
  }

  /// Why the grading block is not on the screen, in the inspector's terms.
  String _gradingNotApplicable(_Reference reference) {
    if (!_isWholeCarcass(reference.portionTypes)) {
      return _portionTypeId == null
          ? 'Choose the Portion Type above. Grading applies to whole '
              'carcasses only.'
          : 'Portions are not graded — the grades are carcass grades. This '
              'inspection covers packing and labelling.';
    }
    return 'Carcasses are graded where they are dressed and packed. At this '
        'facility the inspection covers packing and labelling.';
  }

  /// Stamps where the inspection was done, without being asked.
  ///
  /// It used to be a crosshair button beside the sample number — one more
  /// tap per inspection, on a screen that already has plenty, and an easy
  /// one to forget. The position is not something the inspector decides;
  /// it is simply where they are standing. So it is taken when the form
  /// opens and never mentioned unless something goes wrong on a deliberate
  /// retry.
  Future<void> _captureLocation({bool silent = false}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent) {
          _toast('Location permission was not granted. You can still save.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) {
        setState(() => _position = position);
        if (!silent) _toast('Location captured.');
      }
    } on Object {
      // A missing fix never blocks an inspection; the record saves without
      // one rather than holding the inspector up over it.
      if (!silent) _toast('Could not get a location fix. You can still save.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectGrade(
    int? value,
    List<PoultryGradeRef> grades,
  ) async {
    final grade = grades.where((g) => g.id == value).firstOrNull;
    if (grade?.name.toLowerCase() != 'no grade') {
      setState(() => _gradeId = value);
      return;
    }
    if (widget.embedded) {
      final off = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No Grade'),
          content: const Text(
            'No Grade does not create a grading inspection. Answer NO to '
            'grading and classification for this product?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Continue grading'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Answer NO'),
            ),
          ],
        ),
      );
      if (off == true && mounted) widget.onNoGrade?.call();
      return;
    }
    final abandon = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No Grade'),
        content: const Text(
          'No Grade does not create a grading inspection. Return to the menu without saving this form?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue inspection'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Return to menu'),
          ),
        ],
      ),
    );
    if (abandon == true && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _persist({required bool completed}) async {
    // The refusal lives on the signature rows, where the tick-box is. Read
    // from there rather than tracked twice, so the record field can never
    // contradict what the evidence section shows.
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined = signatures.any((s) => s.role == 'no_client' && s.declined);
    _takeFromHost();

    final row = PoultryInspectionsCompanion.insert(
      clientUuid: _clientUuid,
      visitUuid: Value(widget.visit?.uuid ?? ''),
      inspectedAt: _inspectedAt,
      updatedAt: DateTime.now(),
      inspectorUsername: Value(widget.inspectorName),
      // In a grouped inspection a finished member waits as `ready`; the
      // group's one sign-off submits everything together.
      status: Value(
          completed ? (widget.visit != null ? 'ready' : 'completed') : 'draft'),
      locationId: Value(_locationId),
      reasonId: Value(_reasonId),
      facilityName: Value(_facilityName.text.trim()),
      facilityAddress: Value(_facilityAddress.text.trim()),
      facilityTelephone: Value(_facilityTelephone.text.trim()),
      companyRegNumber: Value(_companyReg.text.trim()),
      contactPerson: Value(_contactPerson.text.trim()),
      contactPersonEmail: Value(_contactEmail.text.trim()),
      managerName: Value(_managerName.text.trim()),
      managerEmail: Value(_managerEmail.text.trim()),
      clientEmail: Value(_clientEmail.text.trim()),
      clientEmail2: Value(_clientEmail2.text.trim()),
      newFacilityName: Value(_newFacilityName.text.trim()),
      producerTradingName: Value(_producerTradingName.text.trim()),
      meatTypeId: Value(_meatTypeId),
      portionTypeId: Value(_portionTypeId),
      designationClassId: Value(_designationId),
      altDesignationClassId: Value(_altDesignationId),
      productDetails: Value(_productDetails.text.trim()),
      sampleNumber: Value(_sampleNumber.text.trim()),
      gradeId: Value(_gradeId),
      compliantItemIds: Value(_compliant.join(',')),
      gradingBySample: Value(_encodeGrading()),
      inspectionComments: Value(_inspectionComments.text.trim()),
      directionComments: Value(_directionComments.text.trim()),
      directionRemarks: Value(_directionRemarks.text.trim()),
      directionRemarkTypeId: Value(_remarkTypeId),
      seizureDecision: Value(_seizureDecision?.stored ?? ''),
      noClientSignaturePresent: Value(declined),
      latitude: Value(_position?.latitude),
      longitude: Value(_position?.longitude),
    );

    await widget.repository.saveInspection(row);
  }

  /// The answers a completed record cannot be without.
  ///
  /// `Form.validate()` is not enough on its own here: the form is a lazy
  /// [ListView], so a picker scrolled off the top is unmounted and its field
  /// deregisters. Completing happens at the foot of the form, by which point
  /// the classification pickers are long gone and validate() passes straight
  /// over them — an inspection completed with no poultry type and no grade,
  /// asterisks and all. These are read from the state itself, which is
  /// always there.
  ///
  /// In page order, as ids for [_missing] with the caption each is shown by.
  List<({String id, String label})> _missingRequired(_Reference reference) => [
        if (_reasonId == null && !widget.embedded)
          (id: 'reason', label: 'Reason for Inspection'),
        if (_locationId == null && !widget.embedded)
          (id: 'location', label: 'Inspection Facility Type'),
        if (_meatTypeId == null) (id: 'meatType', label: 'Poultry Type'),
        if (_gradingApplies(reference)) ...[
          if (_designationId == null)
            (id: 'designation', label: 'Class Designation Type'),
          if (_gradeId == null) (id: 'grade', label: 'Grade'),
        ],
      ];

  /// Wraps a required field so a refused save can scroll to it and mark it.
  Widget _anchor(
    String id,
    Widget child, {
    bool framed = false,
    bool enabled = true,
  }) =>
      enabled
          ? MissingFieldAnchor(
              fields: _missing,
              id: id,
              framed: framed,
              child: child,
            )
          : child;

  Future<void> _save(_Reference reference, {required bool completed}) async {
    if (completed) {
      if (!await _complete(reference)) return;
    } else {
      setState(() => _saving = true);
      await _persist(completed: false);
      if (!mounted) return;
      setState(() => _saving = false);
    }
    final findings = _findings(reference);

    // Inside a grouped inspection there is nothing to announce — the record
    // waits for the group's one sign-off, so go straight back to the visit.
    if (!mounted) return;
    // Seized: said so, and back to where the inspection was opened from.
    if (completed && _seizureDecision == SeizureDecision.seize) {
      announceSeizureDone(context);
      Navigator.of(context).pop(true);
      return;
    }
    if (widget.visit != null) {
      Navigator.of(context).pop(true);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(completed ? 'Inspection saved' : 'Draft saved'),
        content: Text(
          completed
              ? findings.isEmpty
                  ? 'No deviations recorded. Send it from Inspection '
                      'Management when you have signal.'
                  : '${findings.length} '
                      '${findings.length == 1 ? "deviation" : "deviations"} '
                      'recorded. A rejection has been created.'
              : 'Kept on this device. Finish it from Inspection Management.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Checks the record is complete, marking what is not, then writes it as
  /// finished with the rejection its findings raise. False while something
  /// is still missing.
  Future<bool> _complete(_Reference reference,
      {bool hostSeized = false}) async {
    // Seized — this grading, or the label checklist it sits under — the
    // product is taken, so the rest is not asked for: this grading's
    // photographs only when it was the one seized (Ethan, 2026-09-30).
    final seized = _seizureDecision == SeizureDecision.seize;
    hostSeized = hostSeized || widget.hostSeized;
    if (!seized && !hostSeized) {
      // Marks whatever is on screen red; the list below finds the rest.
      final formValid = _formKey.currentState?.validate() ?? false;
      final missing = _missingRequired(reference);
      if (missing.isNotEmpty) {
        _toast('Answer ${missing.map((m) => m.label).join(', ')} before '
            'completing this inspection.');
        await _missing.flag(
          context,
          [for (final m in missing) m.id],
          stillMissing: (id) =>
              _missingRequired(reference).any((m) => m.id == id),
        );
        return false;
      }
      if (!formValid) return false;
    }
    if (!seized && !hostSeized) {
      final sampleCount = _sampleCount(reference);
      if (_gradingApplies(reference)) {
        // One photograph for each sample, no more and no fewer (Ethan,
        // 2026-09-30): five taken of two carcasses is not a set.
        await _reloadGradingPhotos();
        if (!mounted) return false;
        final owed = [
          for (var sample = 1; sample <= sampleCount; sample++)
            if (_photosForSample(sample) == 0) sample,
        ];
        if (owed.isNotEmpty) {
          final which = sampleCount == 1
              ? 'the carcass'
              : owed.length == 1
                  ? 'sample ${owed.first}'
                  : 'samples ${owed.join(', ')}';
          _toast(seized
              ? seizurePhotosOwed('the photo of $which')
              : 'Take the photo of $which before completing this '
                  'inspection.');
          // Opened on the first sample still without one.
          setState(() {
            _currentSample = owed.first;
            _sampleNumber.text = '${owed.first}';
          });
          await _missing.flag(context, const ['photos']);
          return false;
        }
      } else {
        final photos = await widget.captureRepository.photosFor(_clientUuid);
        if (photos.isEmpty) {
          const owed = '1 photo';
          _toast(seized
              ? seizurePhotosOwed(owed)
              : 'Take $owed before completing this inspection.');
          if (mounted) await _missing.flag(context, const ['photos']);
          return false;
        }
      }
    } else if (seized && !widget.embedded) {
      // Seized on its own form: one photograph of the product. Under the
      // label checklist, that form's photographs stand for it.
      final photos = await widget.captureRepository.photosFor(_clientUuid);
      if (photos.isEmpty) {
        _toast(seizurePhotosOwed('a photo of the product'));
        if (mounted) await _missing.flag(context, const ['photos']);
        return false;
      }
    }
    _missing.clear();
    _autosaveTimer?.cancel();
    _finishing = true;
    setState(() => _saving = true);

    await _persist(completed: true);
    if (!mounted) return false;
    setState(() => _saving = false);

    final findings = _findings(reference);

    if (findings.isNotEmpty) {
      await widget.captureRepository.saveDirection(
        PoultryDirectionsCompanion.insert(
          clientUuid: _clientUuid,
          issuedAt: DateTime.now(),
          updatedAt: DateTime.now(),
          inspectorUsername: Value(widget.inspectorName),
          status: const Value('completed'),
          facilityName: Value(_facilityName.text.trim()),
          clientName: Value(_managerName.text.trim()),
          clientEmail: Value(_clientEmail.text.trim()),
          remarkTypeId: Value(_remarkTypeId),
          remarks: Value(_directionRemarks.text.trim()),
          comments: Value(_directionComments.text.trim()),
          actionTaken: Value(_seizureDecision == SeizureDecision.seize
              ? 'Seizure under section 8 of the APS Act '
                  '(FSA-SOP-APS-001 Annexure C).'
              : 'Generated from poultry grading findings.'),
          nonConformanceIds:
              Value(findings.map((f) => f.item.id).toSet().join(',')),
          // FSA-SOP-APS-001 Annexure C's date from the deviations, or the
          // later one the inspector chose.
          correctByDate: Value(_correctBy),
          latitude: Value(_position?.latitude),
          longitude: Value(_position?.longitude),
        ),
      );
    }
    return true;
  }

  /// Back out of the form: the work waits as a draft. A record already
  /// finished is left as it was finished; only Complete changes it.
  Future<void> _leave() async {
    if (!_wasCompleted) {
      setState(() => _saving = true);
      await _persist(completed: false);
      if (!mounted) return;
      setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Under the labelling: the grading alone, in the label checklist's list.
    if (widget.embedded) {
      return FutureBuilder<_Reference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final reference = snap.data;
          if (reference == null || reference.checklist.isEmpty) {
            return PoultryNoRules(onRetry: _retryReference);
          }
          return _form(reference);
        },
      );
    }
    // The back arrow and the phone's own back gesture keep the work: a
    // record stepped out of mid-way waits as a draft, which is why there is
    // no Save draft button (Ethan, 2026-09-30).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        await _leave();
      },
      child: _page(),
    );
  }

  Widget _page() {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Poultry Inspection Details',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_Reference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null || reference.checklist.isEmpty) {
            return PoultryNoRules(onRetry: _retryReference);
          }
          return _form(reference);
        },
      )),
    );
  }

  Widget _form(_Reference reference) {
    // Under the labelling, the label checklist's reason and facility type are
    // this record's: grading follows the facility chosen up there.
    final host = widget.host?.call();
    if (host != null) {
      _reasonId = host.reasonId ?? _reasonId;
      _locationId = host.locationId ?? _locationId;
      _reasonFromVisit = true;
      _locationFromVisit = true;
    }
    // Chosen once at the door: find this commodity's row for it. Runs
    // on every build; no setState, the value is read by the widgets built
    // right below. Under the labelling, the label checklist has done it.
    //
    // Every time, a reopened draft included: the draft keeps the facility
    // type it was saved with, and matching only while it was empty left the
    // question on the form again each time the draft was reopened. The
    // visit's answer is the one that stands (Ethan, 2026-09-30).
    final doorType = host == null ? (widget.visit?.facilityType ?? '') : '';
    if (doorType.isNotEmpty) {
      final i = FacilityTypeMatch.indexOf(
          doorType, reference.locations.map((l) => l.name).toList());
      if (i != null) {
        _locationId = reference.locations[i].id;
        _locationFromVisit = true;
      }
    }
    final doorReason =
        host == null ? (widget.visit?.inspectionReason ?? '') : '';
    if (doorReason.isNotEmpty) {
      final i = InspectionReasonMatch.indexOf(
          doorReason, reference.reasons.map((r) => r.name).toList());
      if (i != null) {
        _reasonId = reference.reasons[i].id;
        _reasonFromVisit = true;
      }
    }
    // Grading is of whole carcasses only: under the labelling the portion
    // type is set, not asked.
    if (widget.embedded) {
      final whole = reference.portionTypes
          .where((p) => p.name.toLowerCase().contains('whole carcass'))
          .firstOrNull;
      if (whole != null) _portionTypeId = whole.id;
    }
    // Only the designations this meat type can actually carry a grade for.
    // Offering the rest would strand the inspector on the grade field.
    final designations = PoultryRules.designationsFor(
      meatTypeId: _meatTypeId,
      links: reference.links,
      designations: reference.designations,
    );
    final grades = PoultryRules.gradesFor(
      meatTypeId: _meatTypeId,
      designationId: _designationId,
      links: reference.links,
      grades: reference.grades,
    );

    List<PoultryChecklistItemRef> of(PoultryChecklistKind kind) => [
          for (final item in reference.checklist)
            if (item.kind == kind) item,
        ];

    final children = <Widget>[
      // Asked once, on the label checklist above, when the grading sits
      // under the labelling.
      if (!widget.embedded) ...[
        // Section headings and field captions are the original's, in the
        // same words and order as the paper form — spelt correctly, so
        // "Classification" rather than the original's "Classifcation"
        // (Ethan, 2026-09-29).
        poultrySection('Inspection Details'),
        if (!_reasonFromVisit)
          _anchor(
              'reason',
              poultryDropdown(
                label: 'Reason for Inspection',
                value: _reasonId,
                items: reference.reasons,
                onChanged: (v) => setState(() => _reasonId = v),
              )),
        if (!_locationFromVisit)
          _anchor(
              'location',
              poultryDropdown(
                label: 'Inspection Facility Type',
                value: _locationId,
                items: reference.locations,
                onChanged: (v) => setState(() => _locationId = v),
              )),
        // Pulls from the synced premises directory the way the egg form
        // does — pick a known facility and its details fill themselves, or
        // type a name that is not on the list and carry on.
        // The facility is captured once, at the top of the grouped
        // inspection, so it is not asked for again on every record inside
        // it. The name and address still travel with the record.
        if (widget.visit == null) ...[
          SearchPickerField<EggFacility>(
            label: 'Inspection Facility Name',
            controller: _facilityName,
            options: reference.facilities,
            optionLabel: (f) => f.name,
            optionSubtitle: (f) => f.physicalAddress,
            isRequired: true,
            onSelected: (f) => setState(() {
              _facilityName.text = f.name;
              if (f.physicalAddress.trim().isNotEmpty) {
                _facilityAddress.text = f.physicalAddress;
              }
              if (f.telephone.trim().isNotEmpty) {
                _facilityTelephone.text = f.telephone;
              }
            }),
            emptyHint: 'No facilities on this device yet. Open Server Sync '
                'with a network connection to download the directory.',
          ),
          poultryField(_newFacilityName, 'New Facility Name'),
          poultryField(
              _producerTradingName, 'Name or Trading Name of New Facility'),
          // Searchable by name — "Pick n Pay Lynnwood" rather than the
          // street address — biased to where the inspector is standing.
          // Still an ordinary typed box with no signal (Ethan, 2026-10-08).
          AddressSearchField(
            controller: _facilityAddress,
            tokenProvider: widget.repository.storedToken,
            nearLatitude: _position?.latitude,
            nearLongitude: _position?.longitude,
            child:
                poultryField(_facilityAddress, 'Facility Address', lines: 2),
          ),
          poultryField(_facilityTelephone,
              'Facility Primary Contact Telephone/Cellphone Number',
              keyboard: TextInputType.phone),
          poultryField(_contactPerson, 'Representative Name'),
          poultryField(_contactEmail, 'Representative Email Address',
              keyboard: TextInputType.emailAddress),
        ],
        // Asked here rather than inside the block above: the visit does not
        // capture it, so it is needed either way — and asking it in both
        // places put the same question on the screen twice, bound to the
        // one controller.
        poultryField(_companyReg, 'Company Registration Number (optional)'),
      ],

      poultrySection('Classification and Grading Checklist'),
      _anchor(
          'meatType',
          poultryDropdown(
            label: 'Poultry Type',
            value: _meatTypeId,
            // Portions and Other are not kinds of bird: a portion is said
            // under Portion Type (Ethan, 2026-09-30). One already on a
            // saved record still shows, so it can be seen and changed.
            items: [
              for (final m in reference.meatTypes)
                if (!_notPoultryTypes.contains(m.name.trim().toLowerCase()) ||
                    m.id == _meatTypeId)
                  PoultryDesignationRef(id: m.id, name: m.name),
            ],
            required: true,
            onChanged: (v) => setState(() {
              _meatTypeId = v;
              // A designation valid for chicken need not exist for turkey, and
              // the grade depends on both — so both are cleared rather than
              // left pointing at a combination the rules do not permit.
              _designationId = null;
              _gradeId = null;
            }),
          )),
      if (!widget.embedded)
        poultryDropdown(
          label: 'Portion Type',
          value: _portionTypeId,
          items: reference.portionTypes,
          onChanged: (v) => setState(() => _portionTypeId = v),
        ),
      _anchor(
          'designation',
          poultryDropdown(
            label: 'Class Designation Type',
            value: _designationId,
            items: designations,
            required: true,
            emptyHint: _meatTypeId == null
                ? 'Choose a poultry type first'
                : 'No designations for this poultry type',
            onChanged: (v) => setState(() {
              _designationId = v;
              _gradeId = null;
            }),
          )),
      // No Alternative Class Designation (Ethan, 2026-09-30).
      if (!widget.embedded) poultryField(_productDetails, 'Product Name'),

      // Seized, the product is not graded (Ethan, 2026-09-30).
      if (_seizedAll)
        _seizedNote()
      else if (_gradingApplies(reference)) ...[
        poultrySection('Quality Std for Carcasses'),
        // No "Sample #" box: the sample heading and its numbered chips
        // below already say which one is in hand (Ethan, 2026-09-30).
        _anchor(
            'grade',
            poultryDropdown(
              label: 'Grade',
              value: _gradeId,
              items: [
                for (final g in grades)
                  PoultryDesignationRef(id: g.id, name: g.name),
              ],
              required: true,
              emptyHint: _designationId == null
                  ? 'Choose a class designation first'
                  : 'No grades permitted for this combination',
              onChanged: (v) => unawaited(_selectGrade(v, grades)),
            )),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _gradingNotApplicable(reference),
            style:
                TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.muted),
          ),
        ),

      Builder(builder: (context) {
        final sampleCount = _sampleCount(reference);
        _gradingRowIds
          ..clear()
          ..addAll(
              [for (final item in of(PoultryChecklistKind.grading)) item.id]);
        if (_currentSample > sampleCount) _currentSample = sampleCount;
        // Said once, up where the grading block would have been.
        if (!_gradingApplies(reference) || _seizedAll) {
          return const SizedBox.shrink();
        }
        _lastSampleCount = sampleCount;
        final shot = _photosForSample(_currentSample) > 0;
        final last = _currentSample >= sampleCount;
        final subject =
            _sampleCarcasses ? 'sample $_currentSample' : 'the carcass';
        final photoPrompt = shot
            ? 'Photograph taken for $subject.'
            : 'Photograph $subject — the carcass whole, with its '
                'class and grade mark legible.';
        return _anchor(
            'photos',
            framed: true,
            Column(
              key: _sampleAnchor,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drawing a sample is optional. A consignment is assessed on
                // a set of five; one carcass in hand is still a grading.
                poultrySwitch(
                  label: 'Grade a sample of five carcasses',
                  value: _sampleCarcasses,
                  onChanged: (on) => setState(() {
                    _sampleCarcasses = on;
                    if (!on) _stopSampling();
                  }),
                ),
                if (_sampleCarcasses) ...[
                  Text('SAMPLE $_currentSample OF $sampleCount',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      'Mark this carcass, photograph it, then move on to the '
                      'next one.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  // The chips stay: an inspector who needs to go back and
                  // correct sample 2 should not have to walk forward again.
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var sample = 1; sample <= sampleCount; sample++)
                        ChoiceChip(
                          // Material ticks whatever is selected, which said
                          // the same thing as the tick below and drowned it.
                          // Here a tick means one thing only: this carcass
                          // has been photographed.
                          showCheckmark: false,
                          avatar: _photosForSample(sample) > 0
                              ? const Icon(Icons.check_circle,
                                  size: 18, color: AppColors.brandPrimary)
                              : null,
                          label: Text('$sample'),
                          selected: _currentSample == sample,
                          onSelected: (_) => setState(() {
                            _currentSample = sample;
                            _sampleNumber.text = '$sample';
                          }),
                        ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Grading the one carcass in hand. Turn the sample back '
                      'on to assess a set of five.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                const SizedBox(height: 8),
                poultryChecklist(
                  title: 'Grading',
                  items: of(PoultryChecklistKind.grading),
                  compliant: _currentGrading,
                  onToggle: _toggleGrading,
                ),
                // This carcass's own photograph, taken here rather than in a
                // block of five at the foot of the form: five photographs
                // gathered at the end cannot be told apart afterwards, and
                // by then the inspector has put the bird down.
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    children: [
                      if (shot)
                        _sampleThumb(_currentSample)
                      else
                        Icon(Icons.photo_camera_outlined,
                            size: 20, color: AppColors.muted),
                      SizedBox(width: shot ? 14 : 8),
                      Expanded(
                        child: Text(
                          photoPrompt,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: AppColors.inkSoft),
                        ),
                      ),
                      if (shot)
                        TextButton.icon(
                          onPressed: _capturingSample
                              ? null
                              : () => unawaited(_captureSamplePhoto()),
                          icon:
                              const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Retake photo'),
                        ),
                    ],
                  ),
                ),
                // Under the deviation rows, the one thing to press: the
                // photograph finishes this sample, and the form goes back
                // up to start the next (Ethan, 2026-09-30). A sample already
                // photographed just moves on.
                if (!shot || !last)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _capturingSample
                            ? null
                            : shot
                                ? () => unawaited(_nextSample(sampleCount))
                                : () => unawaited(_captureSamplePhoto()),
                        icon: Icon(shot
                            ? Icons.arrow_upward
                            : Icons.photo_camera_outlined),
                        label: Text(shot
                            ? 'Go to sample ${_currentSample + 1}'
                            : last
                                ? 'Take photo'
                                : 'Take photo and go to sample '
                                    '${_currentSample + 1}'),
                      ),
                    ),
                  ),
                if (last && shot)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      _sampleCarcasses
                          ? 'All $sampleCount samples graded and photographed.'
                          : 'Carcass graded and photographed.',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPrimary),
                    ),
                  ),
              ],
            ));
      }),
      // Portions (Reg. 5) belongs to portions, so it is asked wherever a
      // portion is inspected. It used to sit inside the grading block,
      // which put it out of reach exactly where it applies.
      if (_isPortions(reference.portionTypes))
        poultryChecklist(
          title: 'Portions (Reg. 5)',
          items: of(PoultryChecklistKind.portion),
          compliant: _compliant,
          onToggle: _toggleCompliant,
        ),
      poultryChecklist(
        title: 'Packing (Reg. 7)',
        items: of(PoultryChecklistKind.pack),
        compliant: _compliant,
        onToggle: _toggleCompliant,
      ),

      _anchor(
        'photos',
        framed: true,
        // Up in the sample block instead while grading applies; a
        // seized product on its own form is photographed here.
        enabled:
            !_gradingApplies(reference) || (_seizedAll && !widget.embedded),
        PoultryEvidenceSection(
          repository: widget.captureRepository,
          recordUuid: _clientUuid,
          kind: 'grading',
          // Grading photographs are taken sample by sample up in the
          // sample block, so this block only carries them where there is
          // no sample walk to hang them on.
          showPhotos:
              !_gradingApplies(reference) || (_seizedAll && !widget.embedded),
          minPhotos: _seizedAll ? 1 : _sampleCount(reference),
          // One spare, as the label and QUID checklists have: with the
          // ceiling set to the minimum there was no room for the shot the
          // required ones could not fit — a second face of the carcass, a
          // mark the first frame caught at an angle.
          maxPhotos: _sampleCount(reference) + 1,
          guidance: _gradingApplies(reference) && !_seizedAll
              ? 'One photograph per graded carcass — five in all. Show the '
                  'carcass whole, with its class and grade mark legible.'
              : 'One photograph of the product as it is offered for sale. '
                  'Show the label square-on, with the class or grade '
                  'designation, the packer and the production lot code '
                  'readable.',
          captureLabel: _gradingApplies(reference) && !_seizedAll
              ? 'Take carcass photograph'
              : 'Take product photograph',
          // One photograph per graded carcass where grading applies;
          // otherwise a single photograph of the product and its label,
          // which is what the inspection actually looked at.
          captureNotes: _gradingApplies(reference) && !_seizedAll
              ? [
                  for (var sample = 1;
                      sample <= _sampleCount(reference);
                      sample++)
                    (
                      title: 'Sample $sample photograph',
                      message: 'Take the grading evidence photograph for '
                          'sample $sample.',
                    ),
                ]
              : const [
                  (
                    title: 'Product photograph',
                    message: 'Take one photograph of the product and its '
                        'label.',
                  ),
                ],
          // In a grouped inspection the manager and inspector sign once,
          // at the end, and those signatures fan out to every member.
          // Under the labelling, the label checklist's signatures stand.
          showSignatures: widget.visit == null && !widget.embedded,
          // A draft is persisted the moment evidence lands, so a photograph
          // never points at a record that was never saved.
          onChanged: () => unawaited(_persist(completed: false)),
        ),
      ),

      // Named for the grading under the labelling, where the label's own
      // rejection form sits just above it.
      poultrySection(
          widget.embedded ? 'Grading Rejection Form' : 'Rejection Form'),
      poultryDropdown(
        label: 'Grading Non-Conformance Remarks',
        value: _remarkTypeId,
        items: reference.remarks,
        onChanged: (v) => setState(() => _remarkTypeId = v),
      ),
      poultryField(_directionRemarks, 'Added Remarks', lines: 2),
      poultryField(_directionComments, 'Comments/Remarks on Rejection',
          lines: 3),
      // Opens on FSA-SOP-APS-001 Annexure C's date; the inspector may move it
      // later, never into the past (see CorrectByDateField).
      CorrectByDateField(
        value: _correctBy,
        sopDate: _sopCorrectBy,
        helperText: _periodHelper(reference),
        onChanged: _correctByChanged,
      ),
      // A seizure declined says nothing here: the rejection above stands
      // as it is (Ethan, 2026-09-30).
      if (_seizureDecision == SeizureDecision.seize) _seizureNotice(),

      // Under the labelling, the label checklist signs and saves it.
      if (!widget.embedded) ...[
        if (widget.visit == null) ...[
          poultrySection('Signatures Control'),
          poultryField(_managerName, 'Authorised Representative name'),
          poultryField(_managerEmail, 'Representative Email address',
              keyboard: TextInputType.emailAddress),
          poultryField(_clientEmail, 'Email address #1',
              keyboard: TextInputType.emailAddress),
          poultryField(_clientEmail2, 'Email address #2',
              keyboard: TextInputType.emailAddress),
          poultryField(_inspectionComments, 'General Comments', lines: 3),
        ],
        // Inside a grouped inspection the manager and inspector sign
        // once, at the end, and those signatures are stamped onto every
        // record in the group — so this record does not ask again.
        if (widget.visit != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'This record is part of a grouped inspection. The manager '
              'and inspector sign once, at the end, and those signatures '
              'are applied to every record in it.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.4),
            ),
          ),
        // The "No Client Signature is available" control lives in the
        // Signatures block above — one tick-box, not two that can disagree.

        const SizedBox(height: 20),
        // No Save draft: going back keeps the work as a draft, and the
        // visit shows it in progress (Ethan, 2026-09-30).
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _saving ? null : () => _save(reference, completed: true),
            child: Text(_saving ? 'Saving…' : 'Complete'),
          ),
        ),
      ],
    ];
    return Form(
      key: _formKey,
      child: widget.embedded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : ListView(
              // Clear the system navigation bar: the submit button is the
              // last thing on the page, and the bar was drawing over it and
              // taking the tap — which dropped the inspector out of the app
              // mid-save.
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: children,
            ),
    );
  }
}

/// Shown when the device holds no poultry rules at all.
