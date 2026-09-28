import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/batch_number.dart';
import '../../../core/data/local_database.dart';
import '../../../core/data/restricted_particulars_catalogue.dart';
import '../../../core/services/in_app_camera.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../data/eggs_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../data/eggs_sync_service.dart';
import 'date_field.dart';
import 'egg_direction_form.dart';
import 'new_directory_entry_sheet.dart';
import 'picker_sheet.dart';
import '../../../core/widgets/required_label.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import 'saved_dialog.dart';
import '../../../core/widgets/search_picker.dart';
import '../domain/egg_rules.dart';
import '../../poultry/presentation/signature_pad.dart';
import '../../../core/widgets/picker_menu_field.dart';
import '../../../core/data/regulation_reference.dart';

/// Poultry Egg inspection capture.
///
/// The distinctive part versus Fruit & Veg is per-egg sampling: each egg in
/// the sample is weighed, auto-sized from its mass, optionally Haugh-measured,
/// and has its own deviations ticked. Grade falls out of those deviations.
class EggInspectionForm extends StatefulWidget {
  const EggInspectionForm({
    super.key,
    required this.repository,
    required this.inspectorName,
    this.syncService,
    this.resumeUuid,
    this.visit,
  });

  final EggsRepository repository;
  final String inspectorName;

  /// Sends the record the moment it is saved, when there is a signal. Optional
  /// so the form can be exercised without a network stack.
  final EggsSyncService? syncService;

  /// An unfinished inspection to pick back up. Set when the app was killed
  /// mid-capture — usually because Android reclaimed memory while the camera
  /// was in front — and the inspector chose to resume rather than start again.
  final String? resumeUuid;

  /// Set when this inspection is one of several at the same store. The
  /// facility, contact and manager fields arrive already filled from the
  /// visit, and the signatures are taken once at the end of the visit
  /// rather than on this form.
  final VisitPrefill? visit;

  @override
  State<EggInspectionForm> createState() => _EggInspectionFormState();
}

/// One egg being captured.
///
/// The egg owns the text in its own fields rather than letting the widgets
/// hold it. Uncontrolled fields keep their contents against a *position* in the
/// list, and this list changes shape underneath them: the "further samples
/// required" banner appears above it, eggs get deleted from the middle, and a
/// resumed draft refills it. Every one of those shifted the readings into the
/// wrong egg or wiped them.
class _Sample {
  _Sample(this.number);

  final int number;

  final massController = TextEditingController();
  final albumenController = TextEditingController();

  double? massG;
  double? albumenHeightMm;
  final Set<int> deviationIds = {};

  EggSizeBand? size;
  EggGradeRef? grade;
  double? haugh;

  /// Puts stored readings into the fields — used when a draft is resumed,
  /// where the values exist but nothing has typed them.
  void fillControllers() {
    massController.text = massG == null ? '' : _trim(massG!);
    albumenController.text =
        albumenHeightMm == null ? '' : _trim(albumenHeightMm!);
  }

  /// 52.0 reads better as "52" on a scale display.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  void dispose() {
    massController.dispose();
    albumenController.dispose();
  }
}

class _Shot {
  _Shot({required this.kind, required this.path});
  final String kind;
  final String path;
}

class _EggInspectionFormState extends State<EggInspectionForm> {
  /// The record's identity. A resumed draft keeps the uuid it was saved
  /// under, so continuing writes back to the same row rather than orphaning
  /// the photographs already attached to it.
  late final String _uuid = widget.resumeUuid ?? const Uuid().v4();

  /// Photograph rows already written to the database, by file path. Photos are
  /// stored the moment they are taken rather than at save, so a process death
  /// on the very next screen cannot lose them.
  final _photoRowIds = <String, int>{};

  /// True while the draft is being written, to keep concurrent saves out of
  /// each other's way.
  bool _savingDraft = false;

  /// When capture began. Held so a resumed draft keeps its original time
  /// rather than jumping to whenever it was picked back up.
  DateTime _startedAt = DateTime.now();
  bool _saving = false;
  bool _loading = true;

  // Reference
  List<EggSizeBand> _bands = [];
  List<EggGradeRef> _gradeRefs = [];

  /// The size picker's own "Not indicated", offered beside the mass bands.
  ///
  /// A pack that declares no size is the same case as one that declares no
  /// grade: the marking requirement is not met, and there is no claim for
  /// the weighed sample to be measured against. Leaving the picker alone
  /// said neither — it read as a question nobody had answered, and the
  /// inspection could not be saved at all, because the size is required.
  ///
  /// Kept out of [_bands], which is what each weighed egg is sized against:
  /// a band with no mass range would swallow every egg.
  static const _sizeNotIndicated = EggSizeBand(
    id: -1,
    name: 'Not indicated',
    minMassG: 0,
    maxMassG: null,
    sortOrder: 999,
    isMassBand: false,
  );

  /// The picker's contents: the office's bands, and "Not indicated".
  List<EggSizeBand> get _sizeOptions =>
      [..._bands, if (_bands.isNotEmpty) _sizeNotIndicated];

  /// The tray picker's own "Not indicated".
  ///
  /// Eggs are met loose and in unmarked trays, and the pack size is required
  /// before the marking checklists open — so with nothing to choose that
  /// meant "the pack does not say", the inspection could not be started at
  /// all. Annexure D of FSA-SOP-APS-001 treats an omitted indication as an
  /// omission rather than a mis-statement, which is the inspector's to
  /// record, not to guess at.
  static const _trayNotIndicated = EggTraySize(
    id: -1,
    name: 'Not indicated',
    eggCount: 0,
    sortOrder: 999,
    isActive: true,
    updatedAt: '',
  );

  List<EggTraySize> get _trayOptions =>
      [..._traySizes, if (_traySizes.isNotEmpty) _trayNotIndicated];

  /// The grade picker's own "Not indicated", offered beside Grade 1/2/3.
  ///
  /// A pack that declares no grade had to be answered by leaving the picker
  /// alone, which read as an unanswered question and contradicted the
  /// labelling checklist, where the row is left as a deviation precisely
  /// because no grade is indicated. Now the inspector says so.
  ///
  /// It is not a grade the office holds: id -1 is the value the rules
  /// already read as "no grade", so the tolerances that key off a declared
  /// grade are simply not applied, and the id survives a draft without a
  /// column of its own.
  static const _gradeNotIndicated =
      EggGradeRef(id: -1, name: 'Not indicated', rank: 0);

  /// The picker's contents: the office's grades, and "Not indicated".
  List<EggGradeRef> get _gradeOptions =>
      [..._gradeRefs, if (_gradeRefs.isNotEmpty) _gradeNotIndicated];
  List<DeviationRef> _deviationRefs = [];
  List<EggDeviationCategory> _categories = [];
  List<EggFacilityType> _facilityTypes = [];

  List<EggInspectionReason> _reasons = [];
  List<EggTraySize> _traySizes = [];
  List<EggRequirement> _labelPack = [];
  List<EggRequirement> _labelOuter = [];
  List<EggRequirement> _packing = [];
  List<EggRestrictedParticular> _particulars = [];

  /// Every commodity's list, so this form offers the same menu as the rest.
  List<String> _sharedParticulars = const [];
  Map<int, List<EggDeviation>> _deviationsByCategory = {};

  List<EggFacility> _facilities = [];
  List<EggSupplier> _suppliers = [];

  // Selections
  EggFacilityType? _facilityType;
  EggInspectionReason? _reason;
  EggTraySize? _traySize;

  /// What the consignment is sold as. Deviation tolerances are keyed on these,
  /// so a Grade 1 Jumbo claim is held to a tighter standard than a Grade 3
  /// Small one. Not the same thing as the grade the inspection determines.
  EggSizeBand? _declaredSize;
  EggGradeRef? _declaredGrade;

  /// The bands a deviation count must stay inside, and which labelling
  /// checklist each requirement sits on. Loaded with the rest of the reference
  /// data so saving does not wait on a query.
  List<DeviationTolerance> _tolerances = [];
  Map<LabelChecklist, Set<int>> _checklists = const {};
  final _failedRequirements = <int>{};
  final _selectedParticulars = <int>{};

  /// Particulars typed in because the Agency's list did not have them.
  final _typedParticulars = <String>{};
  final _samples = <_Sample>[];
  Position? _position;
  final _photos = <_Shot>[];
  bool _pasteurised = false;

  /// The original's `switchIsOuterPackagingAvailable`: the outer-packaging
  /// checklist only shows once the inspector confirms outer labelling is
  /// there to inspect.
  bool _outerAvailable = false;

  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();

  /// Captured signatures by role ('manager' / 'inspector').
  final Map<String, EggSignature> _signaturesByRole = {};
  bool _haughNotRequired = false;

  /// `Constants.MinQualityTrayLabelPhotos` — at least two egg quality
  /// deviation photographs. The original's own words: "the 1st TWO set of
  /// photos will be included in the DIRECTION. Additional photos will be
  /// stored for future reference."
  /// How many photographs every block on this form asks for.
  ///
  /// Two, as the poultry label and QUID checklists have always asked for
  /// ([PoultryRules.requiredPhotos]) — one shot rarely shows both what was
  /// found and where it was found, and the office cannot go back for a
  /// second. The quality-deviation row already worked this way; the label
  /// and egg-numbering rows asked for one, so the same evidence arrived at
  /// two standards depending on which row took it.
  static const _minPhotos = 2;

  static const _minQualityDeviationPhotos = _minPhotos;

  /// The original shows its "at least (TWO) 2 photos" notice once per
  /// inspection, on the first tap of Take Egg Photos
  /// (`_qualityDirectivePhotoMsgFlag`).
  bool _qualityPhotoNoticeShown = false;

  /// The original's `switchEggWeighingInspectionNotRequired`, offered at a
  /// retailer only. Confirming it takes the sizing and grading block off the
  /// page and moves the inspection straight to signature.
  bool _weighingNotRequired = false;

  // Text
  final _facilityName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityPhone = TextEditingController();
  final _clientName = TextEditingController();
  final _clientAddress = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNumber = TextEditingController();
  final _clientEmail = TextEditingController();
  final _representative = TextEditingController();
  final _producer = TextEditingController();
  final _batch = TextEditingController();

  /// Watched so an empty batch box fills itself in with N/A the moment the
  /// inspector moves off it.
  final _batchFocus = FocusNode();

  final _nonConformance = TextEditingController();
  DateTime? _bestBefore;

  EggGradeRef? _consignmentGrade;

  /// The required fields a refused submit flagged, so the page can take the
  /// inspector to the first and mark each red.
  final _missing = MissingFields();

  @override
  void initState() {
    super.initState();
    // The Egg Size picker opens once a producer is settled, and a producer
    // can be typed into the box as well as picked from it — so the gate
    // watches the box rather than a second entry beside it.
    _producer.addListener(_producerChanged);
    _batchFocus.addListener(_normaliseBatch);
    _applyVisitPrefill();
    _load();
  }

  @override
  void dispose() {
    _producer.removeListener(_producerChanged);
    _batchFocus.removeListener(_normaliseBatch);
    _batchFocus.dispose();
    _scroll.dispose();
    _weightEntry.dispose();
    _haughEntry.dispose();
    for (final sample in _samples) {
      sample.dispose();
    }
    for (final c in [
      _facilityName,
      _facilityAddress,
      _facilityPhone,
      _clientName,
      _clientAddress,
      _contactPerson,
      _contactNumber,
      _clientEmail,
      _representative,
      _producer,
      _batch,
      _nonConformance,
    ]) {
      c.dispose();
    }
    _missing.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = widget.repository;
    _bands = await r.sizeBands();
    _gradeRefs = await r.gradeRefs();
    _deviationRefs = await r.deviationRefs();
    _categories = await r.deviationCategories();
    _facilityTypes = await r.facilityTypes();
    // Chosen once at the door: find this commodity's row for it.
    final doorType = widget.visit?.facilityType ?? '';
    if (_facilityType == null && doorType.isNotEmpty) {
      final i = FacilityTypeMatch.indexOf(
          doorType, _facilityTypes.map((t) => t.name).toList());
      if (i != null) {
        _facilityType = _facilityTypes[i];
      }
    }
    // Inspection or Follow-up only; eggs' "Complaint" row is not offered.
    _reasons = [
      for (final reason in await r.reasons())
        if (InspectionReasonMatch.isOffered(reason.name)) reason,
    ];
    // And why it is being made — also answered once, at the door.
    final doorReason = widget.visit?.inspectionReason ?? '';
    if (_reason == null && doorReason.isNotEmpty) {
      final i = InspectionReasonMatch.indexOf(
          doorReason, _reasons.map((x) => x.name).toList());
      if (i != null) {
        _reason = _reasons[i];
      }
    }
    _traySizes = await r.traySizes();
    _tolerances = await r.deviationTolerances();
    _checklists = await r.requirementChecklists();
    _labelPack = await r.requirements('label_pack');
    _labelOuter = await r.requirements('label_outer');
    _packing = await r.requirements('packing');
    _particulars = await r.restrictedParticulars();
    _sharedParticulars = await RestrictedParticularsCatalogue.names(r.database);
    _facilities = await r.facilities();
    _suppliers = await r.suppliers();
    _deviationsByCategory = {
      for (final c in _categories) c.id: await r.deviationsFor(c.id),
    };
    // Every requirement starts Compliant, so the inspector marks only what
    // is wrong.
    //
    // The rows used to start as deviations, on the reasoning that the app
    // must not claim a requirement was met before anyone had looked. In the
    // field that inverted the work: a compliant pack meant moving twenty
    // rows one at a time, and any row missed in that sweep became a
    // deviation the inspector never intended. A deviation is the exception
    // on a normal pack, so it is the exception that gets marked
    // (FSA, 2026-09-07).
    _failedRequirements.clear();
    if (widget.resumeUuid != null) {
      await _restoreDraft();
      // The restore writes every field, blanks included, so anything the
      // draft never captured comes back from the visit here.
      _applyVisitPrefill();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Reloads an unfinished inspection into the form.
  ///
  /// Everything the inspector had entered comes back: the facility and client,
  /// the consignment, every egg with its readings and ticked deviations, the
  /// labelling failures, and the photographs already taken.
  Future<void> _restoreDraft() async {
    final r = widget.repository;
    final draft = await r.inspectionByUuid(_uuid);
    if (draft == null) return;

    _startedAt = draft.inspectedAt;
    _facilityName.text = draft.facilityName;
    _facilityAddress.text = draft.facilityAddress;
    _facilityPhone.text = draft.facilityPhone;
    _clientName.text = draft.clientName;
    _clientAddress.text = draft.clientAddress;
    _contactPerson.text = draft.clientContactPerson;
    _contactNumber.text = draft.clientContactNumber;
    _clientEmail.text = draft.clientEmail;
    _representative.text = draft.representativeName;
    _managerName.text = draft.managerName;
    _managerEmail.text = draft.managerEmail;
    for (final sig in await r.signaturesFor(_uuid)) {
      _signaturesByRole[sig.role] = sig;
    }
    _producer.text = draft.producerSupplier;
    _batch.text = draft.batchNumber;
    _nonConformance.text = draft.nonConformanceComments;
    _bestBefore = draft.bestBefore;
    _pasteurised = draft.pasteurisedPresent;
    _haughNotRequired = draft.haughNotRequired;
    _weighingNotRequired = draft.weighingNotRequired;
    _outerAvailable = draft.outerLabellingAvailable;

    _facilityType =
        _facilityTypes.where((t) => t.id == draft.facilityTypeId).firstOrNull;
    _reason = _reasons.where((x) => x.id == draft.reasonId).firstOrNull;
    _traySize = draft.traySizeId == _trayNotIndicated.id
        ? _trayNotIndicated
        : _traySizes.where((t) => t.id == draft.traySizeId).firstOrNull;
    _seizureDecision = SeizureDecision.of(draft.seizureDecision);
    // A record that already carries an answer does not ask again.
    _seizureAsked = _seizureDecision != null;
    _eggsExpressionAbsent = draft.eggsExpressionAbsent;
    _bestBeforeAbsent = draft.bestBeforeAbsent;
    _declaredSize = draft.declaredSizeId == _sizeNotIndicated.id
        ? _sizeNotIndicated
        : _bands.where((b) => b.id == draft.declaredSizeId).firstOrNull;
    _declaredGrade = draft.declaredGradeId == _gradeNotIndicated.id
        ? _gradeNotIndicated
        : _gradeRefs.where((g) => g.id == draft.declaredGradeId).firstOrNull;

    int? asId(String v) => int.tryParse(v.trim());
    _failedRequirements
      ..clear()
      ..addAll(
          draft.failedRequirementIds.split(',').map(asId).whereType<int>());
    _selectedParticulars
      ..clear()
      ..addAll(
        draft.restrictedParticularIds.split(',').map(asId).whereType<int>(),
      );
    _typedParticulars
      ..clear()
      ..addAll(TypedParticulars.unpack(draft.restrictedParticularsText));

    for (final old in _samples) {
      old.dispose();
    }
    _samples.clear();
    for (final row in await r.samplesFor(_uuid)) {
      final sample = _Sample(row.eggNumber)
        ..massG = row.massG
        ..albumenHeightMm = row.albumenHeightMm;
      sample.deviationIds.addAll(
        row.deviationIds.split(',').map(asId).whereType<int>(),
      );
      // Size, Haugh, automatic deviations and grade are derived, so
      // recompute rather than trust a stored value that may predate a rule
      // change.
      _applyDerived(sample);
      // The readings exist on the record but nothing has typed them into
      // the fields, so put them there.
      sample.fillControllers();
      _samples.add(sample);
    }
    _consignmentGrade =
        EggRules.consignmentGrade([for (final x in _samples) x.grade]);

    // Land on the highest captured egg, ready to carry on from there.
    _currentEggNumber = _samples.isEmpty
        ? 1
        : _samples.map((x) => x.number).reduce((a, b) => a > b ? a : b);
    _loadCurrentEggIntoEntries();

    _photos.clear();
    _photoRowIds.clear();
    for (final photo in await r.photosFor(_uuid)) {
      _photos.add(_Shot(kind: photo.kind, path: photo.filePath));
      _photoRowIds[photo.filePath] = photo.id;
    }
  }

  /// Registers premises the directory does not hold, then selects them.
  Future<void> _addFacility(String typedName) async {
    final values = await showNewDirectoryEntrySheet(
      context,
      title: 'New premises',
      subtitle: 'Registered on the server so the next inspector here finds '
          'them on the list rather than typing the name again.',
      saveLabel: 'Add premises',
      fields: [
        DirectoryField(
            label: 'Name', key: 'name', initial: typedName, isRequired: true),
        const DirectoryField(label: 'Physical address', key: 'address'),
        const DirectoryField(
            label: 'Telephone / cellphone',
            key: 'telephone',
            keyboardType: TextInputType.phone),
      ],
    );
    if (values == null || !mounted) return;

    try {
      final facility = await widget.repository.addFacility(
        name: values['name'] ?? typedName,
        facilityTypeId: _facilityType?.id,
        physicalAddress: values['address'] ?? '',
        telephone: values['telephone'] ?? '',
      );
      if (!mounted) return;
      setState(() => _facilities = [..._facilities, facility]);
      _onFacilitySelected(facility);
      _toast('Premises added.');
    } on Object catch (e) {
      if (mounted) _toast('Could not add the premises. $e');
    }
  }

  /// Registers an egg producer or packer the directory does not hold.
  Future<void> _addSupplier(String typedName) async {
    final values = await showNewDirectoryEntrySheet(
      context,
      title: 'New egg supplier',
      subtitle: 'Registered on the server so the same farm is not spelled '
          'three ways across three inspections.',
      saveLabel: 'Add supplier',
      fields: [
        DirectoryField(
            label: 'Name', key: 'name', initial: typedName, isRequired: true),
        const DirectoryField(label: 'Physical address', key: 'address'),
        const DirectoryField(label: 'Contact person', key: 'contact'),
        const DirectoryField(
            label: 'Telephone / cellphone',
            key: 'telephone',
            keyboardType: TextInputType.phone),
        const DirectoryField(
            label: 'Email',
            key: 'email',
            keyboardType: TextInputType.emailAddress),
      ],
    );
    if (values == null || !mounted) return;

    try {
      final supplier = await widget.repository.addSupplier(
        name: values['name'] ?? typedName,
        physicalAddress: values['address'] ?? '',
        contactPerson: values['contact'] ?? '',
        telephone: values['telephone'] ?? '',
        email: values['email'] ?? '',
      );
      if (!mounted) return;
      setState(() {
        _suppliers = [..._suppliers, supplier];
        _producer.text = supplier.name;
      });
      _toast('Supplier added.');
    } on Object catch (e) {
      if (mounted) _toast('Could not add the supplier. $e');
    }
  }

  /// Fills the facility fields from the picked premises. Editable afterwards,
  /// for the same reason as clients: details change in the field.
  void _onFacilitySelected(EggFacility facility) {
    setState(() {
      _facilityName.text = facility.name;
      _facilityAddress.text = facility.physicalAddress;
      _facilityPhone.text = facility.telephone;
      _facilityType = _facilityTypes
          .where((t) => t.id == facility.facilityTypeId)
          .firstOrNull;
      // The original searches its client table from this one box — the
      // control is literally called ClientAutoSuggestBox while carrying the
      // "Inspection Facility Name" label. The premises IS the client, so the
      // record's client columns follow the selection rather than being
      // captured a second time.
      _clientName.text = facility.name;
      _clientAddress.text = facility.physicalAddress;
      _contactNumber.text = facility.telephone;
    });
  }

  /// Recomputes everything derived on one egg: its size band, Haugh unit,
  /// the deviations the original's grading engine ticks by itself — the
  /// weight checks against the declared size and the Haugh checks against
  /// the declared grade — and finally its grade. Automatic ticks are
  /// stripped and re-derived each time, so a corrected reading clears the
  /// deviation it no longer justifies, exactly as the original clears them.
  void _applyDerived(_Sample s) {
    s.size = EggRules.sizeFor(s.massG, _bands);
    final haughRaw = _haughNotRequired
        ? null
        : EggRules.haughUnit(
            albumenHeightMm: s.albumenHeightMm,
            massG: s.massG,
          );
    // The original stores Math.Round of the formula's result
    // (entryHaughMeterValue_Completed) and every later comparison reads the
    // rounded figure — the rounding is part of the rules, not the display.
    s.haugh = haughRaw?.roundToDouble();
    s.deviationIds
      ..removeAll(EggRules.autoManagedDeviationIds(_deviationRefs))
      ..addAll(EggRules.autoWeightDeviationIds(
        massG: s.massG,
        declaredSize: _declaredSize,
        declaredGrade: _declaredGrade,
        deviations: _deviationRefs,
      ))
      ..addAll(EggRules.autoAlbumenDeviationIds(
        haughUnit: s.haugh,
        declaredGrade: _declaredGrade,
        pasteurised: _pasteurised,
        deviations: _deviationRefs,
      ));
    s.grade = EggRules.gradeForEgg(
      tickedDeviationIds: s.deviationIds,
      deviations: _deviationRefs,
      grades: _gradeRefs,
    );
  }

  /// Recomputes size, Haugh unit and grade for one egg, then the consignment.
  void _recalculate(_Sample s) {
    _applyDerived(s);
    _consignmentGrade =
        EggRules.consignmentGrade([for (final x in _samples) x.grade]);
    _updateHaughBaseline();
    setState(() {});
  }

  /// Re-derives every egg — the declared size, grade and pasteurised switch
  /// feed the automatic deviations, so changing one re-evaluates the whole
  /// sample the way the original's engine re-runs over every egg.
  void _recalculateAll() {
    for (final s in _samples) {
      _applyDerived(s);
    }
    _consignmentGrade =
        EggRules.consignmentGrade([for (final x in _samples) x.grade]);
    _updateHaughBaseline();
    setState(() {});
  }

  /// Fixes the baseline the moment the mean drops below the threshold, and
  /// clears it if further readings bring the mean back up.
  void _updateHaughBaseline() {
    final mean = EggRules.meanHaughUnit([for (final x in _samples) x.haugh]);
    if (mean == null || mean >= EggRules.haughAdditionalSampleThreshold) {
      _haughBaseline = null;
      return;
    }
    _haughBaseline ??= _samples.length;
  }

  /// Which photo row is mid-capture, so its button can show progress rather
  /// than the screen appearing to hang while the plugin re-encodes.
  String? _capturingKind;

  Future<void> _capturePhoto(String kind, String label) async {
    // One at a time. Two cameras in flight would race on the file name and
    // leave a photo attributed to the wrong row.
    if (_capturingKind != null) return;

    // The original says this once per inspection, before the first egg
    // quality deviation photograph.
    if (kind == 'egg' && !_qualityPhotoNoticeShown) {
      _qualityPhotoNoticeShown = true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Egg Quality Deviation Photos'),
          content: const Text(
            'Please note that at least (TWO) 2 photos are required. The 1st '
            'TWO set of photos will be included in the REJECTION. Additional '
            'photos will be stored for future reference.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    // Captured inside the app rather than by handing off to the phone's camera
    // app. The handover backgrounded this app while an inspection was open,
    // and Android reclaimed it — see in_app_camera.dart for the measurements.
    final String? shotPath;
    try {
      shotPath = await capturePhoto(
        context,
        title: label.replaceAll('*', '').trim(),
      );
    } on Object catch (e) {
      if (mounted) _toast('The camera could not be opened. $e');
      return;
    }
    if (shotPath == null) return;

    setState(() => _capturingKind = kind);
    try {
      final storage = await PhotoStorage.instance();
      // Millisecond stamp rather than a running count: a deleted photo would
      // make the count repeat and overwrite an existing file.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await storage.adopt(
        File(shotPath),
        name: 'egg_${_uuid}_${kind}_$stamp.jpg',
      );

      // Persist before returning to the form. A photograph that exists only in
      // memory is lost the moment Android reclaims the process — which taking
      // the photograph is itself the most likely cause of.
      await _saveDraft();
      final id = await widget.repository.addPhotoReturningId(
        EggPhotosCompanion.insert(
          inspectionUuid: _uuid,
          kind: kind,
          filePath: path,
          capturedAt: DateTime.now(),
        ),
      );
      _photoRowIds[path] = id;

      if (mounted) {
        setState(() => _photos.add(_Shot(kind: kind, path: path)));
      }
    } on Object catch (e) {
      if (mounted) _toast('The photo could not be saved. $e');
    } finally {
      if (mounted) setState(() => _capturingKind = null);
    }
  }

  Future<void> _removePhoto(_Shot shot) async {
    setState(() => _photos.remove(shot));
    final id = _photoRowIds.remove(shot.path);
    if (id != null) await widget.repository.deletePhoto(id);
    final storage = await PhotoStorage.instance();
    await storage.delete(shot.path);
  }

  /// [silent] suppresses user-facing messages, for the automatic fix taken
  /// when the form opens. A failure there is not something to interrupt an
  /// inspector about — the Photos step shows the state and offers a retry.
  Future<void> _captureLocation({bool silent = false}) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent) {
          _toast('Location permission is off. Enable it in system settings.');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) setState(() => _position = pos);
    } on Object catch (e) {
      if (!silent) _toast('Could not get a location fix. $e');
    }
  }

  /// Turns the send result into something the inspector can act on.
  SavedState _savedState(bool sent, EggsSyncService? sync) {
    if (sent) return SavedState.sent;
    return switch (sync?.lastOutcome) {
      SendOutcome.notAuthenticated => SavedState.needsSignIn,
      SendOutcome.rejected => SavedState.rejected,
      // Offline, or a hiccup worth retrying. Either way the service handles it.
      _ => SavedState.queued,
    };
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  /// Everything that must hold before an inspection can be saved.
  ///
  /// Each check corresponds to a rule the
  /// `NewPoultyEggInspectionPage` performed, so an inspector cannot save
  /// something here that the old app would have rejected.
  ///
  /// Every problem, in the order the checks run — the first is the one the
  /// submit names — each with the [_missing] id of the field that answers
  /// it. The id is null where that field is not on the page, so there is
  /// nothing to take the inspector to.
  List<({String? id, String message})> _blockingIssues() {
    final issues = <({String? id, String message})>[];
    void add(String? id, String message) =>
        issues.add((id: id, message: message));
    // The sizing block, which holds the best-before date, the batch number
    // and the egg entry, is only on the page while sampling is.
    String? sizing(String id) => _samplingVisible ? id : null;

    // --- Facility
    if (_facilityName.text.trim().isEmpty) {
      add(widget.visit == null ? 'facilityName' : null,
          'Inspection facility name is required.');
    }
    // Inside a visit these are the door's answers, not this form's, and the
    // form no longer shows them — so it must not refuse to save on a field
    // the inspector cannot see. Where the door's answer is not one the egg
    // rules offer, the record simply carries none.
    if (widget.visit == null) {
      if (_facilityType == null) {
        add('facilityType', 'Facility type must be selected.');
      }
      if (_reason == null) {
        add('reason', 'Reason for inspection must be selected.');
      }
    }

    // --- Product
    if (_producer.text.trim().isEmpty) {
      add(_producerFromVisit ? null : 'producer',
          'Egg producer / supplier is required.');
    }
    final batch = BatchNumber.missing(_batch.text);
    if (batch != null) {
      add(sizing('batch'), batch);
    } else if (!_batchEntryValid(_batch.text)) {
      add(
          sizing('batch'),
          'The batch number must be a number, or N/A — nothing else '
          'counts as a batch.');
    }
    if (_traySize == null) {
      add('traySize', 'Tray packaging size must be selected.');
    }
    // Without these there is no tolerance band to judge deviations against,
    // so whether a direction must be served cannot be answered.
    if (_declaredSize == null) {
      add('declaredSize',
          'The size the consignment is sold as must be selected.');
    }

    final bestBefore = EggValidation.bestBefore(_bestBefore);
    if (bestBefore != null) add(sizing('bestBefore'), bestBefore);

    // --- Samples
    //
    // Skipped entirely when the inspector has recorded that no weighing was
    // possible at this retailer: the sizing and grading block is off the
    // screen, so demanding an egg from it asks for something the form no
    // longer offers, and the inspection could not be saved at all.
    //
    // Only the first problem with the samples is named: each one is answered
    // at the same egg entry.
    String? sampleIssue() {
      if (_samples.isEmpty) return 'Capture at least one egg before saving.';
      if (_samples.length > EggValidation.maxSamples) {
        return 'Maximum number of samples reached '
            '(${EggValidation.maxSamples}).';
      }

      for (final s in _samples) {
        if (s.massG == null || s.massG! <= 0) {
          return 'Egg #${s.number} has no weight reading.';
        }
        // A weight above the sanity ceiling is flagged under the field but
        // does not stop the inspection being saved. It guards against a
        // mis-keyed scale reading rather than enforcing a regulation, and an
        // inspector holding a genuinely heavy egg must still be able to
        // record it.
        final albumen = EggValidation.albumenHeight(s.albumenHeightMm);
        if (albumen != null) return 'Egg #${s.number}: $albumen';
      }

      if (_outstandingSamples > 0) {
        return 'Mean Haugh value is below '
            '${EggRules.haughAdditionalSampleThreshold.toStringAsFixed(0)} '
            'HU — $_outstandingSamples further sample(s) required.';
      }
      return null;
    }

    if (EggValidation.samplesRequired(
        weighingNotRequired: _weighingNotRequired)) {
      final sample = sampleIssue();
      if (sample != null) add(sizing('eggEntry'), sample);
    }

    // --- Evidence. Message: "No photo of the label has been taken. Please
    // address." A labelling finding without a photograph cannot be defended.
    if (!_photos.any((p) => p.kind == 'label')) {
      add('photo:label',
          'No photo of the label has been taken. Please address.');
    }

    // An address is taken as typed. A malformed one is a typo, not a
    // reason to refuse an inspection: the server keeps it either way, and
    // blocking sign-off here stranded finished inspections on the handset
    // over an address the inspector often did not have to begin with.
    return issues;
  }

  /// The [_missing] ids of the sample set still owed before the inspection
  /// can be signed off — what [_qualitySetReadyToSave] waits on — in page
  /// order.
  List<String> _readinessMissing() => [
        if (_samplingVisible && !_qualitySetReadyToSave) ...[
          if (_photoCount('numbering') < _minPhotos) 'photo:numbering',
          if (_weighedCount < EggValidation.maxSamples ||
              (!_haughNotRequired &&
                  _haughCount < EggRules.haughReadingsRequired))
            'eggEntry',
        ],
      ];

  /// Every field a refused submit would flag now, for [_missing] to clear
  /// each one's red as it is answered.
  bool _stillMissing(String id) {
    if (_blockingIssues().any((i) => i.id == id)) return true;
    if (_readinessMissing().contains(id)) return true;
    if (id == 'photo:egg') return !_directionPhotosComplete;
    return false;
  }

  /// Shows [message], then takes the inspector to [ids] and marks them red.
  Future<void> _refuse(String message, List<String> ids) async {
    _toast(message);
    if (!mounted) return;
    // The egg entry shows one egg at a time; open the one that is short,
    // rather than point at whichever egg happens to be on screen.
    final short = _firstUnweighedEgg;
    if (ids.contains('eggEntry') && short != null && _samplingVisible) {
      _showEgg(short);
    }
    await _missing.flag(context, ids, stillMissing: _stillMissing);
  }

  /// Wraps a required field so a refused submit can scroll to it and mark
  /// it. [framed] outlines it for inputs that do not turn their own border
  /// red.
  Widget _anchor(
    String id,
    Widget child, {
    bool framed = false,
    Listenable? listenable,
  }) =>
      MissingFieldAnchor(
        fields: _missing,
        id: id,
        framed: framed,
        listenable: listenable,
        child: child,
      );

  /// Message: "Please confirm that you want to save the entire inspection with
  /// the info captured as is?" — and inside a grouped inspection, that
  /// submitting this record does not end the group: the flow carries on to
  /// the next planned inspection.
  Future<bool> _confirmSubmit() async {
    final inVisit = widget.visit != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          inVisit ? 'Finish this egg inspection' : 'Submit inspection',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
        ),
        content: Text(
          inVisit
              ? 'This egg inspection is saved with the information captured '
                  'as is — nothing is submitted yet.\n\n'
                  'You will return to the grouped inspection to carry on '
                  'with the next one in the plan. Everything is submitted '
                  'together when you sign off at the end.'
              : 'Please confirm that you want to save the entire inspection '
                  'with the information captured as is.',
          style: TextStyle(color: AppColors.inkSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(inVisit ? 'Save & Continue' : 'Confirm'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Writes what has been captured so far, as a draft.
  ///
  /// Drafts are never uploaded — the sync service skips anything that is not
  /// `completed` — so this is purely a safety net against the process dying.
  Future<void> _saveDraft() async {
    if (_savingDraft) return;
    _savingDraft = true;
    try {
      await widget.repository.saveInspection(
        _companion(status: 'draft'),
        _sampleCompanions(),
      );
    } on Object catch (error) {
      // A failed draft save must never interrupt capture; the inspector can
      // still finish and save normally.
      debugPrint('Could not save draft: $error');
    } finally {
      _savingDraft = false;
    }
  }

  /// The inspection row, at whatever stage it has reached.
  /// Copies the visit's shared facility details into this form's fields.
  /// Only empty fields take the value, so a resumed draft keeps what was
  /// typed on it.
  void _applyVisitPrefill() {
    final visit = widget.visit;
    if (visit == null) return;
    void fill(TextEditingController field, String value) {
      if (field.text.trim().isEmpty && value.isNotEmpty) field.text = value;
    }

    fill(_facilityName, visit.facilityName);
    fill(_facilityAddress, visit.facilityAddress);
    fill(_facilityPhone, visit.facilityPhone);
    fill(_producer, visit.producer);
    fill(_clientName, visit.facilityName);
    fill(_contactPerson, visit.contactPerson);
    fill(_clientEmail, visit.contactEmail);
    fill(_representative, visit.representative);
    fill(_managerName, visit.managerName);
    fill(_managerEmail, visit.managerEmail);
  }

  EggInspectionsCompanion _companion({required String status}) {
    final now = DateTime.now();
    return EggInspectionsCompanion.insert(
      clientUuid: _uuid,
      visitUuid: Value(widget.visit?.uuid ?? ''),
      inspectedAt: _startedAt,
      updatedAt: now,
      status: Value(status),
      facilityName: Value(_facilityName.text.trim()),
      facilityTypeId: Value(_facilityType?.id),
      facilityAddress: Value(_facilityAddress.text.trim()),
      facilityPhone: Value(_facilityPhone.text.trim()),
      reasonId: Value(_reason?.id),
      clientName: Value(_clientName.text.trim()),
      clientAddress: Value(_clientAddress.text.trim()),
      clientContactPerson: Value(_contactPerson.text.trim()),
      clientContactNumber: Value(_contactNumber.text.trim()),
      clientEmail: Value(_clientEmail.text.trim()),
      representativeName: Value(_representative.text.trim()),
      managerName: Value(_managerName.text.trim()),
      managerEmail: Value(_managerEmail.text.trim()),
      producerSupplier: Value(_producer.text.trim()),
      seizureDecision: Value(_seizureDecision?.stored ?? ''),
      eggsExpressionAbsent: Value(_eggsExpressionAbsent),
      bestBeforeAbsent: Value(_bestBeforeAbsent),
      batchNumber: Value(_batchForRecord),
      bestBefore: Value(_bestBefore),
      traySizeId: Value(_traySize?.id),
      declaredSizeId: Value(_declaredSize?.id),
      declaredGradeId: Value(_declaredGrade?.id),
      sampleSize: Value(_samples.length),
      pasteurisedPresent: Value(_pasteurised),
      haughNotRequired: Value(_haughNotRequired),
      weighingNotRequired: Value(_weighingNotRequired),
      outerLabellingAvailable: Value(_outerAvailable),
      labelChecklistComplete: Value(status != 'draft'),
      determinedGradeId: Value(_consignmentGrade?.id),
      // The grade stands as the inspection determined it; there is no
      // override on the form any more, so nothing can have set these.
      gradeOverridden: const Value(false),
      overrideReason: const Value(''),
      generalComments: const Value(''),
      nonConformanceComments: Value(_nonConformance.text.trim()),
      failedRequirementIds: Value(_failedRequirements.join(',')),
      restrictedParticularIds: Value(_selectedParticulars.join(',')),
      restrictedParticularsText:
          Value(TypedParticulars.pack(_typedParticulars)),
      latitude: Value(_position?.latitude),
      longitude: Value(_position?.longitude),
    );
  }

  List<EggSamplesCompanion> _sampleCompanions() => [
        for (final s in _samples)
          EggSamplesCompanion.insert(
            inspectionUuid: _uuid,
            eggNumber: s.number,
            massG: Value(s.massG),
            sizeId: Value(s.size?.id),
            gradeId: Value(s.grade?.id),
            albumenHeightMm: Value(s.albumenHeightMm),
            haughUnit: Value(s.haugh),
            deviationIds: Value(s.deviationIds.join(',')),
          ),
      ];

  Future<void> _save() async {
    final issues = _blockingIssues();
    if (issues.isNotEmpty) {
      // Taken to the first problem, the one the message names; every other
      // field still owed is marked red with it.
      await _refuse(issues.first.message, [
        for (final i in issues)
          if (i.id != null) i.id!,
      ]);
      return;
    }
    // The button used to stay greyed until the sample set was complete and
    // any rejection carried its photographs, which left the inspector with
    // nothing to press to find out what was still owed. The same two rules
    // now refuse the submit here instead, and point at the field.
    if (!_qualitySetReadyToSave) {
      final outstanding = _readinessOutstanding;
      await _refuse(
        _samplingVisible
            ? 'The sample set is not complete. Still outstanding: '
                '${outstanding.isEmpty ? 'the egg numbering photographs' : outstanding}.'
            : 'Signatures open once the labelling checklist is confirmed '
                'complete and the sample set has been captured.',
        _readinessMissing(),
      );
      return;
    }
    if (!_directionPhotosComplete) {
      await _refuse(
        'The rejection still needs: $_directionPhotosOutstanding.',
        const ['photo:egg'],
      );
      return;
    }
    if (_photos.isEmpty) {
      await _refuse('Capture at least one inspection photo before saving.',
          const ['photo:label']);
      return;
    }
    _missing.clear();
    if (!await _confirmSubmit()) return;
    if (!mounted) return;

    setState(() => _saving = true);

    // Inside a grouped inspection nothing submits per record: the member is
    // saved as `ready` and the one sign-off at the end of the group flips
    // everything to `completed` and lets it upload.
    final inVisit = widget.visit != null;
    try {
      // A standalone record has already been signed at this point. GPS is
      // stored silently now, not displayed while the form is being captured.
      if (!inVisit) await _captureLocation(silent: true);
      // Photographs were written as they were taken, so only the record and
      // its eggs need saving here.
      await widget.repository.saveInspection(
        _companion(status: inVisit ? 'ready' : 'completed'),
        _sampleCompanions(),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast('Could not save. $e');
      return;
    }

    // Saved. From here nothing can lose the record, so upload failures are
    // reported as "will send later" rather than as an error.
    var sent = false;
    final sync = widget.syncService;
    if (!inVisit && sync != null) {
      final saved = await widget.repository.inspectionByUuid(_uuid);
      if (saved != null) sent = await sync.sendNow(saved);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (!inVisit) {
      await showSavedDialog(
        context,
        noun: 'inspection',
        state: _savedState(sent, sync),
      );
      if (!mounted) return;
    }

    // A direction is a consequence of the findings, not a separate errand.
    // The original raises it as part of saving the inspection, and leaving it
    // to the inspector to remember is how a non-conforming consignment leaves
    // the premises with no notice served.
    // A sample that fails the size or grade standard is one Annexure D
    // seizes on, and that is only known once the weighing is complete.
    await _askAboutSeizureIfNeeded();
    if (!mounted) return;
    final required = _directionRequired();
    if (required.any) {
      await _raiseDirection(required);
      if (!mounted) return;
    }

    Navigator.of(context).pop();
  }

  /// Which parts of a direction the findings make compulsory.
  DirectionRequirement _directionRequired() {
    // How many eggs in the sample showed each deviation. The tolerance is on
    // the count across the sample, not on any single egg.
    final counts = <int, int>{};
    for (final sample in _samples) {
      for (final id in sample.deviationIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    final required = EggRules.directionRequired(
      countsByDeviationId: counts,
      // Validation blocks saving without these, so the fallback is only
      // reached on a record that could not have been saved.
      sizeId: _declaredSize?.id ?? -1,
      gradeId: _declaredGrade?.id ?? -1,
      tolerances: _tolerances,
      failedRequirementIds: _failedRequirements,
      checklists: _checklists,
    );
    // A pack with no grade designation fails Reg. 10 whatever else the
    // checklist says, and the rejection covers it under marking.
    if (_noGradeIndicated && !required.labelling) {
      return DirectionRequirement(
        quality: required.quality,
        labelling: true,
      );
    }
    return required;
  }

  /// Opens the direction, pre-filled, with the compulsory parts already set.
  Future<void> _raiseDirection(DirectionRequirement required) async {
    // The correction dates are the annexure's, counted from the inspection.
    final labelDays = EggRules.labellingRectificationDays(
      failed: _failedRows,
      eggsExpressionAbsent: _eggsExpressionAbsent,
      bestBeforeAbsent: _bestBeforeAbsent,
      designationOmitted:
          _noSizeIndicated || _noGradeIndicated || _noTrayIndicated,
    );
    final labelCorrectBy = required.labelling
        ? EggRules.correctBy(inspectedAt: _startedAt, days: labelDays ?? 30)
        : null;
    final qualityCorrectBy = required.quality
        ? EggRules.correctBy(
            inspectedAt: _startedAt, days: EggRules.qualityRectificationDays)
        : null;
    final periods = [
      if (required.labelling)
        'labelling: ${EggRules.periodLabel(labelDays ?? 30).toLowerCase()}',
      if (required.quality)
        'quality: ${EggRules.periodLabel(EggRules.qualityRectificationDays).toLowerCase()}',
    ].join('; ');
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        // Red, like everything else about a rejection: this is the moment
        // the inspection turns into one.
        icon: const Icon(Icons.gavel, size: 32, color: AppColors.brandRed),
        title: const Text('A rejection must be issued'),
        content: Text(
          '${_directionReason(required)}\n\n'
          'The rejection is filled in from this inspection. The correction '
          'dates follow FSA-SOP-APS-001 Annexure D ($periods). You write '
          'the remarks.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggDirectionForm(
          repository: widget.repository,
          inspectorName: widget.inspectorName,
          syncService: widget.syncService,
          inspectionUuid: _uuid,
          requirement: required,
          clientName: _clientName.text.trim(),
          producerSupplier: _producer.text.trim(),
          labelCorrectBy: labelCorrectBy,
          qualityCorrectBy: qualityCorrectBy,
          labelPeriod:
              required.labelling ? EggRules.periodLabel(labelDays ?? 30) : null,
          qualityPeriod: required.quality
              ? EggRules.periodLabel(EggRules.qualityRectificationDays)
              : null,
        ),
      ),
    );
  }

  String _directionReason(DirectionRequirement required) {
    if (_noGradeIndicated && !required.quality) {
      return 'The pack declares no grade. A grade designation is required, '
          'so the consignment is rejected on marking and there is nothing '
          'to weigh it against.';
    }
    if (required.quality && required.labelling) {
      return 'This consignment fails on both quality and labelling. One '
          'rejection covers both, each with its own correction date.';
    }
    if (required.quality) {
      return 'A deviation exceeds what is allowed for a consignment sold as '
          '${_declaredGrade?.name} ${_declaredSize?.name}.';
    }
    return 'The marking and packing requirements were not met.';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body:
              ContentWidth(child: Center(child: CircularProgressIndicator())));
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: const Text(
          'Egg Inspection Details',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      // One continuous form in the original page's order: inspection
      // details, the labelling checklists, client capture, the sizing and
      // grade checklist with per-egg particulars, then signatures and the
      // submit button at the bottom.
      body: ContentWidth(
          child: _pad([
        const RequiredLegend(),
        ..._inspectionDetailFields(),
        ..._declarationFields(),
        // At the FSA's request (2026-08-21) the label photographs sit above
        // the checklists and take up to three — the original kept a single
        // shot at the foot of the block.
        _photoRow('label', 'Add Label Photo *',
            minimum: _minPhotos, maximum: 3),
        _sectionHeader('Marking/Labelling - Packaging'),
        if (!_checklistUnlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Select the Tray Packaging Size above to open the '
              'marking/labelling checklists — the original unlocks them the '
              'same way.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
          ),
        IgnorePointer(
          ignoring: !_checklistUnlocked,
          child: Opacity(
            opacity: _checklistUnlocked ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _labellingFields(),
            ),
          ),
        ),
        // At a retailer the eggs cannot be broken open, so the original
        // offers these two switches there and nowhere else.
        if (_isRetailer) ..._retailerSwitches(),
        // The sizing and grading block is not on the page until the labelling
        // checklist is complete and any restricted particulars are listed.
        if (_samplingVisible) ...[
          _sectionHeader('Sizing and Grade Checklist'),
          ..._sizingChecklistFields(),
          _sectionHeader('Egg Particulars'),
          // btnPhotoEggNumbering is the sampling block's own photograph. The
          // original kept it at the foot of the block (Grid.Row 41 of
          // EggInspectionBlock); at the FSA's request (2026-08-28) it comes
          // first — the eggs are numbered and photographed, then weighed.
          // The two direction photographs are not here — they belong to the
          // Direction Form.
          _photoRow('numbering', 'Photo - Egg Numbering',
              minimum: _minPhotos, maximum: 3),
          ..._samplingFields(),
        ],
        // The direction form appears only once the sample set is signed off
        // and the findings actually call for a direction — quality, labelling
        // or both.
        if (_qualitySetReadyToSave && _directionBlockRequired) ...[
          _sectionHeader('Rejection Form'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'When the findings demand a rejection its form opens on '
              'submission, pre-filled from this inspection. Remarks, the '
              'correct-by dates and the quantity removed are captured there — '
              'the same particulars the original saves with the inspection.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
          ),
          // Grid.Row 10 of EggQualityDirectiveBlock, right after "Quantity
          // of Products Removed". The original enables each button only for
          // the kind of direction the findings raise — a labelling failure
          // asks for label photographs, a quality failure for egg ones — so
          // each row only appears when its direction is owed.
          //
          // These are not the same as "Add Label Photo" up in the labelling
          // checklist: that one evidences the label as found, these evidence
          // the direction being served. The original keeps two separate
          // lists, EggTrayLabellingPhotos and EggLabellingDirectivePhotoLists.
          if (_directionRequired().quality)
            _photoRow('egg', 'Take Egg Photos',
                minimum: _minQualityDeviationPhotos, maximum: 3),
          // The direction cannot be served without the photographs that
          // evidence it, so the record cannot be submitted without them.
          if (!_directionPhotosComplete)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.noticeBackground,
                border: Border.all(color: AppColors.noticeBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The rejection still needs: $_directionPhotosOutstanding.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.noticeForeground,
                ),
              ),
            ),
        ],
        // Signatures Control: on the page only when the original's
        // IsQualitySetReadyToSave is true.
        if (_qualitySetReadyToSave) ...[
          ..._resultFields(),
        ] else
          _notYetSignable(),
        const SizedBox(height: 14),
        // The original's Clear Form, reachable from the foot of the page:
        // reset this inspection to a clean slate rather than starting
        // another record.
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              side: const BorderSide(color: AppColors.brandPrimary),
            ),
            onPressed: _saving ? null : _clearEntireForm,
            icon: const Icon(Icons.restart_alt, size: 20),
            label: const Text('CLEAR FORM'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            // The original enables btnSaveRecords only once the sample set
            // is ready, the GPS reading is stored, both signatures are on the
            // record and any direction it raises carries its photographs.
            //
            // Those rules still hold, but in _save: the button stays pressable
            // so a press can take the inspector to whatever is still owed.
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.visit != null
                    ? 'DONE — NEXT INSPECTION'
                    : 'SUBMIT INSPECTION'),
          ),
        ),
      ])),
    );
  }

  /// Whether the findings call for a direction at all — the original's
  /// `IsQualityDirectionRequired || IsLabelDirectionRequired`.
  bool get _directionBlockRequired {
    final required = _directionRequired();
    return required.quality || required.labelling;
  }

  int _photoCount(String kind) => _photos.where((p) => p.kind == kind).length;

  /// `CheckAllConditionForSaveQualityDirection` and
  /// `CheckAllConditionForSaveLabelDirection`: a direction cannot be served
  /// without the photographs that evidence it. Where no direction of that
  /// kind is required the condition is met by default, exactly as the
  /// original short-circuits it.
  bool get _directionPhotosComplete {
    final required = _directionRequired();
    final quality =
        !required.quality || _photoCount('egg') >= _minQualityDeviationPhotos;
    // The label itself is captured once in the mandatory Label Photo row at
    // the top of this form. Do not ask for the same evidence again in the
    // direction block.
    return quality;
  }

  /// Which photographs the direction is still short of, named as the original
  /// names the buttons that take them.
  String get _directionPhotosOutstanding {
    final required = _directionRequired();
    return [
      if (required.quality && _photoCount('egg') < _minQualityDeviationPhotos)
        'Take Egg Photos (${_photoCount('egg')}/$_minQualityDeviationPhotos)',
    ].join(', ');
  }

  /// The two switches the original shows at a retailer and nowhere else.
  ///
  /// Eggs cannot be broken open on a retailer's premises, so the inspector
  /// may record that no Haugh readings are possible, or that no weighing
  /// operation was done at all. Both are confirmed before they take effect
  /// and neither can be switched back, exactly as the original has it.
  List<Widget> _retailerSwitches() => [
        YesNoQuestion(
          label: 'No Haugh readings required',
          bold: true,
          helper: 'Eggs cannot be broken open at this retailer.',
          value: _haughNotRequired,
          // Once answered Yes it cannot be taken back, exactly as the
          // original has it; the slide is drawn but will not move.
          onChanged: _haughNotRequired
              ? null
              : (v) {
                  if (v) setState(() => _haughNotRequired = true);
                },
        ),
        YesNoQuestion(
          label: 'No egg weighing inspection at this retailer',
          bold: true,
          helper: 'The sizing and grading block comes off the record and the '
              'inspection goes straight to signature. Answer No again to '
              'continue weighing.',
          value: _weighingNotRequired,
          onChanged: (v) {
            if (v) {
              unawaited(_confirmNoWeighing());
            } else {
              setState(() => _weighingNotRequired = false);
              unawaited(_saveDraft());
            }
          },
        ),
      ];

  /// The original's confirmation before it drops the weighing operation.
  Future<void> _confirmNoWeighing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm No Weighing'),
        content: const Text(
          'Please confirm that you are not doing an Egg Weighing operation '
          'at this retailer.',
          style: TextStyle(height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  'Confirm-No Inspection',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.25),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text(
                  'Return-Inspection Continues',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.25),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _weighingNotRequired = true);
    unawaited(_saveDraft());
  }

  /// Stands in for the signature block while the sample set is not finished.
  ///
  /// The original simply leaves the page short, which reads as a fault to
  /// anyone who has not been told the rule. The block is just as absent here;
  /// this says why.
  Widget _notYetSignable() => Container(
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.noticeBackground,
          border: Border.all(color: AppColors.noticeBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _samplingVisible
              ? 'Signatures and the rejection form open once the sample set '
                  'is complete. Still outstanding: $_readinessOutstanding.'
              : 'Signatures open once the labelling checklist is confirmed '
                  'complete and the sample set has been captured.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: AppColors.noticeForeground,
          ),
        ),
      );

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      );

  Widget _pad(List<Widget> children) => ListView(
        controller: _scroll,
        // The system navigation bar draws over the bottom of the page, and
        // the submit button is the last thing on it — without this the bar
        // sat on top of the button and swallowed the tap, dropping the
        // inspector out of the app instead of saving.
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: children,
      );

  List<Widget> _inspectionDetailFields() => [
        // Why the inspector is here and what kind of premises it is were
        // both answered at the door, and the visit carries them to every
        // inspection under it. Asking again on the form is the same question
        // a second time — and lets one record disagree with the visit it
        // belongs to.
        if (widget.visit == null) ...[
          _anchor('reason', _Drop<EggInspectionReason>(
            label: 'Reason for Inspection',
            value: _reason,
            items: _reasons,
            itemLabel: (r) => r.name,
            onChanged: (r) => setState(() => _reason = r),
            isRequired: true,
          )),
          _anchor('facilityType', _Drop<EggFacilityType>(
            label: 'Inspection Facility Type',
            value: _facilityType,
            items: _facilityTypes,
            itemLabel: (f) => f.name,
            onChanged: (f) => setState(() => _facilityType = f),
            isRequired: true,
          )),
        ],
        // The facility is captured once, at the top of the grouped
        // inspection, so it is not asked for again on every record inside
        // it. On a standalone inspection it is still asked here.
        if (widget.visit == null) ...[
          // Pick a known premises rather than retyping four fields per visit,
          // and so the same facility is spelled the same way on every record.
          // One field, not two: type the premises and pick it from the list, or
          // type a name that is not on the list and carry on.
          _anchor('facilityName', listenable: _facilityName,
              SearchPickerField<EggFacility>(
            label: 'Inspection Facility Name',
            controller: _facilityName,
            options: _facilities,
            optionLabel: (f) => f.name,
            optionSubtitle: (f) => [
              _facilityTypes
                      .where((t) => t.id == f.facilityTypeId)
                      .map((t) => t.name)
                      .firstOrNull ??
                  '',
              f.physicalAddress,
            ].where((part) => part.trim().isNotEmpty).join(' · '),
            onSelected: _onFacilitySelected,
            addNewLabel: 'Add new',
            onAddNew: _addFacility,
            isRequired: true,
            emptyHint: 'No facilities on this device yet. Sync from the Eggs '
                'menu to download them.',
          )),
        ],
      ];

  /// The producer named once on the visit: shown there, not asked again.
  bool get _producerFromVisit =>
      (widget.visit?.producer ?? '').trim().isNotEmpty;

  List<Widget> _declarationFields() => [
        if (!_producerFromVisit)
          _anchor('producer', SearchPickerField<EggSupplier>(
            label: 'Egg Producer/Supplier',
            controller: _producer,
            options: _suppliers,
            optionLabel: (x) => x.name,
            optionSubtitle: (x) => x.physicalAddress,
            onSelected: (x) => setState(() => _producer.text = x.name),
            isRequired: true,
            addNewLabel: 'Add new',
            onAddNew: _addSupplier,
            emptyHint: 'No suppliers on this device yet. Sync from the Eggs '
                'menu, or add one here.',
          )),
        // What the consignment claims to be. The deviation tolerances are
        // keyed on these, so they decide how strictly the sample is judged.
        _anchor('declaredSize', _Drop<EggSizeBand>(
          label: 'Egg Size',
          value: _declaredSize,
          items: _sizeOptions,
          itemLabel: (b) => b.name,
          // The original opens this picker only once a producer is chosen
          // (or a new one named) — verified live: before that, tapping it
          // does nothing.
          enabled: _producerChosen,
          disabledHint: 'Choose the Egg Producer/Supplier first',
          onChanged: (b) {
            // The original's size handler closes the tray picker and the
            // checklist-complete switch again: a different declared size
            // means the checklist below has to be reconsidered.
            _declaredSize = b;
            _declaredGrade = null;
            _traySize = null;
            // ResetForm() and ResetFormWithRepeatDetails() both put
            // IsWeighingCheckingRequired back to true and hide the retailer
            // switches. Without this the "no weighing" flag survived a change
            // of declared size, and the page was left with the sampling block
            // gone but the direction and signatures showing.
            _weighingNotRequired = false;
            _haughNotRequired = false;
            _recalculateAll();
            unawaited(_askAboutSeizureIfNeeded());
          },
          // The same note the grade picker carries, for the same reason: a
          // pack that states no size is a marking deviation, not a question
          // the inspector is expected to answer out of their own head.
          helper: 'Choose "Not indicated" if the pack shows no size.',
          isRequired: true,
        )),
        _Drop<EggGradeRef>(
          label: 'Egg Grade',
          value: _declaredGrade,
          items: _gradeOptions,
          itemLabel: (g) => g.name,
          // The original opens the grade picker only once a size is chosen,
          // and closes the tray picker again whenever the size changes.
          enabled: _declaredSize != null,
          disabledHint: 'Choose the Egg Size first',
          onChanged: (g) {
            _declaredGrade = g;
            _traySize = null;
            _weighingNotRequired = false;
            _haughNotRequired = false;
            _recalculateAll();
            unawaited(_askAboutSeizureIfNeeded());
          },
          // Answered as "Not indicated" where the pack carries no grade,
          // which is what the labelling checklist says on the same facts.
          // Demanding Grade 1/2/3 contradicted it — an inspector had to
          // invent a grade to get the inspection submitted.
          helper: 'Choose "Not indicated" if the pack shows no grade.',
        ),
        _anchor('traySize', _Drop<EggTraySize>(
          label: 'Tray Packaging Size',
          value: _traySize,
          items: _trayOptions,
          itemLabel: (t) => t.name,
          helper: 'Choose "Not indicated" if the pack shows no size.',
          // Follows the size, not the grade: the grade may be left blank,
          // and gating on it held the checklists and the label photograph
          // shut behind a field the pack does not carry.
          enabled: _declaredSize != null,
          disabledHint: 'Choose the Egg Size first',
          onChanged: (t) {
            setState(() => _traySize = t);
            unawaited(_askAboutSeizureIfNeeded());
          },
          isRequired: true,
        )),
      ];

  List<Widget> _sizingChecklistFields() => [
        _anchor('bestBefore', DateField(
          label: 'Best Before/Best Quality Before Date',
          value: _bestBefore,
          onChanged: (d) => setState(() => _bestBefore = d),
          // Past as well as future — the calendar's open default. The
          // original refused any date before tomorrow, which made expired
          // stock on a shelf impossible to record as what it is: the date on
          // the pack. Whether it has passed is a finding, not an input error
          // (Ethan, 2026-09-23).
          errorText: EggValidation.bestBefore(_bestBefore),
          // The original will not open the batch number until the date is
          // picked (datepickerBBDate_DateSelected). A date already passed is
          // accepted and said so: it is what the pack claims, and the fact
          // that it has passed is the finding.
          helperText: EggValidation.bestBeforeHasPassed(_bestBefore)
              ? 'This date has already passed - the pack is past its best '
                  'before. Record it as marked; the labelling checklist '
                  'carries the finding.'
              : 'Printed on the pack. The Batch Number opens once the '
                  'date is set.',
        )),
        _anchor('batch', _Text(
          label: 'Batch Number',
          isRequired: true,
          controller: _batch,
          focusNode: _batchFocus,
          // Opened by the date above; completing it opens the weighing
          // fields, exactly the original's entryBatchNumber_Completed →
          // SetEggQualityInspectBlock(true) chain.
          enabled: _bestBefore != null,
          helper: _bestBefore == null
              ? 'Pick the Best Before date above first.'
              : _batchEntryValid(_batch.text)
                  ? 'The number off the pack, or N/A if it has none.'
                  : 'A number, or N/A — nothing else counts as a batch.',
          onChanged: (_) => setState(() {}),
        )),
        YesNoQuestion(
          label: 'Is Pasteurised Eggs Present',
          value: _pasteurised,
          onChanged: (v) {
            _pasteurised = v;
            _recalculateAll();
          },
        ),
        // The original carries a "Is Haugh Readings NOT required" switch but
        // ships it hidden (IsVisible=False) — readings are always required,
        // and so they are here.
      ];

  /// Mean Haugh below 70 HU demands six further samples.
  /// How many eggs the inspection held when the mean Haugh unit was first
  /// seen below the threshold.
  ///
  /// Held in state rather than derived, so the "six more samples" requirement
  /// is a fixed target. Deriving it from the current count made every egg
  /// added push the target six further away, and the inspection could never
  /// be saved.
  int? _haughBaseline;

  int get _outstandingSamples => EggRules.additionalSamplesRequired(
        haughUnits: [for (final s in _samples) s.haugh],
        sampledCount: _samples.length,
        baselineCount: _haughBaseline,
      );

  // -------------------------------------------------------------------
  // The original's Egg Particulars is a single-record capture: one egg on
  // screen at a time, stepped with Next/Back/Goto, and every derived value
  // — size, grade, Haugh unit, auto deviations, the results table —
  // recomputed in the background as each reading lands
  // (DoFullGradeCheckandUpdate). Nothing per-egg is ever displayed beyond
  // the number, the two readings, the Haugh unit and the ticks.
  // -------------------------------------------------------------------

  /// `CurrentEggSampleNumber` — which egg the fields show, 1-based.
  int _currentEggNumber = 1;

  /// The one visible pair of entry fields, rebound on every navigation the
  /// way `UpdateNewEggQualitySampleGroup` reloads or clears the original's.
  final _weightEntry = TextEditingController();
  final _haughEntry = TextEditingController();

  /// Anchors the Egg # field so the bottom-of-form "Add egg n" button can
  /// scroll the capture fields back into view after jumping to a new egg.
  final _eggNumberFieldKey = GlobalKey();

  /// The form's ListView builds lazily, so from the bottom of the page the
  /// Egg # field is unmounted and its key has no context to scroll to.
  /// This controller lets _addNextEgg step upward until it mounts.
  final _scroll = ScrollController();

  _Sample? get _currentEgg =>
      _samples.where((x) => x.number == _currentEggNumber).firstOrNull;

  int get _weighedCount => _samples.where((x) => (x.massG ?? 0) > 0).length;
  int get _haughCount => _samples.where((x) => (x.haugh ?? 0) > 0).length;

  static bool _batchEntryValid(String text) => BatchNumber.valid(text);

  /// What goes on the record: the number as typed, or N/A.
  String get _batchForRecord => BatchNumber.forRecord(_batch.text);

  /// Leaving the box empty fills in N/A rather than filing a blank: a blank
  /// says nothing about whether the pack carried a batch code or the
  /// inspector never looked (FSA, 2026-09-08).
  void _normaliseBatch() {
    if (_batchFocus.hasFocus) return;
    final tidied = BatchNumber.tidy(_batch.text);
    if (tidied == _batch.text) return;
    setState(() => _batch.text = tidied);
  }

  /// Whether the weighing fields are open: the original enables them from
  /// entryBatchNumber_Completed, once the best-before date has opened the
  /// batch number and it has been filled in — with a number, or N/A.
  bool get _samplingUnlocked =>
      _bestBefore != null && _batchEntryValid(_batch.text);

  /// A record exists only once a valid weight lands on it — the original's
  /// `IsPopulated`.
  _Sample _ensureCurrentEgg() {
    final existing = _currentEgg;
    if (existing != null) return existing;
    final fresh = _Sample(_currentEggNumber);
    _samples.add(fresh);
    return fresh;
  }

  /// The original's DisplayAlert: title, message, one "Ok".
  Future<void> _legacyAlert(String title, String message) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message, style: const TextStyle(height: 1.4)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Ok'),
            ),
          ],
        ),
      );

  /// The weight lands the moment the typed text is a weight — no Done key,
  /// no dialog. Out-of-range and half-typed values simply do not store, and
  /// clearing the field takes the reading off the egg again.
  void _weightTyped(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value != null && value >= 0.1 && value <= 999.9) {
      final egg = _ensureCurrentEgg();
      egg.massG = value;
      egg.massController.text = raw.trim();
      _recalculate(egg);
      unawaited(_saveDraft());
      return;
    }
    final egg = _currentEgg;
    if (egg != null && egg.massG != null) {
      egg.massG = null;
      egg.massController.clear();
      _recalculate(egg);
      unawaited(_saveDraft());
    } else {
      // Nothing stored yet; still repaint so the inline message tracks the
      // text.
      setState(() {});
    }
  }

  /// The Haugh reading, live like the weight. The unit recomputes on every
  /// keystroke and shows in the read-only row underneath.
  void _haughTyped(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    final egg = _currentEgg;
    if (value != null && value > 0 && egg != null && (egg.massG ?? 0) > 0) {
      egg.albumenHeightMm = value;
      egg.albumenController.text = raw.trim();
      _recalculate(egg);
      unawaited(_saveDraft());
      return;
    }
    if (egg != null && egg.albumenHeightMm != null) {
      egg.albumenHeightMm = null;
      egg.albumenController.clear();
      _recalculate(egg);
      unawaited(_saveDraft());
    } else {
      setState(() {});
    }
  }

  /// What the weight field has to say about its text, inline — there is no
  /// submit moment to hang a dialog on any more.
  String? get _weightInlineError {
    final raw = _weightEntry.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null) return null; // still typing
    if (value > 999.9) {
      return "Entered weight is too high. Please recheck the scale's reading.";
    }
    if (value < 0.1) return 'A weight of zero or less is not allowed.';
    return null;
  }

  String? get _haughInlineHint {
    if (_haughEntry.text.trim().isEmpty) return null;
    final egg = _currentEgg;
    if (egg == null || (egg.massG ?? 0) <= 0) {
      return 'Enter the weight first — the Haugh unit needs it.';
    }
    final value = double.tryParse(_haughEntry.text.trim().replaceAll(',', '.'));
    if (value != null && value <= 0) {
      return 'The Haugh meter value cannot be 0 or less.';
    }
    return null;
  }

  /// The deviation rows exactly as the original's screen lists them.
  ///
  /// The original pairs 25 fixed XAML labels (lblPack1..25) with the
  /// deviation matrix its manager builds from the database — every category
  /// except Egg Size, minus the four Haugh/pasteurised rows the analysis
  /// ticks itself. The label text is cleaner than the stored description
  /// ("do not result in leakage" on screen, a typo in the record), so, as
  /// with the labelling checklists, the screen wording and the record
  /// wording are both kept: the label shows, the id stores.
  static const _deviationScreenLabels = [
    'Soundness of Egg - Eggs with cracks that result in leakage',
    'Soundness of Egg - Eggs with cracks that do not result in leakage',
    'Cleaniness of Shell - Eggs with nesting material/foreign matter',
    'Discolouration/Stains - Eggs with discolouration/stains on shell',
    'Shape of Shell - Irregular shape of shell',
    'Blood Spot - Light intensity, ≤ 1mm diameter',
    'Blood Spot - Strong intensity, ≤ 2mm diameter',
    'Blood Rings - Light intensity, ≤ 1mm diameter',
    'Blood Rings - Strong intensity, ≤ 2mm diameter',
    'Meat Spots in Egg - Light intensity, ≤ 1mm diameter',
    'Meat Spots in Egg - Strong intensity, ≤ 2mm diameter',
    'Moulds - Eggs with mould adhering to shells',
    'Poultry Feces - Eggs with faeces',
    'Yolk - Defects in normal position',
    'Yolk - Defects in yolk not spotted, flat or englared',
    'Yolk - Defects in yolk colour',
    'Air Cells - Maximum Depth 6/9mm - Eggs exceed permissable maximum '
        'depth',
    'Air Cells - Not Move> 6/12mm in any direction when tilted from the '
        'Vertical - Eggs exceed permissable maximum depth',
    'Air Cells - No swimmers',
    'Air Cells - No bubbly air cells - eggs with bubbly air cells',
    'Packaged Eggs - Boards end down/point ends up',
    'Egg White - Clear',
    'Atypical / Unacceptable Odours',
    'Texture of Shell - Strong and Smooth',
    'Decay/Germ Development',
  ];

  /// The screen lays the last four out in a different order than they are
  /// numbered — the XAML's grid rows put Texture (24) before Egg White (22)
  /// and Decay (25) before Atypical (23). Indices into the matrix/labels.
  static const _deviationScreenOrder = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    23,
    21,
    24,
    22,
  ];

  /// The original's deviation matrix: every deviation outside the Egg Size
  /// category, minus the rows the analysis manages, in database order.
  /// Position n pairs with `_deviationScreenLabels[n]`.
  List<DeviationRef> get _deviationMatrix {
    final eggSizeCategory =
        _categories.where((c) => c.name == 'Egg Size').map((c) => c.id).toSet();
    final auto = EggRules.autoManagedDeviationIds(_deviationRefs);
    return [
      for (final d in _deviationRefs)
        if (!eggSizeCategory.contains(d.categoryId) && !auto.contains(d.id)) d,
    ];
  }

  /// The highest egg number holding anything so far.
  int get _highestEggNumber =>
      _samples.fold(0, (high, x) => x.number > high ? x.number : high);

  /// Tap the egg number and pick from the eggs opened so far — the weighed
  /// ones and the fresh one on screen — to move between them and edit any.
  /// New eggs are added only through the "Add egg" button under the sampled
  /// counters. No guards: an egg left unweighed stays unweighed and the
  /// counters keep the score.
  Future<void> _pickEggNumber() async {
    final highest = _highestEggNumber;
    final furthest = _currentEggNumber > highest ? _currentEggNumber : highest;
    final options = [for (var n = 1; n <= furthest; n++) n];
    // Opened and moved off with no weight — not the egg on screen now.
    bool skipped(int n) =>
        n <= highest && !_eggWeighed(n) && n != _currentEggNumber;
    final picked = await showPickerSheet<int>(
      context: context,
      title: 'Egg #',
      items: options,
      itemLabel: (n) => n > highest
          ? 'Egg $n (new)'
          : skipped(n)
              ? 'Egg $n of $highest — skipped, no weight'
              : 'Egg $n of $highest',
      // A tick on every egg captured, a cross on one skipped with no weight,
      // so a gap in sixty can be found at a glance instead of by counting.
      itemLeading: (n) => _eggWeighed(n)
          ? const Icon(Icons.check_circle,
              color: AppColors.brandPrimary, size: 22)
          : skipped(n)
              ? const Icon(Icons.cancel, color: AppColors.brandRed, size: 22)
              : Icon(Icons.radio_button_unchecked,
                  color: AppColors.border, size: 22),
      selected: _currentEggNumber,
    );
    if (picked == null || !mounted) return;
    _showEgg(picked);
  }

  /// `UpdateNewEggQualitySampleGroup` — load the record under the new
  /// number into the fields, or clear them when none exists yet.
  void _loadCurrentEggIntoEntries() {
    final egg = _currentEgg;
    if (egg != null && (egg.massG ?? 0) > 0) {
      _weightEntry.text = egg.massController.text;
      // The original skips a stored "0" so the field reads as empty.
      final haughText = egg.albumenController.text;
      _haughEntry.text = haughText == '0' ? '' : haughText;
    } else {
      _weightEntry.clear();
      _haughEntry.clear();
    }
  }

  void _showEgg(int number) => setState(() {
        _currentEggNumber = number;
        _loadCurrentEggIntoEntries();
      });

  /// Whether egg [number] carries a weight — what the sample count counts.
  bool _eggWeighed(int number) =>
      _samples.any((x) => x.number == number && (x.massG ?? 0) > 0);

  /// The lowest egg number still without a weight, or null once all
  /// [EggValidation.maxSamples] are weighed.
  int? get _firstUnweighedEgg {
    for (var n = 1; n <= EggValidation.maxSamples; n++) {
      if (!_eggWeighed(n)) return n;
    }
    return null;
  }

  /// Egg numbers below the highest one opened that were left without a
  /// weight — skipped with NEXT before a reading was typed.
  List<int> get _skippedEggs => [
        for (var n = 1; n < _highestEggNumber; n++)
          if (!_eggWeighed(n) && n != _currentEggNumber) n,
      ];

  /// The number NEXT and "Add egg" offer: the next egg after this one still
  /// without a weight, so adding egg 2 moves the offer on to egg 3.
  ///
  /// Past the end it comes back round to any egg skipped on the way. It used
  /// to be one past the highest egg, so an egg NEXT moved off before its
  /// weight was typed was never offered again: the button read "ALL 60 EGGS
  /// CAPTURED" over 59 weighed eggs and the inspection could not be signed
  /// off, with nothing on screen saying which egg was short.
  ///
  /// Past [EggValidation.maxSamples] when there is nowhere left to go.
  int get _nextEggNumber {
    for (var n = _currentEggNumber + 1; n <= EggValidation.maxSamples; n++) {
      if (!_eggWeighed(n)) return n;
    }
    final skipped = _firstUnweighedEgg;
    if (skipped != null && skipped != _currentEggNumber) return skipped;
    return EggValidation.maxSamples + 1;
  }

  /// The bottom-of-form shortcut: jump to the next fresh egg and scroll the
  /// capture fields back into view so the weight can be typed right away.
  void _addNextEgg() {
    _showEgg(_nextEggNumber);
    unawaited(_revealEggEntry());
  }

  /// Moves to the next egg from the capture fields themselves.
  ///
  /// The reading is already saved as it is typed, so there is nothing to
  /// confirm: this only advances the number and clears the two fields, and
  /// leaves the view where it is — the inspector's hands stay on the scale
  /// and the keypad.
  void _nextEgg() {
    if (_nextEggNumber > EggValidation.maxSamples) return;
    _showEgg(_nextEggNumber);
  }

  /// Bring the Egg # field on screen. The lazy ListView keeps it unmounted
  /// while the user is far below it, so its key has no context yet — step
  /// the scroll upward a screen at a time until it mounts, then land on it.
  Future<void> _revealEggEntry() async {
    for (var i = 0; i < 40; i++) {
      if (!mounted) return;
      final anchor = _eggNumberFieldKey.currentContext;
      if (anchor != null && anchor.mounted) {
        await Scrollable.ensureVisible(
          anchor,
          duration: const Duration(milliseconds: 250),
          alignment: 0.05,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels <= position.minScrollExtent) return;
      await _scroll.animateTo(
        (position.pixels - 700)
            .clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// What the read-only Haugh row shows. "No value" before anything exists;
  /// the original's reload path writes it back as "No Value" on a weighed
  /// egg without a reading, capital and all.
  String get _haughUnitDisplay {
    final egg = _currentEgg;
    if (egg?.haugh != null) return egg!.haugh!.round().toString();
    // The XAML placeholder is "No value"; every reload writes "No Value".
    // Only the pristine first egg has never been through a reload.
    final pristine =
        _currentEggNumber == 1 && _samples.isEmpty && (egg?.massG ?? 0) <= 0;
    return pristine ? 'No value' : 'No Value';
  }

  /// `UpdateOverallGradeResultsTable` — "Deviations | Count", one row per
  /// deviation found across the set, the count on green while the tolerance
  /// for the declared size and grade permits it, red once it does not.
  Widget _overallGradeResults() {
    final counts = <int, int>{};
    for (final x in _samples) {
      for (final id in x.deviationIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final labelById = {
      for (final category in _categories)
        for (final d
            in _deviationsByCategory[category.id] ?? const <EggDeviation>[])
          d.id: '${category.name} - ${d.description}',
    };

    const cellPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

    // One definition, because the count column's width is measured from it
    // below and the two must not drift apart.
    TextStyle cellTextStyle({bool bold = false, Color? foreground}) =>
        TextStyle(
          fontSize: 12.5,
          height: 1.3,
          color: foreground ?? AppColors.ink,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        );

    Widget cell(String text,
            {Color? background,
            Color? foreground,
            bool center = false,
            bool bold = false,
            bool singleLine = false}) =>
        Container(
          color: background,
          alignment: center ? Alignment.center : Alignment.centerLeft,
          padding: cellPadding,
          child: Text(
            text,
            textAlign: center ? TextAlign.center : TextAlign.start,
            // Deviation descriptions are long and must wrap; the count header
            // is sized to fit and must never split across two lines.
            maxLines: singleLine ? 1 : null,
            softWrap: !singleLine,
            style: cellTextStyle(bold: bold, foreground: foreground),
          ),
        );

    // The original lays the table out as a grid: the deviation text spans
    // the wide columns, the count keeps one narrow column of its own, and
    // every cell stretches to the row's full height so the green/red block
    // fills its cell rather than floating beside a taller wrapped label.
    // The dressing, though, is this app's: a bordered rounded card, the
    // teal accent on the header, the brand red where a count breaks the
    // tolerance.
    //
    // That narrow column is measured rather than fixed. "Count" is the widest
    // thing it ever holds — a tally does not reach three digits on a sample
    // set this size — and a hard-coded 62 was only just wide enough at the
    // default font: on a tablet with the system text size turned up the
    // header wrapped to "Coun / t". Measuring the header at the scale the
    // device is actually using keeps it on one line at any accessibility
    // setting, and the column stays no wider than it has to be.
    // Measured against the style the cell will actually resolve to, not the
    // bare TextStyle. The app is set in Poppins, which is wider than the
    // engine's default face, and `cellTextStyle` names no family — so
    // measuring it alone came out short and the header still wrapped, just
    // one letter later.
    final countHeaderStyle =
        DefaultTextStyle.of(context).style.merge(cellTextStyle(bold: true));
    final countWidth = cellPadding.horizontal +
        (TextPainter(
          text: TextSpan(text: '00 of 00 allowed', style: countHeaderStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout())
            .width
            .ceilToDouble() +
        // Slack for subpixel rounding and any hinting difference between
        // measuring and painting.
        4;
    Widget tableRow(Widget label, Widget count) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: label),
              SizedBox(width: countWidth, child: count),
            ],
          ),
        );

    final rows = <Widget>[];
    for (final entry in counts.entries) {
      if (rows.isNotEmpty) {
        rows.add(Container(height: 1, color: AppColors.border));
      }
      rows.add(tableRow(
        cell(
          labelById[entry.key] ??
              _deviationRefs
                  .where((d) => d.id == entry.key)
                  .map((d) => d.description)
                  .firstOrNull ??
              'Deviation ${entry.key}',
        ),
        // The band is named beside the tally. A green "2" on its own read
        // as nothing having happened; "2 of 4 allowed" says the deviation
        // was counted and is inside what the Agency permits at this size
        // and grade, and red says it is not (Ethan, 2026-09-23).
        cell(
          EggRules.toleranceLabel(
            count: entry.value,
            deviationId: entry.key,
            sizeId: _declaredSize?.id ?? -1,
            gradeId: _declaredGrade?.id ?? -1,
            tolerances: _tolerances,
            sampleSize: EggValidation.maxSamples,
          ),
          center: true,
          bold: true,
          singleLine: true,
          foreground: Colors.white,
          background: EggRules.isDeviationPermissible(
            deviationId: entry.key,
            count: entry.value,
            sizeId: _declaredSize?.id ?? -1,
            gradeId: _declaredGrade?.id ?? -1,
            tolerances: _tolerances,
          )
              ? const Color(0xFF2E7D32)
              : AppColors.brandRed,
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tableRow(
              cell('Deviations',
                  background: AppColors.brandTeal,
                  foreground: Colors.white,
                  bold: true),
              cell('Count',
                  background: AppColors.brandTeal,
                  foreground: Colors.white,
                  center: true,
                  bold: true,
                  singleLine: true),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  List<Widget> _samplingFields() => [
        if (_outstandingSamples > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.noticeBackground,
              border: Border.all(color: AppColors.noticeBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.science_outlined,
                    size: 20, color: AppColors.noticeForeground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mean Haugh value is below '
                    '${EggRules.haughAdditionalSampleThreshold.toStringAsFixed(0)} HU. '
                    'A further ${EggRules.haughAdditionalSampleCount} samples are '
                    'required — $_outstandingSamples still outstanding.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppColors.noticeForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Egg # — tap it to jump to any egg in the sample of 60.
        LabelledField(
          key: _eggNumberFieldKey,
          label: 'Egg #',
          child: InkWell(
            onTap: _samplingUnlocked ? _pickEggNumber : null,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              isEmpty: false,
              decoration: const InputDecoration(
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                _currentEggNumber <= _highestEggNumber
                    ? 'Egg $_currentEggNumber of $_highestEggNumber'
                    : 'Egg $_currentEggNumber (new)',
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        _anchor('eggEntry', framed: true, listenable: _weightEntry,
            LabelledField(
          label: 'Egg Weight (g)',
          child: TextField(
            controller: _weightEntry,
            enabled: _samplingUnlocked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 15.5),
            // Saved as typed — no Done key, no dialogs.
            onChanged: _weightTyped,
            decoration: InputDecoration(
              errorText: _weightInlineError,
              errorMaxLines: 2,
            ),
          ),
        )),
        LabelledField(
          label: 'Haugh Meter Value (mm)',
          child: TextField(
            controller: _haughEntry,
            enabled: _samplingUnlocked && !_haughNotRequired,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 15.5),
            onChanged: _haughTyped,
            decoration: InputDecoration(
              helperText: _haughInlineHint,
              helperMaxLines: 2,
            ),
          ),
        ),
        LabelledField(
          // The trailing space is the original's.
          label: 'Haugh Unit Value ',
          child: InputDecorator(
            isEmpty: false,
            decoration: const InputDecoration(),
            child: Text(
              _haughUnitDisplay,
              style: TextStyle(
                fontSize: 15.5,
                color: _currentEgg?.haugh != null
                    ? AppColors.ink
                    : AppColors.muted,
              ),
            ),
          ),
        ),
        // Straight on to the next egg, from where the reading was just
        // typed. Sixty eggs is sixty trips down to the egg picker and back
        // otherwise, and losing your place in that is easy — E-click has a
        // Next for the same reason.
        if (_samplingUnlocked)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: _nextEggNumber <= EggValidation.maxSamples
                    ? _nextEgg
                    : null,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(
                  _nextEggNumber <= EggValidation.maxSamples
                      ? 'NEXT — EGG $_nextEggNumber'
                      : _firstUnweighedEgg == null
                          ? 'ALL ${EggValidation.maxSamples} EGGS CAPTURED'
                          : 'EGG $_currentEggNumber STILL NEEDS A WEIGHT',
                ),
              ),
            ),
          ),
        // The current egg's deviations. The auto-managed rows never
        // appear — the analysis sets those itself, in the background.
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Deviation',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'This egg',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted),
              ),
            ],
          ),
        ),
        // One flat list, worded and ordered exactly as the original's
        // screen — no category headings.
        for (final index in _deviationScreenOrder)
          if (index < _deviationMatrix.length)
            Builder(builder: (context) {
              final d = _deviationMatrix[index];
              final label = index < _deviationScreenLabels.length
                  ? _deviationScreenLabels[index]
                  : d.description;
              final found = _currentEgg?.deviationIds.contains(d.id) ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ComplianceSlider(
                      compliant: !found,
                      onChanged: (isCompliant) {
                        final egg = _currentEgg;
                        if (egg == null || (egg.massG ?? 0) <= 0) {
                          // DeviationCheckBoxHander's own guard, verbatim.
                          unawaited(_legacyAlert(
                              'No Weight Entered',
                              'A weight reading must be entered for this '
                                  'sample, before any egg deviations can be '
                                  'noted.'));
                          return;
                        }
                        if (isCompliant) {
                          egg.deviationIds.remove(d.id);
                        } else {
                          egg.deviationIds.add(d.id);
                        }
                        _recalculate(egg);
                      },
                    ),
                  ],
                ),
              );
            }),
        Row(
          children: [
            Expanded(
              child: Text(
                '# Eggs Sampled: $_weighedCount',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Text(
                '# Haugh Readings Sampled: $_haughCount',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        // Reaching the bottom of the checklist with another egg to do —
        // jump straight to the next fresh egg without scrolling back up.
        if (_samplingUnlocked && _nextEggNumber <= EggValidation.maxSamples)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _addNextEgg,
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add egg $_nextEggNumber'),
              ),
            ),
          ),
        _overallGradeResults(),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _samples.isEmpty ? null : _clearSamples,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Clear Samples'),
          ),
        ),
      ];

  /// The original's "Clear Samples" — wipes every captured egg after a
  /// confirmation, since there is no undo.
  Future<void> _clearSamples() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Samples'),
        content: const Text(
          'Remove every captured egg from this inspection?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final sample in _samples) {
      sample.dispose();
    }
    _samples.clear();
    _currentEggNumber = 1;
    _weightEntry.clear();
    _haughEntry.clear();
    _consignmentGrade = null;
    _updateHaughBaseline();
    setState(() {});
  }

  List<Widget> _labellingFields() => [
        Text(
          'Every requirement starts Compliant. Mark only the ones the '
          'consignment fails.',
          style: TextStyle(color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _reqSection('Marking/Labelling - Packaging', _labelPack,
            letteringMinsMm: _labelLetteringMinsMm),
        YesNoQuestion(
          label: 'Is the outer labelling available for inspection',
          bold: true,
          value: _outerAvailable,
          onChanged: (v) => setState(() {
            _outerAvailable = v;
            if (v) {
              // Compliant, like every other row on this form. It used to
              // open with all of them already marked as deviations, so an
              // inspector who said the outer labelling was available and
              // moved on served a rejection for the whole outer block
              // without answering a single row.
              _failedRequirements
                  .removeAll([for (final r in _labelOuter) r.id]);
            } else {
              // A hidden checklist cannot carry failures — the original's
              // boxes revert to their initial all-pass state.
              _failedRequirements
                  .removeAll([for (final r in _labelOuter) r.id]);
            }
          }),
        ),
        if (_outerAvailable)
          _reqSection('Marking/Labelling - Outer Packaging', _labelOuter,
              letteringMinsMm: _labelLetteringMinsMm),
        _reqSection(
            'Packing Requirements - Inner/Outer Containers [Reg 6]', _packing),
        // The original activates this list from
        // CheckForRestrictedParticularsActivation — only a deviation on the
        // tenth labelling row puts it on the page, and until something is
        // listed the sizing and grading block stays off.
        if (_restrictedParticularsRequired) ...[
          Divider(height: 26, color: AppColors.border),
          Text(
            'RESTRICTED PARTICULARS PRESENT ON THE LABEL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.muted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              'Optional — add any restricted particulars that appear on the '
              'label. A label with none is normal. One the list does not '
              'have can be typed in.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
          ),
          // The same dropdown every other picker on the form uses; the
          // original works with a picker, an Add button and a Clear beside
          // the list, instead of two dozen checkbox rows.
          RestrictedParticularsPicker<EggRestrictedParticular>(
            options: _particulars,
            optionId: (p) => p.id,
            optionLabel: (p) => p.keyword,
            selected: _selectedParticulars,
            typed: _typedParticulars,
            shared: _sharedParticulars,
            onChanged: () {
              if (!mounted) return;
              setState(() {});
              unawaited(_saveDraft());
            },
            // A duplicate gets the original's own refusal, word for word.
            onDuplicate: () => _legacyAlert('Already added',
                'That restricted particular is already on the list.'),
          ),
        ],
        Divider(height: 26, color: AppColors.border),
        Text(
          'Selected Rejection for Follow up',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.muted,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text('Not applicable', style: TextStyle(fontSize: 13.5)),
        ),
      ];

  /// Whether the marking/labelling block is open at all — the original
  /// enables it from PickerTraySize_SelectedIndexChanged, so nothing in it
  /// can be touched until the tray packaging size is chosen.
  bool get _checklistUnlocked => _traySize != null;

  // ------------------------------------------------- what the page shows
  //
  // The original does not grey the blocks below out and wait — it keeps them
  // off the page and puts each one back when the inspection has earned it.
  // Every one of them starts life as IsVisible="False" in the XAML.

  /// A deviation on the tenth row of the packaging checklist — or of the
  /// outer checklist, while outer packaging is being inspected — obliges the
  /// inspector to list which restricted particulars are on the label.
  ///
  /// The original reads `!checkbox10a.IsChecked`: its boxes tick to mean "no
  /// deviation", and so do these — what the record stores is still the set of
  /// failures, which is what `_failedRequirements` holds.
  bool get _restrictedParticularsRequired {
    bool deviated(List<EggRequirement> list) =>
        list.length >= 10 && _failedRequirements.contains(list[9].id);
    return deviated(_labelPack) || (_outerAvailable && deviated(_labelOuter));
  }

  /// `CheckForQualityChecklistBlockActivation`: the sizing and grading block
  /// is not on the page until the labelling checklist is confirmed complete
  /// — and it comes back off it if the inspector records that no weighing
  /// was possible.
  ///
  /// The original also held this behind the restricted-particulars list, but
  /// the FSA dropped that obligation (2026-08-21): many labels carry no
  /// restricted particulars at all, so the list is optional.
  /// The pack declares no grade at all.
  ///
  /// A grade designation is a marking requirement, so a consignment that
  /// carries none is rejected on marking (Reg. 10). It is also nothing to
  /// weigh against: the sizing and grading block measures eggs against the
  /// grade the pack claims, and there is no claim to measure. So the block
  /// comes off and the inspection goes to the rejection instead.
  bool get _noGradeIndicated => _declaredGrade?.id == _gradeNotIndicated.id;

  /// The same, for the size: a consignment that claims no size is rejected
  /// on marking and has no declared band to be weighed against.
  bool get _noSizeIndicated => _declaredSize?.id == _sizeNotIndicated.id;

  bool get _noTrayIndicated => _traySize?.id == _trayNotIndicated.id;

  /// Why this consignment must be seized, per Annexure D — empty when it
  /// need not be.
  List<String> get _seizureReasons => EggRules.seizureReasons(
        sizeNotIndicated: _noSizeIndicated,
        gradeNotIndicated: _noGradeIndicated,
        trayNotIndicated: _noTrayIndicated,
        eggsExpressionAbsent: _eggsExpressionAbsent,
        bestBeforeAbsent: _bestBeforeAbsent,
        looseQuantityFailed: _failedRows.any(EggRules.isLooseQuantityRow),
        qualityStandardFailed: _qualityStandardFailed,
      );

  /// The requirement rows the inspector has marked as failing.
  List<EggRequirement> get _failedRows => [
        for (final r in [..._labelPack, ..._labelOuter, ..._packing])
          if (_failedRequirements.contains(r.id)) r,
      ];

  /// Whether the weighed sample fails the size or grade standard the eggs
  /// are sold as — Annexure D seizes on that.
  bool get _qualityStandardFailed =>
      _samples.isNotEmpty && _directionRequired().quality;

  /// The inspector's answers when the "Eggs" row or the best-before row is
  /// unticked: Annexure D seizes on an omission and gives 30 days for an
  /// indication that is shown but wrong.
  bool _eggsExpressionAbsent = false;
  bool _bestBeforeAbsent = false;

  /// Asks whether an indication is missing altogether or merely wrong, then
  /// puts the seizure question if the answer raises it.
  Future<void> _askIndicatedAtAll(
      String question, ValueChanged<bool> apply) async {
    final absent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Not indicated?'),
        content: Text(question, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Shown, but not correct'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Not indicated at all'),
          ),
        ],
      ),
    );
    if (absent == null || !mounted) return;
    setState(() => apply(absent));
    await _askAboutSeizureIfNeeded();
    unawaited(_saveDraft());
  }

  /// Puts the seizure question, once, the moment the findings raise it.
  ///
  /// Asked as soon as the inspector says an indication is missing, not held
  /// back to the sign-off: the consignment is in front of them now, and the
  /// SOP's choice is between seizing it and carrying on.
  Future<void> _askAboutSeizureIfNeeded() async {
    final reasons = _seizureReasons;
    if (reasons.isEmpty || _seizureAsked || !mounted) return;
    _seizureAsked = true;
    final answer = await askAboutSeizure(
      context,
      reason: reasons.join('\n'),
    );
    if (answer == null || !mounted) {
      // Dismissed without an answer: ask again next time it changes.
      _seizureAsked = false;
      return;
    }
    setState(() => _seizureDecision = answer);
    // Seized: the Annexure E sheet is drawn up here, on the premises.
    if (answer == SeizureDecision.seize) {
      await recordSeizure(
        context,
        database: widget.repository.database,
        draft: SeizureDraft(
          recordUuid: _uuid,
          recordKind: 'egg',
          visitUuid: widget.visit?.uuid ?? '',
          inspectorUsername: widget.inspectorName,
          natureOfDeviation:
              'Seizure under FSA-SOP-APS-001 Annexure D: ${reasons.join('; ')}',
          regulation: 'R.541 of 30 June 2017',
          clientName: _facilityName.text,
          clientAddress: _facilityAddress.text,
          clientTelephone: _facilityPhone.text,
          clientEmail: _clientEmail.text,
          inspectionPoint: _facilityType?.name ?? '',
          productName: 'Eggs',
          receiverName: _managerName.text,
        ),
      );
      if (!mounted) return;
    }
    await _saveDraft();
  }

  /// Whether the question has been put on this visit to the form, so a
  /// second unticked row does not put it again.
  bool _seizureAsked = false;
  SeizureDecision? _seizureDecision;

  bool get _samplingVisible =>
      _checklistUnlocked &&
      !_weighingNotRequired &&
      !_noGradeIndicated &&
      !_noSizeIndicated;

  /// Eggs cannot be broken open on a retailer's premises, so the original
  /// offers the two "not required" switches there and nowhere else.
  bool get _isRetailer {
    final name = _facilityType?.name.toLowerCase() ?? '';
    return name.contains('retailer');
  }

  /// The original's `IsQualitySetReadyToSave`: the full sample set is
  /// weighed, the Haugh readings are in, and the egg-numbering photograph of
  /// the tray has been taken — or no weighing was required in the first
  /// place, in which case the original simulates a complete set.
  ///
  /// Nothing below the sampling block appears before this is true: no
  /// direction form, no signatures, and the record cannot be submitted.
  bool get _qualitySetReadyToSave {
    if (_weighingNotRequired) return true;
    // Nothing to weigh without a declared grade, so the set is as complete
    // as it is ever going to be.
    if (_noGradeIndicated) return true;
    if (!_samplingVisible) return false;
    final weighed = _samples.where((s) => (s.massG ?? 0) > 0).length;
    final haughReadings = _samples.where((s) => (s.haugh ?? 0) > 0).length;
    return weighed >= EggValidation.maxSamples &&
        (_haughNotRequired ||
            haughReadings >= EggRules.haughReadingsRequired) &&
        _photoCount('numbering') >= _minPhotos;
  }

  /// What is still owed before the inspection can be signed off, phrased as
  /// the original's own counters. Shown in place of the signature block so
  /// the inspector can see why it has not appeared rather than assuming the
  /// page is broken.
  String get _readinessOutstanding {
    final weighed = _samples.where((s) => (s.massG ?? 0) > 0).length;
    final haughReadings = _samples.where((s) => (s.haugh ?? 0) > 0).length;
    return [
      if (weighed < EggValidation.maxSamples)
        '$weighed of ${EggValidation.maxSamples} eggs weighed'
            '${_skippedEggs.isEmpty ? '' : ' (no weight on egg ${_skippedEggs.join(', ')})'}',
      if (!_haughNotRequired && haughReadings < EggRules.haughReadingsRequired)
        '$haughReadings of ${EggRules.haughReadingsRequired} Haugh readings',
      if (!_photos.any((p) => p.kind == 'numbering'))
        'the egg numbering photograph',
    ].join(', ');
  }

  void _producerChanged() {
    if (mounted) setState(() {});
  }

  /// Whether a producer has been settled, which is what opens the Egg
  /// Size picker in the original.
  bool get _producerChosen => _producer.text.trim().isNotEmpty;

  /// The original's confirmation when completing the checklist; proceeding
  /// locks the checklist for the rest of the capture. Before the dialog it
  /// applies the same two refusals the handset shows, in the same order,
  /// and after Proceed the same grade/size question.
  /// The original's follow-up when the size/grade designation row carries a
  /// deviation: without a size and grade on the label there may be nothing
  /// to weigh the eggs against. Asked as the deviation is recorded, since
  /// there is no longer a "checklist complete" step to hang it on.
  Future<void> _askGradeSizeWeighing() async {
    final continueWeighing = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No grade/No size'),
        content: const Text(
          'A Grade/Size label non-conformance or deviation was noted. '
          'Can you continue to perform the egg weighing inspection, i.e. '
          'there is no missing/incomplete GRADE and/or SIZE present on '
          'the labelling?',
          style: TextStyle(fontSize: 14.5, height: 1.4),
        ),
        // Two long answers side by side wrap into a mess; stacked
        // full-width they each read as one line of intent.
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  'YES-Continue to do Egg Weighing',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.25),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text(
                  'NO-Stop inspection and Proceed to signatures',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.25),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted) return;
    // The NO path is the original's l.3296: the sizing and grading block
    // comes off the page and the inspection goes straight to signatures —
    // the same machinery as no weighing required.
    setState(() => _weighingNotRequired = continueWeighing != true);
    unawaited(_saveDraft());
  }

  /// The original's btnClearEntireForm: one confirmation, then the whole
  /// form back to its opening state — same inspection, clean slate.
  Future<void> _clearEntireForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Form'),
        // The trailing space is the original's.
        content: const Text('Do you want to clear/reset the form? '),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Photographs first — they live in the database the moment they are
    // taken, so clearing the form must take the rows with it.
    for (final shot in _photos.toList()) {
      await _removePhoto(shot);
    }
    if (!mounted) return;

    setState(() {
      _reason = null;
      _facilityType = null;
      _facilityName.clear();
      _facilityAddress.clear();
      _facilityPhone.clear();
      _producer.clear();
      _clientName.clear();
      _clientAddress.clear();
      _contactPerson.clear();
      _contactNumber.clear();
      _clientEmail.clear();
      _representative.clear();
      _declaredSize = null;
      _declaredGrade = null;
      _traySize = null;
      _failedRequirements.clear();
      _selectedParticulars.clear();
      _typedParticulars.clear();
      _outerAvailable = false;
      _weighingNotRequired = false;
      _haughNotRequired = false;
      _qualityPhotoNoticeShown = false;
      _bestBefore = null;
      _batch.clear();
      _pasteurised = false;
      for (final sample in _samples) {
        sample.dispose();
      }
      _samples.clear();
      _currentEggNumber = 1;
      _weightEntry.clear();
      _haughEntry.clear();
      _haughBaseline = null;
      _consignmentGrade = null;
      _nonConformance.clear();
      _managerName.clear();
      _managerEmail.clear();
      _signaturesByRole.clear();
    });
    unawaited(_saveDraft());
  }

  /// The "Container (mm)" column of the original's labelling checklists —
  /// static text in its layout (">= 5" etc.), one entry per row in order.
  static const _labelLetteringMinsMm = [5, 5, 1, 5, 1, 3, 1, 10, 10, 10];

  Widget _reqSection(String title, List<EggRequirement> items,
          {List<int>? letteringMinsMm}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.ink,
              ),
            ),
          ),
          // Both answers are on the row itself, so the small print that
          // used to explain what an empty tick box meant is gone with it.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Slide each requirement to Compliant or Deviation.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
          for (final (index, r) in items.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The original words each row twice: the label on
                        // its screen and the description it files against
                        // the record. An inspector reads the screen, so
                        // that is what is shown here.
                        Text(
                          r.screenLabel.isEmpty ? r.description : r.screenLabel,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        if (cleanRegulation(r.regulation).isNotEmpty ||
                            (letteringMinsMm != null &&
                                index < letteringMinsMm.length))
                          Text(
                            [
                              if (cleanRegulation(r.regulation).isNotEmpty)
                                cleanRegulation(r.regulation),
                              if (letteringMinsMm != null &&
                                  index < letteringMinsMm.length)
                                'Lettering \u2265 ${letteringMinsMm[index]} mm',
                            ].join('  \u00b7  '),
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // What is stored is still the failures, exactly as before
                  // — the slide only changes how the answer is given.
                  ComplianceSlider(
                    compliant: !_failedRequirements.contains(r.id),
                    onChanged: (isCompliant) {
                      final failed = !isCompliant;
                      setState(() {
                        if (failed) {
                          _failedRequirements.add(r.id);
                        } else {
                          _failedRequirements.remove(r.id);
                        }
                      });
                      // A deviation on the grade/size row decides whether
                      // there is anything to weigh, so the original's
                      // question follows it.
                      if (failed &&
                          _labelPack.isNotEmpty &&
                          r.id == _labelPack.first.id) {
                        unawaited(_askGradeSizeWeighing());
                      }
                      // FSA-SOP-APS-001 Annexure D: an omission is a
                      // seizure, a wrong indication is 30 days, so the
                      // rows that can be either ask which.
                      if (EggRules.isEggsExpressionRow(r)) {
                        if (failed) {
                          unawaited(_askIndicatedAtAll(
                              'Is the expression "Eggs" shown on the pack '
                              'at all?',
                              (absent) => _eggsExpressionAbsent = absent));
                        } else {
                          _eggsExpressionAbsent = false;
                        }
                      } else if (EggRules.isBestBeforeRow(r)) {
                        if (failed) {
                          unawaited(_askIndicatedAtAll(
                              'Is a best-before date shown on the pack at '
                              'all?',
                              (absent) => _bestBeforeAbsent = absent));
                        } else {
                          _bestBeforeAbsent = false;
                        }
                      } else if (failed) {
                        unawaited(_askAboutSeizureIfNeeded());
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      );

  /// The original replaces each photograph button's own text with a running
  /// count once a shot is taken, and turns the button green once the minimum
  /// is met. These are its strings verbatim, stray spaces and all — they come
  /// out of its string concatenation and inspectors read them as they are.
  ///
  /// One departure: the original's egg-numbering caption prints
  /// `Count - 1`, because that list is shared with the label photograph and
  /// it subtracts it back out. Taking one numbering photo therefore reads
  /// "0Egg Numbering Photo(s) Taken" on the handset. The count here is the
  /// true one.
  String _photoCaption(String kind, int count, int minimum) {
    switch (kind) {
      case 'label':
        return 'Label/Container\n[$count Photo(s) Taken]';
      case 'numbering':
        return '${count}Egg Numbering\nPhoto(s) Taken';
      case 'egg':
        return count >= minimum
            ? 'Egg Photos [ $count/$minimum Taken]'
            : 'Egg Photos [$count/$minimum Taken]';
      case 'deviation':
        return 'Label Photos - [$count/$minimum  ] Taken';
    }
    return '$count photo(s) taken';
  }

  Widget _photoRow(String kind, String label,
      {int minimum = 0, int maximum = 0}) {
    final shots = _photos.where((p) => p.kind == kind).toList();
    final metMinimum = minimum > 0 && shots.length >= minimum;
    final atMaximum = maximum > 0 && shots.length >= maximum;
    return _anchor('photo:$kind', framed: true, Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              // The original turns the button green once the minimum is
              // met, so the inspector can see at a glance which rows are done.
              if (metMinimum)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle,
                      size: 18, color: AppColors.brandTeal),
                ),
              TextButton.icon(
                onPressed: (_capturingKind == null && !atMaximum)
                    ? () => _capturePhoto(kind, label)
                    : null,
                icon: _capturingKind == kind
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_capturingKind == kind ? 'Saving…' : 'Capture'),
              ),
            ],
          ),
          // What the row asks for, on the row itself. The maximum was stated
          // and the minimum was not, so an inspector took one photograph,
          // saw nothing asking for another, and met the submit button
          // refusing without saying why.
          if (minimum > 0 || maximum > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                atMaximum
                    ? 'Maximum of $maximum photos reached.'
                    : '${[
                        if (minimum > 0) 'Minimum of $minimum photos',
                        if (maximum > 0) 'maximum of $maximum',
                      ].join(', ')}.',
                style: TextStyle(
                  fontSize: 12,
                  color: metMinimum || minimum == 0
                      ? AppColors.muted
                      : AppColors.brandRed,
                  fontWeight: metMinimum || minimum == 0
                      ? FontWeight.normal
                      : FontWeight.w700,
                ),
              ),
            ),
          if (shots.isEmpty)
            Text(
              minimum > 0 ? _photoCaption(kind, 0, minimum) : 'None captured',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            )
          else ...[
            if (minimum > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _photoCaption(kind, shots.length, minimum),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: metMinimum ? AppColors.brandTeal : AppColors.muted,
                  ),
                ),
              ),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(shots[i].path),
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        cacheWidth: 252,
                      ),
                    ),
                    // A blurred or mistaken shot has to be removable, or the
                    // inspector is stuck attaching it to the record.
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove photo',
                        // Red, not the app's accent: removing a
                        // photograph is destructive, and in teal it read as
                        // a confirmation.
                        icon:
                            const Icon(Icons.cancel, color: AppColors.brandRed),
                        onPressed: () => _removePhoto(shots[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ));
  }

  List<Widget> _resultFields() {
    final sized = _samples.where((s) => s.size != null).length;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONSIGNMENT GRADE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _consignmentGrade?.name ?? 'Not determined',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _consignmentGrade == null
                    ? AppColors.noticeForeground
                    : AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_samples.length} egg(s) sampled · $sized sized',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      // No per-egg recap. The original's results grid carries the
      // deviation counts for the consignment, not a line per egg — the
      // individual sizes and grades stay behind the form, where its own
      // analysis keeps them.
      _Text(
        label: 'Non-conformance comments',
        controller: _nonConformance,
        maxLines: 3,
      ),
      const SizedBox(height: 10),
      Text(
        'SIGNATURES CONTROL',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: AppColors.muted,
        ),
      ),
      const SizedBox(height: 6),
      if (widget.visit == null) ...[
        _Text(label: 'Authorised Manager name', controller: _managerName),
        _Text(
          label: 'Manager Email address',
          controller: _managerEmail,
          keyboardType: TextInputType.emailAddress,
        ),
        _signatureRow('manager', 'Manager Signature Block'),
        _signatureRow('inspector', 'Inspector Signature Block'),
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'This inspection is part of a store visit. The manager and '
            'inspector sign once, at the end of the visit, and those '
            'signatures are applied to every inspection in it.',
            style:
                TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
          ),
        ),
      Text(
        'Inspector: ${widget.inspectorName}',
        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
    ];
  }

  Widget _signatureRow(String role, String label) {
    final signature = _signaturesByRole[role];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        signature == null ? Icons.draw_outlined : Icons.check_circle,
        color: signature == null ? AppColors.muted : const Color(0xFF2E7D32),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        signature == null ? 'Not signed' : 'Signed',
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing: TextButton(
        onPressed: () => _sign(role, label),
        child: Text(signature == null ? 'Sign' : 'Re-sign'),
      ),
    );
  }

  Future<void> _sign(String role, String label) async {
    final storage = await PhotoStorage.instance();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = storage.pathFor('egg_sig_${_uuid}_${role}_$stamp.png');
    if (!mounted) return;
    final saved = await captureSignature(
      context,
      title: label,
      outputPath: path,
    );
    if (saved == null) return;
    await widget.repository.saveSignature(
      EggSignaturesCompanion.insert(
        inspectionUuid: _uuid,
        role: role,
        filePath: saved,
        signedName: Value(
          role == 'inspector' ? widget.inspectorName : _managerName.text.trim(),
        ),
        signedAt: Value(DateTime.now()),
      ),
    );
    for (final sig in await widget.repository.signaturesFor(_uuid)) {
      _signaturesByRole[sig.role] = sig;
    }
    if (mounted) setState(() {});
  }
}

class _Text extends StatelessWidget {
  const _Text({
    required this.label,
    required this.controller,
    this.focusNode,
    this.keyboardType,
    this.maxLines = 1,
    this.helper,
    this.enabled = true,
    this.onChanged,
    this.isRequired = false,
  });

  final String label;
  final TextEditingController controller;

  /// Draws the red star beside the label.
  final bool isRequired;

  /// Lets the form tidy what was typed when the field loses focus.
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final int maxLines;

  /// A quiet line under the field — used to say when it is optional, or
  /// what opens it.
  final String? helper;

  /// False while the original keeps this entry locked behind another step.
  final bool enabled;

  /// Fires per keystroke, for fields other steps unlock from.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => LabelledField(
        label: label,
        isRequired: isRequired,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15.5),
          decoration: InputDecoration(
            helperText: helper,
            helperMaxLines: 2,
            // Red while a refused submit has flagged this field.
            errorText: MissingFieldScope.errorOf(context),
          ),
        ),
      );
}

class _Drop<T> extends StatelessWidget {
  const _Drop({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.disabledHint,
    this.helper,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool isRequired;

  /// False while the screen's own order says this step is not open yet. The
  /// original greys the picker rather than hiding it, so the inspector can
  /// see what is coming.
  final bool enabled;

  /// Stands in for the value while [enabled] is false, saying what unlocks it.
  final String? disabledHint;

  /// A note under an open picker — what to do when the answer is nothing.
  final String? helper;

  @override
  Widget build(BuildContext context) => PickerMenuField<T>(
        label: label,
        value: items.contains(value) ? value : null,
        options: [
          for (final item in items) (value: item, text: itemLabel(item)),
        ],
        onChanged: onChanged,
        isRequired: isRequired,
        enabled: enabled,
        hint: enabled ? null : disabledHint,
        helper: enabled ? helper : disabledHint,
        emptyHint: 'Nothing to choose from yet',
      );
}
