import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import 'poultry_evidence_section.dart';
import '../domain/poultry_rules.dart';

/// New Grading and Classification Checklist.
///
/// Follows the original screen's order so an inspector working from the paper
/// form fills the two in the same sequence: where and why, then the facility,
/// then what is being inspected, then the three tick-lists, then remarks.
///
/// The tick-lists read "No deviation" because that is what a tick means here —
/// the original's column header. Labelling them "Deviation" would invert every
/// record captured.
class PoultryInspectionForm extends StatefulWidget {
  const PoultryInspectionForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.existingUuid,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;

  /// Set when resuming a draft.
  final String? existingUuid;

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
    required this.restricted,
    required this.remarks,
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
  final List<PoultryDesignationRef> restricted;
  final List<PoultryDesignationRef> remarks;
}

class _PoultryInspectionFormState extends State<PoultryInspectionForm> {
  late Future<_Reference> _reference;

  final _formKey = GlobalKey<FormState>();

  late final String _clientUuid =
      widget.existingUuid ?? const Uuid().v4();

  int? _locationId;
  int? _reasonId;
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
  final _restricted = <int>{};

  /// When the consignment was inspected — set once, and restored on resume.
  /// Stamping every save with "now" instead silently moved a draft between
  /// days each time it was touched, changing which date filter finds it.
  late DateTime _inspectedAt = DateTime.now();

  bool _saving = false;

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
      _producerTradingName.text = saved.producerTradingName;
      _productDetails.text = saved.productDetails;
      _sampleNumber.text = saved.sampleNumber;
      _inspectionComments.text = saved.inspectionComments;
      _directionComments.text = saved.directionComments;
      _directionRemarks.text = saved.directionRemarks;
      _compliant
        ..clear()
        ..addAll(_idSet(saved.compliantItemIds));
      _restricted
        ..clear()
        ..addAll(_idSet(saved.restrictedParticularIds));
    });
  }

  Future<_Reference> _load() async {
    final repo = widget.repository;
    return _Reference(
      meatTypes: await repo.meatTypes(),
      grades: await repo.grades(),
      portionTypes: await repo.portionTypes(),
      designations: await repo.designationClasses(),
      altDesignations: await repo.alternativeDesignationClasses(),
      links: await repo.designationGradeLinks(),
      altLinks: await repo.alternativeGradeLinks(),
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
      _facilityAddress,
      _facilityTelephone,
      _companyReg,
      _contactPerson,
      _contactEmail,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _producerTradingName,
      _productDetails,
      _sampleNumber,
      _inspectionComments,
      _directionComments,
      _directionRemarks,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Writes the form to the local store, without ceremony.
  ///
  /// Split from [_save] so the evidence section can persist a draft the
  /// moment a photograph or signature lands: the record must exist for the
  /// evidence to belong to, and the camera is precisely when Android is most
  /// likely to reclaim the process and lose unsaved state.
  Future<void> _persist({required bool completed}) async {
    // The refusal lives on the signature rows, where the tick-box is. Read
    // from there rather than tracked twice, so the record field can never
    // contradict what the evidence section shows.
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined =
        signatures.any((s) => s.role == 'no_client' && s.declined);

    final row = PoultryInspectionsCompanion.insert(
      clientUuid: _clientUuid,
      inspectedAt: _inspectedAt,
      updatedAt: DateTime.now(),
      inspectorUsername: Value(widget.inspectorName),
      status: Value(completed ? 'completed' : 'draft'),
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
      producerTradingName: Value(_producerTradingName.text.trim()),
      meatTypeId: Value(_meatTypeId),
      portionTypeId: Value(_portionTypeId),
      designationClassId: Value(_designationId),
      altDesignationClassId: Value(_altDesignationId),
      productDetails: Value(_productDetails.text.trim()),
      sampleNumber: Value(_sampleNumber.text.trim()),
      gradeId: Value(_gradeId),
      compliantItemIds: Value(_compliant.join(',')),
      restrictedParticularIds: Value(_restricted.join(',')),
      inspectionComments: Value(_inspectionComments.text.trim()),
      directionComments: Value(_directionComments.text.trim()),
      directionRemarks: Value(_directionRemarks.text.trim()),
      directionRemarkTypeId: Value(_remarkTypeId),
      noClientSignaturePresent: Value(declined),
    );

    await widget.repository.saveInspection(row);
  }

  Future<void> _save(_Reference reference, {required bool completed}) async {
    if (completed && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    await _persist(completed: completed);
    if (!mounted) return;
    setState(() => _saving = false);

    final findings = PoultryRules.findings(
      items: reference.checklist,
      compliantItemIds: _compliant,
    );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Grading and Classification',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<_Reference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null || reference.checklist.isEmpty) {
            return _NoRules();
          }
          return _form(reference);
        },
      ),
    );
  }

  Widget _form(_Reference reference) {
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

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Section headings and field captions are the original's, verbatim
          // — including "Classifcation". An inspector working from the paper
          // form should be reading the same words in the same order.
          _section('Inspection Details'),
          _dropdown(
            label: 'Reason for Inspection',
            value: _reasonId,
            items: reference.reasons,
            onChanged: (v) => setState(() => _reasonId = v),
          ),
          _dropdown(
            label: 'Inspection Facility Type',
            value: _locationId,
            items: reference.locations,
            onChanged: (v) => setState(() => _locationId = v),
          ),
          _field(_facilityName, 'New Facility Name', required: true),
          _field(_producerTradingName,
              'Name or Trading Name of New Facility'),
          _field(_facilityAddress, 'Facility Address', lines: 2),
          _field(_facilityTelephone,
              'Facility Primary Contact Telephone Number',
              keyboard: TextInputType.phone),
          _field(_companyReg, 'Company Registration Number'),
          _field(_contactPerson, 'Representative Name'),
          _field(_contactEmail, 'Representative Email Address',
              keyboard: TextInputType.emailAddress),

          _section('Classifcation and Grading Checklist'),
          _dropdown(
            label: 'Poultry Type',
            value: _meatTypeId,
            items: [
              for (final m in reference.meatTypes)
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
          ),
          _dropdown(
            label: 'Portion Type',
            value: _portionTypeId,
            items: reference.portionTypes,
            onChanged: (v) => setState(() => _portionTypeId = v),
          ),
          _dropdown(
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
          ),
          _dropdown(
            label: 'Alternative Class Designation',
            value: _altDesignationId,
            items: reference.altDesignations,
            onChanged: (v) => setState(() => _altDesignationId = v),
          ),
          _field(_productDetails, 'Product Details'),

          _section('Quality Std for Carcasses'),
          _field(_sampleNumber, 'Sample #'),
          _dropdown(
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
            onChanged: (v) => setState(() => _gradeId = v),
          ),

          _section('Restricted Particulars'),
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

          _checklist('Grading', of(PoultryChecklistKind.grading)),
          _checklist('Portions (Reg. 5)', of(PoultryChecklistKind.portion)),
          _checklist('Packing (Reg. 7)', of(PoultryChecklistKind.pack)),

          PoultryEvidenceSection(
            repository: widget.captureRepository,
            recordUuid: _clientUuid,
            kind: 'grading',
            // A draft is persisted the moment evidence lands, so a photograph
            // never points at a record that was never saved.
            onChanged: () => unawaited(_persist(completed: false)),
          ),

          _section('Direction Form'),
          _dropdown(
            label: 'Grading Non-Conformance Remarks',
            value: _remarkTypeId,
            items: reference.remarks,
            onChanged: (v) => setState(() => _remarkTypeId = v),
          ),
          _field(_directionRemarks, 'List of Added Remarks', lines: 2),
          _field(_directionComments, 'Comments/Remarks on Direction', lines: 3),

          _section('Signatures Control'),
          _field(_managerName, 'Authorised Representative name'),
          _field(_managerEmail, 'Representative Email address',
              keyboard: TextInputType.emailAddress),
          _field(_clientEmail, 'Email address #1',
              keyboard: TextInputType.emailAddress),
          _field(_clientEmail2, 'Email address #2',
              keyboard: TextInputType.emailAddress),
          _field(_inspectionComments, 'General Comments', lines: 3),
          // The "No Client Signature is available" control lives in the
          // Signatures block above — one tick-box, not two that can disagree.

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

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
            color: AppColors.ink,
          ),
        ),
      );

  /// A tick-list. The header says what a tick means, because it means the
  /// opposite of what a reader expects from a compliance checklist.
  Widget _checklist(String title, List<PoultryChecklistItemRef> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(title),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Tick where there is NO deviation.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.noticeForeground,
            ),
          ),
        ),
        for (final item in items)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _compliant.contains(item.id),
            title: Text(
              item.description,
              style: const TextStyle(fontSize: 13.5),
            ),
            subtitle: item.regulationReference.isEmpty
                ? null
                : Text(
                    item.regulationReference,
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
            onChanged: (on) => setState(() {
              if (on ?? false) {
                _compliant.add(item.id);
              } else {
                _compliant.remove(item.id);
              }
            }),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int lines = 1,
    TextInputType? keyboard,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          maxLines: lines,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          validator: required
              ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
              : null,
        ),
      );

  Widget _dropdown({
    required String label,
    required int? value,
    required List<PoultryDesignationRef> items,
    required ValueChanged<int?> onChanged,
    bool required = false,
    String? emptyHint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        // alignedDropdown keeps the open menu exactly as wide as the field.
        // Without it, Material inflates the menu 16dp past the field on both
        // sides, which on a full-width field puts it hard against the screen
        // edges.
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButtonFormField<int>(
            initialValue: items.any((i) => i.id == value) ? value : null,
            // Long lists stay usable: 26 class designations in an unbounded
            // menu covers the screen and loses the field it belongs to, so
            // the menu is capped and scrolls inside itself.
            isExpanded: true,
            menuMaxHeight: 360,
            // A card, not a full-bleed sheet: rounded corners and a raised
            // surface tone. The theme default paints the menu in the page's
            // own colour, so in dark mode its edges vanish and the options
            // look like loose text running into the screen corners.
            borderRadius: BorderRadius.circular(12),
            dropdownColor: AppColors.surfaceAlt,
            elevation: 4,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              border: const OutlineInputBorder(),
              isDense: true,
              // Says why the list is empty instead of showing a dead control.
              helperText: items.isEmpty ? emptyHint : null,
            ),
            items: [
              for (final item in items)
                DropdownMenuItem(
                  value: item.id,
                  // Two lines rather than one: several designations and every
                  // direction remark are longer than a handset is wide, and an
                  // ellipsis in the closed field is fine while an ellipsis in
                  // the menu hides which option you are choosing.
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: items.isEmpty ? null : onChanged,
            validator:
                required ? (v) => v == null ? 'Required' : null : null,
          ),
        ),
      );
}

/// Shown when the device holds no poultry rules at all.
class _NoRules extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              'This device has no poultry rules yet.\n'
              'Connect once and sync, then the form works offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      );
}
