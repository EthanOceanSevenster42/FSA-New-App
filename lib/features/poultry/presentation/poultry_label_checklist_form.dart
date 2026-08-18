import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../domain/poultry_rules.dart';
import 'poultry_evidence_section.dart';
import 'poultry_form_widgets.dart';

/// New Label/Container Checklist.
///
/// The original asks the same nine lettering requirements twice — once of the
/// product label, once of the outer container — then how the container is
/// built, then repeats the grading and portion lists. That shape is kept: an
/// inspector can find the product label compliant and the outer container not,
/// and the record has to be able to say which.
///
/// The outer run is only asked when there is an outer label to inspect. With
/// none, those rows are not findings — they do not apply, which is a different
/// thing from failing them.
class PoultryLabelChecklistForm extends StatefulWidget {
  const PoultryLabelChecklistForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.existingUuid,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;
  final String? existingUuid;

  @override
  State<PoultryLabelChecklistForm> createState() =>
      _PoultryLabelChecklistFormState();
}

class _LabelReference {
  _LabelReference({
    required this.meatTypes,
    required this.grades,
    required this.portionTypes,
    required this.designations,
    required this.altDesignations,
    required this.links,
    required this.checklist,
    required this.reasons,
    required this.locations,
    required this.restricted,
    required this.remarks,
  });

  final List<PoultryMeatTypeRef> meatTypes;
  final List<PoultryGradeRef> grades;
  final List<PoultryDesignationRef> portionTypes;
  final List<PoultryDesignationRef> designations;
  final List<PoultryDesignationRef> altDesignations;
  final List<PoultryGradeLink> links;
  final List<PoultryChecklistItemRef> checklist;
  final List<PoultryDesignationRef> reasons;
  final List<PoultryDesignationRef> locations;
  final List<PoultryDesignationRef> restricted;
  final List<PoultryDesignationRef> remarks;
}

class _PoultryLabelChecklistFormState extends State<PoultryLabelChecklistForm> {
  late Future<_LabelReference> _reference;
  final _formKey = GlobalKey<FormState>();

  late final String _clientUuid = widget.existingUuid ?? const Uuid().v4();

  int? _locationId;
  int? _reasonId;
  int? _meatTypeId;
  int? _portionTypeId;
  int? _designationId;
  int? _altDesignationId;
  int? _gradeId;
  int? _remarkTypeId;

  final _facilityName = TextEditingController();
  final _tradingName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityTelephone = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _productDetails = TextEditingController();
  final _followUp = TextEditingController();
  final _sampleNumber = TextEditingController();
  final _restrictedText = TextEditingController();
  final _nonConformanceComments = TextEditingController();
  final _directionRemarks = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _generalComments = TextEditingController();

  final _compliant = <int>{};
  final _restricted = <int>{};
  bool _outerLabelsPresent = false;
  bool _saving = false;

  /// Set once and restored on resume, so touching a draft does not move it
  /// between days and out from under the date filter that found it.
  late DateTime _inspectedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reference = _load();
    if (widget.existingUuid != null) _restore(widget.existingUuid!);
  }

  static Set<int> _idSet(String csv) => {
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  /// Puts a saved draft back on screen — resuming must never present a blank
  /// form whose completion overwrites everything already entered.
  Future<void> _restore(String uuid) async {
    final saved = await widget.captureRepository.labelInspectionByUuid(uuid);
    if (saved == null || !mounted) return;
    setState(() {
      _inspectedAt = saved.inspectedAt;
      _locationId = saved.locationId;
      _reasonId = saved.reasonId;
      _meatTypeId = saved.meatTypeId;
      _portionTypeId = saved.portionTypeId;
      _designationId = saved.designationClassId;
      _altDesignationId = saved.altDesignationClassId;
      _gradeId = saved.gradeId;
      _remarkTypeId = saved.directionRemarkTypeId;
      _outerLabelsPresent = saved.outerLabelsPresent;
      _facilityName.text = saved.facilityName;
      _tradingName.text = saved.producerTradingName;
      _facilityAddress.text = saved.facilityAddress;
      _facilityTelephone.text = saved.facilityTelephone;
      _registrationNumber.text = saved.registrationNumber;
      _contactPerson.text = saved.contactPerson;
      _contactEmail.text = saved.contactPersonEmail;
      _productDetails.text = saved.productDetails;
      _followUp.text = saved.selectedDirectionForFollowup;
      _sampleNumber.text = saved.sampleNumber;
      _restrictedText.text = saved.restrictedParticularsText;
      _nonConformanceComments.text = saved.nonConformanceComments;
      _directionRemarks.text = saved.directionRemarks;
      _managerName.text = saved.managerName;
      _managerEmail.text = saved.managerEmail;
      _clientEmail.text = saved.clientEmail;
      _clientEmail2.text = saved.clientEmail2;
      _generalComments.text = saved.generalComments;
      _compliant
        ..clear()
        ..addAll(_idSet(saved.compliantItemIds));
      _restricted
        ..clear()
        ..addAll(_idSet(saved.restrictedParticularIds));
    });
  }

  Future<_LabelReference> _load() async {
    final repo = widget.repository;
    return _LabelReference(
      meatTypes: await repo.meatTypes(),
      grades: await repo.grades(),
      portionTypes: await repo.portionTypes(),
      designations: await repo.designationClasses(),
      altDesignations: await repo.alternativeDesignationClasses(),
      links: await repo.designationGradeLinks(),
      checklist: await repo.checklistItems(),
      reasons: await repo.inspectionReasons(),
      locations: await repo.inspectionLocations(),
      restricted: await repo.restrictedParticulars(),
      remarks: await repo.directionRemarks(),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _facilityName,
      _tradingName,
      _facilityAddress,
      _facilityTelephone,
      _registrationNumber,
      _contactPerson,
      _contactEmail,
      _productDetails,
      _followUp,
      _sampleNumber,
      _restrictedText,
      _nonConformanceComments,
      _directionRemarks,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _generalComments,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The rows that actually apply.
  ///
  /// Without an outer container label, the outer lettering run is excluded
  /// rather than counted as failed — the requirement does not arise.
  List<PoultryChecklistItemRef> _applicable(_LabelReference reference) => [
        for (final item in reference.checklist)
          if (_appliesHere(item.kind)) item,
      ];

  bool _appliesHere(PoultryChecklistKind kind) => switch (kind) {
        PoultryChecklistKind.labelInner => true,
        PoultryChecklistKind.labelOuter => _outerLabelsPresent,
        PoultryChecklistKind.container => true,
        PoultryChecklistKind.labelGrading => true,
        PoultryChecklistKind.labelPortion => true,
        _ => false,
      };

  /// Writes the form to the local store — silently, so the evidence section
  /// can persist a draft the moment a photograph or signature lands.
  Future<void> _persist({required bool completed}) async {
    // Read from the signature rows rather than tracked twice, so the record
    // field can never contradict what the Signatures block shows.
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined =
        signatures.any((s) => s.role == 'no_client' && s.declined);

    await widget.captureRepository.saveLabelInspection(
      PoultryLabelInspectionsCompanion.insert(
        clientUuid: _clientUuid,
        inspectedAt: _inspectedAt,
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        status: Value(completed ? 'completed' : 'draft'),
        locationId: Value(_locationId),
        reasonId: Value(_reasonId),
        facilityName: Value(_facilityName.text.trim()),
        producerTradingName: Value(_tradingName.text.trim()),
        facilityAddress: Value(_facilityAddress.text.trim()),
        facilityTelephone: Value(_facilityTelephone.text.trim()),
        registrationNumber: Value(_registrationNumber.text.trim()),
        contactPerson: Value(_contactPerson.text.trim()),
        contactPersonEmail: Value(_contactEmail.text.trim()),
        productDetails: Value(_productDetails.text.trim()),
        selectedDirectionForFollowup: Value(_followUp.text.trim()),
        meatTypeId: Value(_meatTypeId),
        portionTypeId: Value(_portionTypeId),
        designationClassId: Value(_designationId),
        altDesignationClassId: Value(_altDesignationId),
        gradeId: Value(_gradeId),
        sampleNumber: Value(_sampleNumber.text.trim()),
        outerLabelsPresent: Value(_outerLabelsPresent),
        compliantItemIds: Value(_compliant.join(',')),
        restrictedParticularIds: Value(_restricted.join(',')),
        restrictedParticularsText: Value(_restrictedText.text.trim()),
        nonConformanceComments: Value(_nonConformanceComments.text.trim()),
        directionRemarks: Value(_directionRemarks.text.trim()),
        directionRemarkTypeId: Value(_remarkTypeId),
        managerName: Value(_managerName.text.trim()),
        managerEmail: Value(_managerEmail.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        clientEmail2: Value(_clientEmail2.text.trim()),
        noClientSignaturePresent: Value(declined),
        generalComments: Value(_generalComments.text.trim()),
      ),
    );
  }

  Future<void> _save(
    _LabelReference reference, {
    required bool completed,
  }) async {
    if (completed && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    await _persist(completed: completed);
    if (!mounted) return;
    setState(() => _saving = false);

    final findings = PoultryRules.findings(
      items: _applicable(reference),
      compliantItemIds: _compliant,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(completed ? 'Checklist saved' : 'Draft saved'),
        content: Text(
          completed
              ? findings.isEmpty
                  ? 'No deviations recorded. Send it from Inspection '
                      'Management when you have signal.'
                  : '${findings.length} '
                      '${findings.length == 1 ? "deviation" : "deviations"} '
                      'recorded. A direction may need to be served.'
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

  void _toggle(int id) => setState(() {
        if (!_compliant.remove(id)) _compliant.add(id);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Label/Container Checklist',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<_LabelReference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null || reference.checklist.isEmpty) {
            return const PoultryNoRules();
          }
          return _form(reference);
        },
      ),
    );
  }

  Widget _form(_LabelReference reference) {
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

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          poultrySection('Inspection Details'),
          poultryDropdown(
            label: 'Reason for Inspection',
            value: _reasonId,
            items: reference.reasons,
            onChanged: (v) => setState(() => _reasonId = v),
          ),
          poultryDropdown(
            label: 'Inspection Facility Type',
            value: _locationId,
            items: reference.locations,
            onChanged: (v) => setState(() => _locationId = v),
          ),
          poultryField(_facilityName, 'New Facility Name', required: true),
          poultryField(_tradingName, 'Name or Trading Name of New Facility'),
          poultryField(_facilityAddress, 'Facility Address', lines: 2),
          poultryField(
            _facilityTelephone,
            'Facility Primary Contact Telephone Number',
            keyboard: TextInputType.phone,
          ),
          poultryField(_registrationNumber, 'Registration Number'),
          poultryField(_contactPerson, 'Representative Name'),
          poultryField(
            _contactEmail,
            'Representative Email Address',
            keyboard: TextInputType.emailAddress,
          ),
          poultryField(_productDetails, 'Product Details'),
          poultryField(_followUp, 'Selected Direction for Follow up'),

          poultryChecklist(
            title: 'Product Label',
            items: of(PoultryChecklistKind.labelInner),
            compliant: _compliant,
            onToggle: _toggle,
          ),

          poultrySection('Outer Container Label'),
          poultrySwitch(
            label: 'Outer Container Label Present',
            value: _outerLabelsPresent,
            onChanged: (v) => setState(() {
              _outerLabelsPresent = v;
              if (!v) {
                // Ticks on rows that no longer apply would be carried into the
                // record as compliance nobody assessed.
                for (final item in of(PoultryChecklistKind.labelOuter)) {
                  _compliant.remove(item.id);
                }
              }
            }),
          ),
          if (_outerLabelsPresent)
            poultryChecklist(
              title: 'Outer Container Lettering',
              items: of(PoultryChecklistKind.labelOuter),
              compliant: _compliant,
              onToggle: _toggle,
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No outer container label on this consignment, so those '
                'requirements do not apply.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.muted,
                  height: 1.35,
                ),
              ),
            ),

          poultryChecklist(
            title: 'Container',
            items: of(PoultryChecklistKind.container),
            compliant: _compliant,
            onToggle: _toggle,
          ),

          poultrySection('Classifcation and Grading Checklist'),
          poultryDropdown(
            label: 'Poultry Type',
            value: _meatTypeId,
            items: [
              for (final m in reference.meatTypes)
                PoultryDesignationRef(id: m.id, name: m.name),
            ],
            onChanged: (v) => setState(() {
              _meatTypeId = v;
              _designationId = null;
              _gradeId = null;
            }),
          ),
          poultryDropdown(
            label: 'Portion Type',
            value: _portionTypeId,
            items: reference.portionTypes,
            onChanged: (v) => setState(() => _portionTypeId = v),
          ),
          poultryDropdown(
            label: 'Class Designation Type',
            value: _designationId,
            items: designations,
            emptyHint: _meatTypeId == null
                ? 'Choose a poultry type first'
                : 'No designations for this poultry type',
            onChanged: (v) => setState(() {
              _designationId = v;
              _gradeId = null;
            }),
          ),
          poultryDropdown(
            label: 'Alternative Class Designation',
            value: _altDesignationId,
            items: reference.altDesignations,
            onChanged: (v) => setState(() => _altDesignationId = v),
          ),
          poultryDropdown(
            label: 'Grade',
            value: _gradeId,
            items: [
              for (final g in grades)
                PoultryDesignationRef(id: g.id, name: g.name),
            ],
            emptyHint: _designationId == null
                ? 'Choose a class designation first'
                : 'No grades permitted for this combination',
            onChanged: (v) => setState(() => _gradeId = v),
          ),
          poultryField(_sampleNumber, 'Sample #'),

          poultryChecklist(
            title: 'Grading',
            items: of(PoultryChecklistKind.labelGrading),
            compliant: _compliant,
            onToggle: _toggle,
          ),
          poultryChecklist(
            title: 'Portions',
            items: of(PoultryChecklistKind.labelPortion),
            compliant: _compliant,
            onToggle: _toggle,
          ),

          poultrySection('Restricted Particulars'),
          for (final r in reference.restricted)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _restricted.contains(r.id),
              title: Text(r.name, style: const TextStyle(fontSize: 13.5)),
              onChanged: (on) => setState(() {
                if (on ?? false) {
                  _restricted.add(r.id);
                } else {
                  _restricted.remove(r.id);
                }
              }),
            ),
          poultryField(
            _restrictedText,
            'Selection of Restricted Particular Keywords',
            lines: 2,
          ),

          PoultryEvidenceSection(
            repository: widget.captureRepository,
            recordUuid: _clientUuid,
            kind: 'label',
            // A draft is persisted the moment evidence lands, so a photograph
            // never points at a record that was never saved.
            onChanged: () => unawaited(_persist(completed: false)),
          ),

          poultrySection('Direction Form'),
          poultryField(
            _nonConformanceComments,
            'Non-Conformance Comments',
            lines: 3,
          ),
          poultryDropdown(
            label: 'Grading Non-Conformance Remarks',
            value: _remarkTypeId,
            items: reference.remarks,
            onChanged: (v) => setState(() => _remarkTypeId = v),
          ),
          poultryField(_directionRemarks, 'List of Added Remarks', lines: 2),

          poultrySection('Signatures Control'),
          poultryField(_managerName, 'Authorised Representative name'),
          poultryField(
            _managerEmail,
            'Authorised Representative Email address',
            keyboard: TextInputType.emailAddress,
          ),
          poultryField(
            _clientEmail,
            'Email address #1',
            keyboard: TextInputType.emailAddress,
          ),
          poultryField(
            _clientEmail2,
            'Email address #2',
            keyboard: TextInputType.emailAddress,
          ),
          poultryField(_generalComments, 'General Comments', lines: 3),
          // The "No Client Signature is available" control lives in the
          // Signatures block — one tick-box, not two that can disagree.

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _save(reference, completed: false),
                    child: const Text('Save draft'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(reference, completed: true),
                    child: Text(_saving ? 'Saving…' : 'Complete'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
