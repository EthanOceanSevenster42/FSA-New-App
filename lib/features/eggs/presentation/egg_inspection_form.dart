import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/services/in_app_camera.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import '../data/eggs_sync_service.dart';
import 'date_field.dart';
import 'egg_direction_form.dart';
import 'new_directory_entry_sheet.dart';
import 'picker_sheet.dart';
import 'required_label.dart';
import 'saved_dialog.dart';
import 'search_picker.dart';
import '../domain/egg_rules.dart';

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
  final _page = PageController();
  int _step = 0;
  bool _saving = false;
  bool _loading = true;

  // Reference
  List<EggSizeBand> _bands = [];
  List<EggGradeRef> _gradeRefs = [];
  List<DeviationRef> _deviationRefs = [];
  List<EggDeviationCategory> _categories = [];
  List<EggFacilityType> _facilityTypes = [];
  List<EggInspectionReason> _reasons = [];
  List<EggTraySize> _traySizes = [];
  List<EggRequirement> _labelPack = [];
  List<EggRequirement> _labelOuter = [];
  List<EggRequirement> _packing = [];
  List<EggRestrictedParticular> _particulars = [];
  Map<int, List<EggDeviation>> _deviationsByCategory = {};

  List<EggClient> _clients = [];
  List<EggFacility> _facilities = [];
  List<EggSupplier> _suppliers = [];

  // Selections
  EggClient? _client;
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
  final _samples = <_Sample>[];
  Position? _position;
  final _photos = <_Shot>[];
  bool _pasteurised = false;
  bool _haughNotRequired = false;

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
  final _generalComments = TextEditingController();
  final _nonConformance = TextEditingController();
  final _overrideReason = TextEditingController();
  DateTime? _bestBefore;

  EggGradeRef? _consignmentGrade;
  bool _override = false;
  EggGradeRef? _overrideGrade;

  static const _titles = [
    'Facility & client',
    'Product',
    'Egg samples',
    'Labelling & packing',
    'Photos',
    'Result',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // Every inspection is located. Permission is requested once at app start,
    // so this is a silent fix rather than a prompt mid-inspection, and it
    // begins immediately so a fix is ready by the time it is needed.
    unawaited(_captureLocation(silent: true));
  }

  @override
  void dispose() {
    for (final sample in _samples) {
      sample.dispose();
    }
    _page.dispose();
    for (final c in [
      _facilityName, _facilityAddress, _facilityPhone, _clientName,
      _clientAddress, _contactPerson, _contactNumber, _clientEmail,
      _representative, _producer, _batch, _generalComments,
      _nonConformance, _overrideReason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = widget.repository;
    _bands = await r.sizeBands();
    _gradeRefs = await r.gradeRefs();
    _deviationRefs = await r.deviationRefs();
    _categories = await r.deviationCategories();
    _facilityTypes = await r.facilityTypes();
    _reasons = await r.reasons();
    _traySizes = await r.traySizes();
    _tolerances = await r.deviationTolerances();
    _checklists = await r.requirementChecklists();
    _labelPack = await r.requirements('label_pack');
    _labelOuter = await r.requirements('label_outer');
    _packing = await r.requirements('packing');
    _particulars = await r.restrictedParticulars();
    _clients = await r.clients();
    _facilities = await r.facilities();
    _suppliers = await r.suppliers();
    _deviationsByCategory = {
      for (final c in _categories) c.id: await r.deviationsFor(c.id),
    };
    if (widget.resumeUuid != null) await _restoreDraft();
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
    _producer.text = draft.producerSupplier;
    _batch.text = draft.batchNumber;
    _generalComments.text = draft.generalComments;
    _nonConformance.text = draft.nonConformanceComments;
    _overrideReason.text = draft.overrideReason;
    _bestBefore = draft.bestBefore;
    _pasteurised = draft.pasteurisedPresent;
    _haughNotRequired = draft.haughNotRequired;
    _override = draft.gradeOverridden;

    _facilityType =
        _facilityTypes.where((t) => t.id == draft.facilityTypeId).firstOrNull;
    _reason = _reasons.where((x) => x.id == draft.reasonId).firstOrNull;
    _traySize = _traySizes.where((t) => t.id == draft.traySizeId).firstOrNull;
    _declaredSize =
        _bands.where((b) => b.id == draft.declaredSizeId).firstOrNull;
    _declaredGrade =
        _gradeRefs.where((g) => g.id == draft.declaredGradeId).firstOrNull;

    int? asId(String v) => int.tryParse(v.trim());
    _failedRequirements
      ..clear()
      ..addAll(draft.failedRequirementIds.split(',').map(asId).whereType<int>());
    _selectedParticulars
      ..clear()
      ..addAll(
        draft.restrictedParticularIds.split(',').map(asId).whereType<int>(),
      );

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
      // Size, Haugh and grade are derived, so recompute rather than trust a
      // stored value that may predate a rule change.
      sample.size = EggRules.sizeFor(sample.massG, _bands);
      sample.haugh = _haughNotRequired
          ? null
          : EggRules.haughUnit(
              albumenHeightMm: sample.albumenHeightMm,
              massG: sample.massG,
            );
      sample.grade = EggRules.gradeForEgg(
        tickedDeviationIds: sample.deviationIds,
        deviations: _deviationRefs,
        grades: _gradeRefs,
      );
      // The readings exist on the record but nothing has typed them into
      // the fields, so put them there.
      sample.fillControllers();
      _samples.add(sample);
    }
    _consignmentGrade =
        EggRules.consignmentGrade([for (final x in _samples) x.grade]);
    _overrideGrade =
        _gradeRefs.where((g) => g.id == draft.determinedGradeId).firstOrNull;

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
        DirectoryField(label: 'Physical address', key: 'address'),
        DirectoryField(
            label: 'Telephone',
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
        DirectoryField(label: 'Physical address', key: 'address'),
        DirectoryField(label: 'Contact person', key: 'contact'),
        DirectoryField(
            label: 'Telephone',
            key: 'telephone',
            keyboardType: TextInputType.phone),
        DirectoryField(
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

  /// Registers a client the directory does not hold, then selects them.
  Future<void> _addClient(String typedName) async {
    final values = await showNewDirectoryEntrySheet(
      context,
      title: 'New client',
      subtitle: 'Registered on the server so the next inspection for this '
          'client links up rather than recording a loose name.',
      saveLabel: 'Add client',
      fields: [
        DirectoryField(
            label: 'Name', key: 'name', initial: typedName, isRequired: true),
        DirectoryField(label: 'Trading name', key: 'trading'),
        DirectoryField(label: 'Physical address', key: 'address'),
        DirectoryField(label: 'Contact person', key: 'contact'),
        DirectoryField(
            label: 'Telephone',
            key: 'telephone',
            keyboardType: TextInputType.phone),
        DirectoryField(
            label: 'Email',
            key: 'email',
            keyboardType: TextInputType.emailAddress),
      ],
    );
    if (values == null || !mounted) return;

    try {
      final client = await widget.repository.addClient(
        name: values['name'] ?? typedName,
        tradingName: values['trading'] ?? '',
        physicalAddress: values['address'] ?? '',
        contactPerson: values['contact'] ?? '',
        telephone: values['telephone'] ?? '',
        email: values['email'] ?? '',
      );
      if (!mounted) return;
      setState(() => _clients = [..._clients, client]);
      _onClientSelected(client);
      _toast('Client added.');
    } on Object catch (e) {
      if (mounted) _toast('Could not add the client. $e');
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
    });
  }

  /// Fills the client fields from the picked record. They stay editable —
  /// details change in the field, and an inspector must be able to correct
  /// them without abandoning the selection.
  void _onClientSelected(EggClient client) {
    setState(() {
      _client = client;
      _clientName.text = client.name;
      _clientAddress.text = client.physicalAddress;
      _contactPerson.text = client.contactPerson;
      _contactNumber.text = client.telephone;
      _clientEmail.text = client.email;
    });
  }

  void _clearClient() {
    setState(() {
      _client = null;
      _clientName.clear();
      _clientAddress.clear();
      _contactPerson.clear();
      _contactNumber.clear();
      _clientEmail.clear();
    });
  }

  /// Recomputes size, Haugh unit and grade for one egg, then the consignment.
  void _recalculate(_Sample s) {
    s.size = EggRules.sizeFor(s.massG, _bands);
    s.haugh = _haughNotRequired
        ? null
        : EggRules.haughUnit(
            albumenHeightMm: s.albumenHeightMm,
            massG: s.massG,
          );
    s.grade = EggRules.gradeForEgg(
      tickedDeviationIds: s.deviationIds,
      deviations: _deviationRefs,
      grades: _gradeRefs,
    );
    _consignmentGrade =
        EggRules.consignmentGrade([for (final x in _samples) x.grade]);
    _updateHaughBaseline();
    setState(() {});
  }

  /// Fixes the baseline the moment the mean drops below the threshold, and
  /// clears it if further readings bring the mean back up.
  void _updateHaughBaseline() {
    final mean =
        EggRules.meanHaughUnit([for (final x in _samples) x.haugh]);
    if (mean == null || mean >= EggRules.haughAdditionalSampleThreshold) {
      _haughBaseline = null;
      return;
    }
    _haughBaseline ??= _samples.length;
  }

  void _addEgg() {
    setState(() => _samples.add(_Sample(_samples.length + 1)));
  }

  /// Which photo row is mid-capture, so its button can show progress rather
  /// than the screen appearing to hang while the plugin re-encodes.
  String? _capturingKind;

  Future<void> _capturePhoto(String kind, String label) async {
    // One at a time. Two cameras in flight would race on the file name and
    // leave a photo attributed to the wrong row.
    if (_capturingKind != null) return;

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
  String? _blockingIssue() {
    // --- Facility
    if (_facilityName.text.trim().isEmpty) {
      return 'Inspection facility name is required.';
    }
    if (_facilityType == null) return 'Facility type must be selected.';
    if (_reason == null) return 'Reason for inspection must be selected.';

    // --- Client. Message: "Please type in the client / Physical Address /
    // Telephone to proceed."
    if (_clientName.text.trim().isEmpty) {
      return 'Please type in the client to proceed.';
    }
    if (_clientAddress.text.trim().isEmpty) {
      return 'Please type in the physical address to proceed.';
    }
    if (_contactNumber.text.trim().isEmpty) {
      return 'Please type in the telephone to proceed.';
    }
    final email = EggValidation.email(_clientEmail.text);
    if (email != null) return email;

    // --- Product
    if (_producer.text.trim().isEmpty) {
      return 'Egg producer / supplier is required.';
    }
    if (_batch.text.trim().isEmpty) return 'Batch number is required.';
    if (_traySize == null) return 'Tray packaging size must be selected.';
    // Without these there is no tolerance band to judge deviations against,
    // so whether a direction must be served cannot be answered.
    if (_declaredSize == null) {
      return 'The size the consignment is sold as must be selected.';
    }
    if (_declaredGrade == null) {
      return 'The grade the consignment is sold as must be selected.';
    }

    final bestBefore = EggValidation.bestBefore(_bestBefore);
    if (bestBefore != null) return bestBefore;

    // --- Samples
    if (_samples.isEmpty) return 'Capture at least one egg before saving.';
    if (_samples.length > EggValidation.maxSamples) {
      return 'Maximum number of samples reached '
          '(${EggValidation.maxSamples}).';
    }

    for (final s in _samples) {
      if (s.massG == null || s.massG! <= 0) {
        return 'Egg #${s.number} has no weight reading.';
      }
      // A weight above the sanity ceiling is flagged under the field but does
      // not stop the inspection being saved. It guards against a mis-keyed
      // scale reading rather than enforcing a regulation, and an inspector
      // holding a genuinely heavy egg must still be able to record it.
      final albumen = EggValidation.albumenHeight(s.albumenHeightMm);
      if (albumen != null) return 'Egg #${s.number}: $albumen';
    }

    if (_outstandingSamples > 0) {
      return 'Mean Haugh value is below '
          '${EggRules.haughAdditionalSampleThreshold.toStringAsFixed(0)} HU — '
          '$_outstandingSamples further sample(s) required.';
    }

    // --- Evidence. Message: "No photo of the label has been taken. Please
    // address." A labelling finding without a photograph cannot be defended.
    if (!_photos.any((p) => p.kind == 'label')) {
      return 'No photo of the label has been taken. Please address.';
    }

    if (_override && _overrideReason.text.trim().isEmpty) {
      return 'A reason is required when overriding the grade.';
    }
    return null;
  }

  /// Message: "Please confirm that you want to save the entire inspection with
  /// the info captured as is?"
  Future<bool> _confirmSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Submit inspection',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
        ),
        content: Text(
          'Please confirm that you want to save the entire inspection with '
          'the information captured as is.',
          style: TextStyle(color: AppColors.inkSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
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
  EggInspectionsCompanion _companion({required String status}) {
    final now = DateTime.now();
    return EggInspectionsCompanion.insert(
      clientUuid: _uuid,
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
      producerSupplier: Value(_producer.text.trim()),
      batchNumber: Value(_batch.text.trim()),
      bestBefore: Value(_bestBefore),
      traySizeId: Value(_traySize?.id),
      declaredSizeId: Value(_declaredSize?.id),
      declaredGradeId: Value(_declaredGrade?.id),
      sampleSize: Value(_samples.length),
      pasteurisedPresent: Value(_pasteurised),
      haughNotRequired: Value(_haughNotRequired),
      determinedGradeId:
          Value(_override ? _overrideGrade?.id : _consignmentGrade?.id),
      gradeOverridden: Value(_override),
      overrideReason: Value(_overrideReason.text.trim()),
      generalComments: Value(_generalComments.text.trim()),
      nonConformanceComments: Value(_nonConformance.text.trim()),
      failedRequirementIds: Value(_failedRequirements.join(',')),
      restrictedParticularIds: Value(_selectedParticulars.join(',')),
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
    final issue = _blockingIssue();
    if (issue != null) {
      _toast(issue);
      return;
    }
    if (!await _confirmSubmit()) return;
    if (!mounted) return;

    setState(() => _saving = true);

    try {
      // Photographs were written as they were taken, so only the record and
      // its eggs need saving here.
      await widget.repository.saveInspection(
        _companion(status: 'completed'),
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
    if (sync != null) {
      final saved = await widget.repository.inspectionByUuid(_uuid);
      if (saved != null) sent = await sync.sendNow(saved);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    await showSavedDialog(
      context,
      noun: 'inspection',
      state: _savedState(sent, sync),
    );
    if (!mounted) return;

    // A direction is a consequence of the findings, not a separate errand.
    // The original raises it as part of saving the inspection, and leaving it
    // to the inspector to remember is how a non-conforming consignment leaves
    // the premises with no notice served.
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

    return EggRules.directionRequired(
      countsByDeviationId: counts,
      // Validation blocks saving without these, so the fallback is only
      // reached on a record that could not have been saved.
      sizeId: _declaredSize?.id ?? -1,
      gradeId: _declaredGrade?.id ?? -1,
      tolerances: _tolerances,
      failedRequirementIds: _failedRequirements,
      checklists: _checklists,
    );
  }

  /// Opens the direction, pre-filled, with the compulsory parts already set.
  Future<void> _raiseDirection(DirectionRequirement required) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.gavel, size: 32, color: AppColors.brandRed),
        title: const Text('A direction must be served'),
        content: Text(
          '${_directionReason(required)}\n\n'
          'The direction is filled in from this inspection. You set the '
          'correction dates and the remarks.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          FilledButton(
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
        ),
      ),
    );
  }

  String _directionReason(DirectionRequirement required) {
    if (required.quality && required.labelling) {
      return 'This consignment fails on both quality and labelling. One '
          'direction covers both, each with its own correction date.';
    }
    if (required.quality) {
      return 'A deviation exceeds what is allowed for a consignment sold as '
          '${_declaredGrade?.name} ${_declaredSize?.name}.';
    }
    return 'The marking and packing requirements were not met.';
  }

  void _goto(int step) {
    // Cheap insurance: every step change leaves a recoverable draft behind.
    unawaited(_saveDraft());
    setState(() => _step = step);
    _page.animateToPage(
      step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titles[_step],
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              'Step ${_step + 1} of ${_titles.length}',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_step + 1) / _titles.length,
            backgroundColor: AppColors.surfaceAlt,
            color: AppColors.brandRed,
            minHeight: 3,
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _facilityStep(),
                _productStep(),
                _samplesStep(),
                _requirementsStep(),
                _photosStep(),
                _resultStep(),
              ],
            ),
          ),
          _navBar(),
        ],
      ),
    );
  }

  Widget _navBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _goto(_step - 1),
                      child: const Text('Back'),
                    ),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            if (_step == _titles.length - 1) {
                              await _save();
                            } else {
                              _goto(_step + 1);
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(_step == _titles.length - 1
                            ? 'SAVE INSPECTION'
                            : 'NEXT'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _pad(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: children,
      );

  Widget _facilityStep() => _pad([
        const RequiredLegend(),
        // Pick a known premises rather than retyping four fields per visit,
        // and so the same facility is spelled the same way on every record.
        // One field, not two: type the premises and pick it from the list, or
        // type a name that is not on the list and carry on.
        SearchPickerField<EggFacility>(
          label: 'Inspection facility name',
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
          addNewLabel: 'Add as new premises',
          onAddNew: _addFacility,
          isRequired: true,
          emptyHint: 'No facilities on this device yet. Sync from the Eggs '
              'menu to download them.',
        ),
        _Drop<EggFacilityType>(
          label: 'Facility type',
          value: _facilityType,
          items: _facilityTypes,
          itemLabel: (f) => f.name,
          onChanged: (f) => setState(() => _facilityType = f),
          isRequired: true,
        ),
        _Text(label: 'Facility address', controller: _facilityAddress),
        _Text(
          label: 'Facility telephone',
          controller: _facilityPhone,
          keyboardType: TextInputType.phone,
        ),
        _Drop<EggInspectionReason>(
          label: 'Reason for inspection',
          value: _reason,
          items: _reasons,
          itemLabel: (r) => r.name,
          onChanged: (r) => setState(() => _reason = r),
          isRequired: true,
        ),
        Divider(height: 28, color: AppColors.border),
        // Pick a known client rather than retyping four fields at every
        // consignment.
        SearchPickerField<EggClient>(
          label: 'Client name',
          controller: _clientName,
          options: _clients,
          optionLabel: (c) => c.name,
          optionSubtitle: (c) => [
            if (c.tradingName.trim().isNotEmpty) 't/a ${c.tradingName}',
            if (!c.isRegistered) 'unregistered',
            c.physicalAddress,
          ].where((part) => part.trim().isNotEmpty).join(' · '),
          onSelected: _onClientSelected,
          addNewLabel: 'Add as a new client',
          onAddNew: _addClient,
          isRequired: true,
          emptyHint: 'No clients on this device yet. Sync from the Eggs menu '
              'to download them.',
        ),
        if (_client != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Details filled from the client list. Edit below if they '
                    'have changed.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      height: 1.3,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearClient,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        _Text(
          label: 'Client physical address',
          controller: _clientAddress,
          isRequired: true,
        ),
        _Text(label: 'Contact person', controller: _contactPerson),
        _Text(
          label: 'Telephone',
          controller: _contactNumber,
          keyboardType: TextInputType.phone,
          isRequired: true,
        ),
        _Text(
          label: 'Client email',
          controller: _clientEmail,
          keyboardType: TextInputType.emailAddress,
          // Message: "The email address does not meet standard conventions."
          errorText: EggValidation.email(_clientEmail.text),
          onChanged: (_) => setState(() {}),
        ),
        _Text(
          label: 'Representative / person in charge',
          controller: _representative,
        ),
      ]);

  Widget _productStep() => _pad([
        const RequiredLegend(),
        SearchPickerField<EggSupplier>(
          label: 'Egg producer / supplier',
          controller: _producer,
          options: _suppliers,
          optionLabel: (x) => x.name,
          optionSubtitle: (x) => x.physicalAddress,
          onSelected: (x) => setState(() => _producer.text = x.name),
          isRequired: true,
          addNewLabel: 'Add as a new supplier',
          onAddNew: _addSupplier,
          emptyHint: 'No suppliers on this device yet. Sync from the Eggs '
              'menu, or add one here.',
        ),
        _Text(
          label: 'Batch number',
          controller: _batch,
          isRequired: true,
        ),
        DateField(
          label: 'Best before / best quality before',
          value: _bestBefore,
          onChanged: (d) => setState(() => _bestBefore = d),
          // Neither past nor today, so the picker cannot offer a date the
          // form would then reject.
          firstDate: DateTime.now().add(const Duration(days: 1)),
          lastDate: DateTime(DateTime.now().year + 3),
          errorText: EggValidation.bestBefore(_bestBefore),
          helperText: 'Printed on the pack. Leave empty if the consignment '
              'carries none.',
        ),
        _Drop<EggTraySize>(
          label: 'Tray packaging size',
          value: _traySize,
          items: _traySizes,
          itemLabel: (t) => t.name,
          onChanged: (t) => setState(() => _traySize = t),
          isRequired: true,
        ),
        // What the consignment claims to be. The deviation tolerances are
        // keyed on these, so they decide how strictly the sample is judged.
        _Drop<EggSizeBand>(
          label: 'Size declared on the pack',
          value: _declaredSize,
          items: _bands,
          itemLabel: (b) => b.name,
          onChanged: (b) => setState(() => _declaredSize = b),
          isRequired: true,
        ),
        _Drop<EggGradeRef>(
          label: 'Grade declared on the pack',
          value: _declaredGrade,
          items: _gradeRefs,
          itemLabel: (g) => g.name,
          onChanged: (g) => setState(() => _declaredGrade = g),
          isRequired: true,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.brandRed,
          value: _pasteurised,
          title: const Text('Pasteurised eggs present'),
          onChanged: (v) => setState(() => _pasteurised = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.brandRed,
          value: _haughNotRequired,
          title: const Text('Haugh readings not required'),
          subtitle: const Text(
            'Hides albumen height and skips the Haugh calculation.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (v) {
            setState(() => _haughNotRequired = v);
            for (final s in _samples) {
              _recalculate(s);
            }
          },
        ),
      ]);

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

  Widget _samplesStep() => _pad([
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
        if (_samples.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No eggs captured yet. Add one egg per unit drawn from the '
              'sample — each is weighed, sized and graded individually.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
          ),
        for (final s in _samples) _sampleCard(s),
        const SizedBox(height: 8),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _addEgg,
            icon: const Icon(Icons.add),
            label: Text('Add egg #${_samples.length + 1}'),
          ),
        ),
      ]);

  Widget _sampleCard(_Sample s) => Container(
        // Tied to the egg, not to a position in the list.
        //
        // The "further samples required" banner appears and disappears above
        // this list as readings are typed, which shifts every card down or up
        // one. Without a key Flutter rebinds each card to a different element,
        // destroys the field being typed into, and the keyboard closes
        // mid-number. Keying on the egg keeps the field — and the caret —
        // exactly where the inspector left it.
        key: ValueKey(s),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Egg #${s.number}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (s.grade != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.grade!.name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandTeal,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => setState(() {
                    _samples.remove(s);
                    s.dispose();
                    _consignmentGrade = EggRules.consignmentGrade(
                      [for (final x in _samples) x.grade],
                    );
                  }),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.brandRed),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextFormField(
              // Controlled by the egg, not by this widget's position in the
              // list. See _Sample.
              key: ValueKey('mass-${s.number}'),
              controller: s.massController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Mass (g) *',
                // Message: "Entered weight is too high. Please recheck the
                // scale's reading."
                errorText: EggValidation.eggMass(s.massG),
              ),
              onChanged: (v) {
                s.massG = double.tryParse(v.trim().replaceAll(',', '.'));
                _recalculate(s);
              },
            ),
            if (s.massG != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.size == null
                      // Not forced into a band — an out-of-range mass is a
                      // finding, not a "Small" egg.
                      ? 'Mass falls outside every size band'
                      : 'Size: ${s.size!.name}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: s.size == null
                        ? AppColors.noticeForeground
                        : AppColors.brandTeal,
                  ),
                ),
              ),
            if (!_haughNotRequired) ...[
              const SizedBox(height: 10),
              TextFormField(
                // The "Size: …" line above appears the moment a mass is
                // entered, shifting this field down inside the card.
                key: ValueKey('albumen-${s.number}'),
                controller: s.albumenController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Message: "No weight has been entered for this sample. No
                // Haugh Unit can be calculated." The formula needs the mass,
                // so the field is unusable until it is present.
                enabled: EggValidation.canRecordDeviations(s.massG),
                decoration: InputDecoration(
                  labelText: 'Albumen height (mm)',
                  helperText: EggValidation.canRecordDeviations(s.massG)
                      ? 'Haugh meter reading'
                      : EggValidation.haughNeedsMass,
                  // Message: "The Haugh meter value cannot be 0 or less."
                  errorText: EggValidation.albumenHeight(s.albumenHeightMm),
                ),
                onChanged: (v) {
                  s.albumenHeightMm =
                      double.tryParse(v.trim().replaceAll(',', '.'));
                  _recalculate(s);
                },
              ),
              if (s.haugh != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Haugh unit: ${s.haugh!.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandTeal,
                    ),
                  ),
                ),
            ] else
              // The field is not missing — it was switched off for the whole
              // consignment on the Product step. Without saying so, it simply
              // vanishes and looks like the app has lost it.
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Albumen height is off for this consignment, so no '
                        'Haugh unit is calculated.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _goto(1),
                      child: const Text('Turn on'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'DEVIATIONS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            // A weight must be entered before deviations can be
            // noted. Enforced by disabling them rather than by an alert after
            // the fact.
            if (!EggValidation.canRecordDeviations(s.massG))
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  EggValidation.deviationsNeedMass,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppColors.noticeForeground,
                  ),
                ),
              ),
            for (final category in _categories) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              for (final d in _deviationsByCategory[category.id] ??
                  const <EggDeviation>[])
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  activeColor: AppColors.brandRed,
                  value: s.deviationIds.contains(d.id),
                  title: Text(
                    d.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: EggValidation.canRecordDeviations(s.massG)
                          ? AppColors.ink
                          : AppColors.muted,
                    ),
                  ),
                  onChanged: EggValidation.canRecordDeviations(s.massG)
                      ? (v) {
                          if (v ?? false) {
                            s.deviationIds.add(d.id);
                          } else {
                            s.deviationIds.remove(d.id);
                          }
                          _recalculate(s);
                        }
                      : null,
                ),
            ],
          ],
        ),
      );

  Widget _requirementsStep() => _pad([
        Text(
          'Tick anything the consignment FAILS.',
          style: TextStyle(color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _reqSection('Marking / labelling — packaging', _labelPack),
        _reqSection('Marking / labelling — outer packaging', _labelOuter),
        _reqSection('Packing — inner/outer containers (Reg 6)', _packing),
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
        for (final p in _particulars)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.brandRed,
            value: _selectedParticulars.contains(p.id),
            title: Text(p.keyword, style: const TextStyle(fontSize: 14)),
            subtitle: p.note.isEmpty
                ? null
                : Text(p.note, style: const TextStyle(fontSize: 11.5)),
            onChanged: (v) => setState(() {
              if (v ?? false) {
                _selectedParticulars.add(p.id);
              } else {
                _selectedParticulars.remove(p.id);
              }
            }),
          ),
      ]);

  Widget _reqSection(String title, List<EggRequirement> items) => Column(
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
          for (final r in items)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.brandRed,
              value: _failedRequirements.contains(r.id),
              title: Text(r.description, style: const TextStyle(fontSize: 13.5)),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _failedRequirements.add(r.id);
                } else {
                  _failedRequirements.remove(r.id);
                }
              }),
            ),
        ],
      );

  Widget _photosStep() => _pad([
        for (final entry in const [
          ('egg', 'Egg photos'),
          // Required: a labelling finding cannot be defended without one.
          ('label', 'Label photos *'),
          ('deviation', 'Deviation photos'),
          ('numbering', 'Egg numbering'),
        ])
          _photoRow(entry.$1, entry.$2),
        Divider(height: 26, color: AppColors.border),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.my_location, color: AppColors.brandTeal),
          title: const Text(
            'GPS location',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _position == null
                ? 'Not captured'
                : '${_position!.latitude.toStringAsFixed(5)}, '
                    '${_position!.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: TextButton(
            onPressed: _captureLocation,
            child: Text(_position == null ? 'Capture' : 'Update'),
          ),
        ),
      ]);

  Widget _photoRow(String kind, String label) {
    final shots = _photos.where((p) => p.kind == kind).toList();
    return Padding(
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
              TextButton.icon(
                onPressed: _capturingKind == null
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
          if (shots.isEmpty)
            Text(
              'None captured',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            )
          else
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
                        icon: const Icon(Icons.cancel,
                            color: AppColors.brandRed),
                        onPressed: () => _removePhoto(shots[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultStep() {
    final sized = _samples.where((s) => s.size != null).length;
    return _pad([
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
                fontSize: 26,
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
      if (_samples.isNotEmpty) ...[
        Text(
          'PER EGG',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        for (final s in _samples)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '#${s.number}: '
              '${s.massG?.toStringAsFixed(1) ?? '—'} g · '
              '${s.size?.name ?? 'unsized'} · '
              '${s.grade?.name ?? 'ungraded'}'
              '${s.haugh == null ? '' : ' · HU ${s.haugh!.toStringAsFixed(1)}'}'
              '${s.deviationIds.isEmpty ? '' : ' · ${s.deviationIds.length} deviation(s)'}',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        const SizedBox(height: 16),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppColors.brandRed,
        value: _override,
        title: const Text(
          'Override the determined grade',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Requires a reason, and is recorded against your name.',
          style: TextStyle(fontSize: 12),
        ),
        onChanged: (v) => setState(() => _override = v),
      ),
      if (_override) ...[
        _Drop<EggGradeRef>(
          label: 'Override grade',
          value: _overrideGrade,
          items: _gradeRefs,
          itemLabel: (g) => g.name,
          onChanged: (g) => setState(() => _overrideGrade = g),
        ),
        _Text(
          label: 'Reason for override *',
          controller: _overrideReason,
          maxLines: 2,
        ),
      ],
      _Text(
        label: 'Non-conformance comments',
        controller: _nonConformance,
        maxLines: 3,
      ),
      _Text(
        label: 'General comments',
        controller: _generalComments,
        maxLines: 3,
      ),
      const SizedBox(height: 8),
      Text(
        'Inspector: ${widget.inspectorName}',
        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
    ]);
  }
}

class _Text extends StatelessWidget {
  const _Text({
    required this.label,
    required this.controller,
    this.isRequired = false,
    this.keyboardType,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool isRequired;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => LabelledField(
        label: label,
        isRequired: isRequired,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15.5),
          decoration: InputDecoration(errorText: errorText),
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
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool isRequired;

  /// Opens the options in a bottom sheet.
  ///
  /// A dropdown menu is positioned over its own button, so on a form it
  /// covered the fields above and below — the complaint that prompted this.
  /// A sheet comes up from the bottom over a dimmed page: it cannot be
  /// mistaken for the form, it names what is being chosen, and each option
  /// gets a full-width row.
  Future<void> _choose(BuildContext context) async {
    if (items.isEmpty) return;
    final picked = await showPickerSheet<T>(
      context: context,
      title: label,
      items: items,
      itemLabel: itemLabel,
      selected: value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final empty = items.isEmpty;
    return LabelledField(
      label: label,
      isRequired: isRequired,
      child: InkWell(
        onTap: empty ? null : () => _choose(context),
        borderRadius: BorderRadius.circular(10),
        // Same chrome as the text and date fields, so the row reads as one
        // more input rather than a control of its own kind.
        child: InputDecorator(
          isEmpty: false,
          decoration: const InputDecoration(
            suffixIcon: Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            value != null
                ? itemLabel(value as T)
                : (empty ? 'Nothing to choose from' : 'Select'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              // An unchosen value is a prompt, not an answer.
              fontWeight: value != null ? FontWeight.w700 : FontWeight.w400,
              color: value != null ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
