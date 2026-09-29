import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../domain/poultry_rules.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/search_picker.dart';
import 'poultry_form_widgets.dart';
import '../domain/quid_flow.dart';

/// Setup QUID Checklist.
///
/// QUID is the declared quantity of added water in injected poultry. This
/// screen records what is being sampled and how; the weighing happens later on
/// "Continue with QUID Checklist", against the same record.
///
/// Deliberately short. The original's set-up screen is 17 fields, and padding
/// it out with the weighing fields would invite an inspector to fill them in
/// at a desk rather than at the line.
class PoultryQuidSetupForm extends StatefulWidget {
  const PoultryQuidSetupForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.visit,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;

  /// The grouped inspection this QUID belongs to, and the facility details
  /// captured once at the door. Null when it is captured on its own.
  final VisitPrefill? visit;

  @override
  State<PoultryQuidSetupForm> createState() => _PoultryQuidSetupFormState();
}

class _SetupReference {
  _SetupReference({
    required this.reasons,
    required this.locations,
    required this.facilities,
  });

  final List<PoultryDesignationRef> reasons;
  final List<PoultryDesignationRef> locations;

  /// The premises directory, shared with the egg module.
  final List<EggFacility> facilities;
}

class _PoultryQuidSetupFormState extends State<PoultryQuidSetupForm> {
  late Future<_SetupReference> _reference;

  /// Copies the visit's shared facility details in. Only empty fields take
  /// a value, so nothing already typed is overwritten.
  void _applyVisitPrefill() {
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
  }

  final _formKey = GlobalKey<FormState>();

  int? _locationId;
  int? _reasonId;

  /// True when the door-side answers settled these, so a grouped inspection
  /// is not asked the same two questions on every record inside it.
  bool _locationFromVisit = false;
  bool _reasonFromVisit = false;

  final _facilityName = TextEditingController();
  final _tradingName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityTelephone = TextEditingController();
  final _companyReg = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _productDetails = TextEditingController();
  final _injectorName = TextEditingController();

  /// "Dispensation QUID %" for the injector being added — used only when
  /// that injector runs under a dispensation rather than the regulation.
  final _dispensation = TextEditingController();

  /// The injectors added so far, in the order the list shows them.
  ///
  /// A plant runs several injectors, each set to its own percentage, so the
  /// set-up builds a list rather than naming one. The weighing screen
  /// assigns each carcass to one of these and compares the percentage the
  /// injector was set to against the percentage the weighing found.
  ///
  /// Each is held to the regulated standard (10% whole carcass, 15% cuts)
  /// or to a dispensation percentage the plant was granted — the original's
  /// Regulated Standard / Dispensation switch beside every injector.
  final _injectors = <({String name, bool dispensation, String percent})>[];

  // The original's switches start off, and off reads Water and Whole
  // Carcass.
  bool _isWaterChilled = true;
  bool _isWholeCarcass = true;

  /// The next injector is under a dispensation, not the regulation.
  bool _nextIsDispensation = false;
  bool _setupComplete = false;
  bool _saving = false;

  /// The required fields a refused Add or set-up flagged, so the page can
  /// take the inspector to the first and mark each red.
  final _missing = MissingFields();

  /// The percentage an injector is held to, as the list shows it.
  String _percentOf(({String name, bool dispensation, String percent}) i) =>
      i.dispensation
          ? i.percent
          : quidRegulatedPercent(isWholeCarcass: _isWholeCarcass)
              .toStringAsFixed(0);

  @override
  void initState() {
    super.initState();
    _applyVisitPrefill();
    _reference = _load();
    unawaited(_carryRegistrationNumber());
  }

  /// Takes the registration number from whichever poultry record in this
  /// visit captured it first — the premises has one, and it is not worth
  /// typing on each record. Only ever fills an empty field.
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

  Future<_SetupReference> _load() async => _SetupReference(
        reasons: await widget.repository.inspectionReasons(),
        locations: await widget.repository.inspectionLocations(),
        facilities: await widget.repository.facilities(),
      );

  @override
  void dispose() {
    for (final c in [
      _facilityName,
      _tradingName,
      _facilityAddress,
      _facilityTelephone,
      _companyReg,
      _contactPerson,
      _contactEmail,
      _productDetails,
      _injectorName,
      _dispensation,
    ]) {
      c.dispose();
    }
    _missing.dispose();
    super.dispose();
  }

  /// Adds what is typed to the list and clears the boxes for the next one,
  /// which is how the original's Add works: the switch goes back to the
  /// Regulated Standard and the dispensation box to "Not Used".
  Future<void> _addInjector() async {
    final name = _injectorName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name the injector before adding it to the list.'),
        ),
      );
      await _missing.flag(
        context,
        const ['injectorName'],
        stillMissing: (_) => _injectorName.text.trim().isEmpty,
      );
      return;
    }
    final typed = _dispensation.text.trim().replaceAll(',', '.');
    if (_nextIsDispensation) {
      final value = double.tryParse(typed);
      if (value == null || value <= 0) {
        await _alert(
            'Injector Add Error',
            'Dispensation QUID option selected, but no Dispensation Value '
                'has been entered.');
        if (!mounted) return;
        await _missing.flag(
          context,
          const ['dispensation'],
          stillMissing: (_) {
            final v = double.tryParse(
                _dispensation.text.trim().replaceAll(',', '.'));
            return _nextIsDispensation && (v == null || v <= 0);
          },
        );
        return;
      }
    }
    _missing.clear();
    setState(() {
      _injectors.add((
        name: name,
        dispensation: _nextIsDispensation,
        percent: _nextIsDispensation ? typed : '',
      ));
      _injectorName.clear();
      _dispensation.clear();
      _nextIsDispensation = false;
    });
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
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

  /// "Injector Inspection Set-Up Details Complete", as the original runs
  /// it: there must be an injector on the list, the inspector confirms the
  /// particulars, and the set-up is saved.
  Future<void> _completeSetup(bool on) async {
    if (!on) {
      setState(() => _setupComplete = false);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_injectors.isEmpty) {
      await _alert('Injector Details Error',
          'No Injector details has been added. Please address.');
      if (!mounted) return;
      await _missing.flag(
        context,
        const ['injectors'],
        stillMissing: (_) => _injectors.isEmpty,
      );
      return;
    }
    _missing.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Setup Data'),
        content: const Text(
            'Please confirm that all the inspection particulars is correct.',
            style: TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Edit/Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _setupComplete = true);
    await _save();
  }

  Future<void> _clearInjectors() async {
    if (_injectors.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear List'),
        content: const Text('Remove every injector from this set-up?'),
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
    setState(_injectors.clear);
  }

  /// The original's "# / Injector / %" table under the set-up.
  Widget _injectorList() {
    if (_injectors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No injectors added yet.',
          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
      );
    }
    Widget row(String a, String b, String c, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(a,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: head ? FontWeight.w900 : FontWeight.w400)),
              ),
              Expanded(
                child: Text(b,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: head ? FontWeight.w900 : FontWeight.w400)),
              ),
              SizedBox(
                width: 72,
                child: Text(c,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: head ? FontWeight.w900 : FontWeight.w400)),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('#', 'Injector', '%', head: true),
            Divider(height: 1, color: AppColors.border),
            for (var i = 0; i < _injectors.length; i++) ...[
              row('${i + 1}', _injectors[i].name, _percentOf(_injectors[i])),
              if (i < _injectors.length - 1)
                Divider(height: 1, color: AppColors.border),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final uuid = const Uuid().v4();
    await widget.captureRepository.saveQuidInspection(
      PoultryQuidInspectionsCompanion.insert(
        clientUuid: uuid,
        visitUuid: Value(widget.visit?.uuid ?? ''),
        inspectedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        // Always a draft on leaving this screen. The checklist is not finished
        // until the weighing is done, and marking it complete here would put
        // an unweighed QUID record in the register.
        status: const Value('draft'),
        locationId: Value(_locationId),
        reasonId: Value(_reasonId),
        facilityName: Value(_facilityName.text.trim()),
        producerTradingName: Value(_tradingName.text.trim()),
        facilityAddress: Value(_facilityAddress.text.trim()),
        facilityTelephone: Value(_facilityTelephone.text.trim()),
        companyRegNumber: Value(_companyReg.text.trim()),
        contactPerson: Value(_contactPerson.text.trim()),
        contactPersonEmail: Value(_contactEmail.text.trim()),
        productDetails: Value(_productDetails.text.trim()),
        isWaterChilled: Value(_isWaterChilled),
        isWholeCarcass: Value(_isWholeCarcass),
        // The list is on its own rows below; these carry the gist for
        // older readers of the record.
        injectorName: Value([for (final i in _injectors) i.name].join(', ')),
        isRegulatedStandard: Value(_injectors.every((i) => !i.dispensation)),
        dispensationQuidPercent: Value([
          for (final i in _injectors)
            if (i.dispensation) i.percent
        ].join(', ')),
        setupComplete: Value(_setupComplete),
      ),
    );

    // Each injector with the percentage it is held to, worked out now from
    // the portion type as it finally stands.
    await widget.captureRepository.replaceQuidInjectors(uuid, [
      for (var i = 0; i < _injectors.length; i++)
        PoultryQuidInjectorsCompanion.insert(
          inspectionUuid: uuid,
          position: i + 1,
          name: Value(_injectors[i].name),
          quidPercent: Value(_percentOf(_injectors[i])),
        ),
    ]);

    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QUID checklist set up'),
        content: const Text(
          'Weigh the carcasses from "Continue with QUID Checklist" when you '
          'are at the line.',
          style: TextStyle(height: 1.4),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Setup QUID Checklist',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_SetupReference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null) return const PoultryNoRules();

          // Chosen once at the door: find this commodity's rows for them.
          final doorType = widget.visit?.facilityType ?? '';
          if (_locationId == null && doorType.isNotEmpty) {
            final i = FacilityTypeMatch.indexOf(
                doorType, reference.locations.map((l) => l.name).toList());
            if (i != null) {
              _locationId = reference.locations[i].id;
              _locationFromVisit = true;
            }
          }
          final doorReason = widget.visit?.inspectionReason ?? '';
          if (_reasonId == null && doorReason.isNotEmpty) {
            final i = InspectionReasonMatch.indexOf(
                doorReason, reference.reasons.map((r) => r.name).toList());
            if (i != null) {
              _reasonId = reference.reasons[i].id;
              _reasonFromVisit = true;
            }
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                poultrySection('Inspection Details'),
                if (!_reasonFromVisit)
                  poultryDropdown(
                    label: 'Reason for Inspection',
                    value: _reasonId,
                    items: reference.reasons,
                    onChanged: (v) => setState(() => _reasonId = v),
                  ),
                if (!_locationFromVisit)
                  poultryDropdown(
                    label: 'Inspection Facility Type',
                    value: _locationId,
                    items: reference.locations,
                    onChanged: (v) => setState(() => _locationId = v),
                  ),
                // The facility and the client behind it are captured once,
                // at the top of the grouped inspection, so they are not
                // asked for again on every record inside it. The details
                // still travel with the record, filled in from the visit.
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
                    emptyHint: 'No facilities on this device yet. Open the '
                        'Server Sync with a network connection to download '
                        'the directory.',
                  ),
                  poultryField(
                      _tradingName, 'Name or Trading Name of New Facility'),
                  poultryField(_facilityAddress, 'Facility Address', lines: 2),
                  poultryField(
                    _facilityTelephone,
                    'Facility Primary Contact Telephone / Cellphone Number',
                    keyboard: TextInputType.phone,
                  ),
                  poultryField(
                      _contactPerson, 'Representative Name / Person in Charge'),
                  poultryField(
                    _contactEmail,
                    'Representative Name Email Address',
                    keyboard: TextInputType.emailAddress,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Facility: ${widget.visit!.facilityName}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft),
                    ),
                  ),
                poultryField(
                    _companyReg, 'Company Registration Number (optional)'),
                poultryField(_productDetails, 'Product Name'),

                // The original's own heading for the block below.
                poultrySection('Inspection Setup Control'),
                // Chilling method: one boolean, both states named.
                poultryChoice(
                  label: 'Chilling Method',
                  options: const ['Water', 'Air'],
                  selectedIndex: _isWaterChilled ? 0 : 1,
                  onChanged: (i) => setState(() => _isWaterChilled = i == 0),
                ),
                poultryChoice(
                  label: 'Poultry Portion Type',
                  options: const ['Whole Carcass', 'Cuts'],
                  selectedIndex: _isWholeCarcass ? 0 : 1,
                  onChanged: (i) => setState(() => _isWholeCarcass = i == 0),
                ),
                // The original's own sub-heading for the injector block.
                poultrySection('Injector Setup Details'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Add each injector on the line and the QUID percentage '
                    'it is set to. The weighing screen assigns every carcass '
                    'to one of them.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.muted, height: 1.35),
                  ),
                ),
                MissingFieldAnchor(
                  fields: _missing,
                  id: 'injectorName',
                  framed: false,
                  listenable: _injectorName,
                  child:
                      poultryField(_injectorName, 'Injector Name/Identifier'),
                ),
                poultryChoice(
                  label: 'QUID Percentage for this Injector',
                  options: const ['Regulated Standard', 'Dispensation'],
                  selectedIndex: _nextIsDispensation ? 1 : 0,
                  onChanged: (i) => setState(() {
                    _nextIsDispensation = i == 1;
                    if (!_nextIsDispensation) _dispensation.clear();
                  }),
                ),
                MissingFieldAnchor(
                  fields: _missing,
                  id: 'dispensation',
                  framed: false,
                  listenable: _dispensation,
                  child: poultryField(
                  _dispensation,
                  'Dispensation QUID %',
                  enabled: _nextIsDispensation,
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true),
                  helper: _nextIsDispensation
                      ? 'The percentage the plant\'s dispensation allows.'
                      : 'Not Used — the regulated '
                          '${quidRegulatedPercent(isWholeCarcass: _isWholeCarcass).toStringAsFixed(0)}% '
                          'applies.',
                ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: _addInjector,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed:
                              _injectors.isEmpty ? null : _clearInjectors,
                          child: const Text('Clear List'),
                        ),
                      ),
                    ),
                  ],
                ),
                MissingFieldAnchor(
                  fields: _missing,
                  id: 'injectors',
                  message: 'Add at least one injector',
                  child: _injectorList(),
                ),
                // The original saves the set-up from this switch: it checks
                // there is an injector, asks for confirmation, then saves.
                poultrySwitch(
                  label: 'Injector Inspection Set-Up Details Complete',
                  value: _setupComplete,
                  onChanged:
                      _saving ? (_) {} : (v) => unawaited(_completeSetup(v)),
                  helper: _saving
                      ? 'Saving…'
                      : 'Turn on to confirm and save the set-up.',
                ),
              ],
            ),
          );
        },
      )),
    );
  }
}
