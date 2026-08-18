import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../domain/poultry_rules.dart';
import 'poultry_evidence_section.dart';
import 'poultry_form_widgets.dart';

/// Continue with QUID Checklist — pick a set-up, then weigh against it.
class PoultryQuidContinuePage extends StatefulWidget {
  const PoultryQuidContinuePage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<PoultryQuidContinuePage> createState() =>
      _PoultryQuidContinuePageState();
}

class _PoultryQuidContinuePageState extends State<PoultryQuidContinuePage> {
  late Future<List<PoultryQuidInspection>> _open;

  @override
  void initState() {
    super.initState();
    _open = _load();
  }

  Future<List<PoultryQuidInspection>> _load() async {
    final all = await widget.captureRepository
        .quidInspections(widget.user.userName);
    // Only what is still open. A completed checklist is reviewed from
    // Inspection Management, not continued.
    return [
      for (final i in all)
        if (i.status != 'completed') i,
    ];
  }

  void _refresh() => setState(() {
        _open = _load();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Continue with QUID Checklist',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<List<PoultryQuidInspection>>(
        future: _open,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <PoultryQuidInspection>[];
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No QUID checklists are waiting.\n'
                  'Start one from "Setup QUID Checklist".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              for (final row in rows) ...[
                _OpenCard(
                  inspection: row,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => PoultryQuidWeighingForm(
                          repository: widget.repository,
                          captureRepository: widget.captureRepository,
                          inspection: row,
                        ),
                      ),
                    );
                    if (mounted) _refresh();
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OpenCard extends StatelessWidget {
  const _OpenCard({required this.inspection, required this.onTap});

  final PoultryQuidInspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inspection.facilityName.isEmpty
                            ? '(no facility)'
                            : inspection.facilityName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${inspection.injectorName.isEmpty ? "no injector named" : inspection.injectorName}'
                        '   •   ${inspection.inspectedAt.toLocal()}'
                            .split('.')
                            .first,
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
}

/// The weighing half of a QUID checklist.
///
/// Percentages are computed from the masses rather than typed: the original
/// shows the arithmetic, and a figure entered by hand cannot be checked
/// against the readings behind it. Everything is stored as text, exactly as
/// entered, so nothing is rounded on the way in.
class PoultryQuidWeighingForm extends StatefulWidget {
  const PoultryQuidWeighingForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspection,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final PoultryQuidInspection inspection;

  @override
  State<PoultryQuidWeighingForm> createState() =>
      _PoultryQuidWeighingFormState();
}

class _Sample {
  _Sample();
  final carcass = TextEditingController();
  final injector = TextEditingController();
  final initial = TextEditingController();
  final after = TextEditingController();
  final finalMass = TextEditingController();

  /// Pick-up as a percentage of the initial mass, or empty when either mass is
  /// missing or the initial is zero. Never "0%" for "not measured".
  String get pickup {
    final a = double.tryParse(initial.text.trim());
    final b = double.tryParse(after.text.trim());
    if (a == null || b == null || a <= 0) return '';
    return (((b - a) / a) * 100).toStringAsFixed(2);
  }

  void dispose() {
    carcass.dispose();
    injector.dispose();
    initial.dispose();
    after.dispose();
    finalMass.dispose();
  }
}

class _PoultryQuidWeighingFormState extends State<PoultryQuidWeighingForm> {
  final _samples = <_Sample>[];
  late Future<List<PoultryDesignationRef>> _remarks;

  final _clientName = TextEditingController();
  final _iteration = TextEditingController();
  final _documentName = TextEditingController();
  final _deviationComment = TextEditingController();
  final _directionRemarks = TextEditingController();
  final _directionAction = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _generalComments = TextEditingController();

  int? _remarkTypeId;
  bool _waterChillingComplete = false;
  bool _airChillingComplete = false;
  bool _injectorSamplingComplete = false;
  bool _documentVerified = false;
  bool _documentDeviationPresent = false;
  bool _repeatQuid = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _remarks = widget.repository.directionRemarks();
    // Every continuation field comes back from the record, not just the first
    // two — a draft saved here and reopened must not present blank document
    // and direction fields whose save would erase what was already entered.
    final i = widget.inspection;
    _clientName.text = i.clientName;
    _iteration.text = i.iterationNumber;
    _documentName.text = i.documentName;
    _deviationComment.text = i.documentDeviationComment;
    _directionRemarks.text = i.directionRemarks;
    _directionAction.text = i.directionAction;
    _managerName.text = i.managerName;
    _managerEmail.text = i.managerEmail;
    _clientEmail.text = i.clientEmail;
    _clientEmail2.text = i.clientEmail2;
    _generalComments.text = i.generalComments;
    _remarkTypeId = i.directionRemarkTypeId;
    _waterChillingComplete = i.waterChillingComplete;
    _airChillingComplete = i.airChillingComplete;
    _injectorSamplingComplete = i.injectorSamplingComplete;
    _documentVerified = i.documentVerified;
    _documentDeviationPresent = i.documentDeviationPresent;
    _repeatQuid = i.repeatQuidDetermination;
    _restore();
  }

  Future<void> _restore() async {
    final saved = await widget.captureRepository
        .quidSamples(widget.inspection.clientUuid);
    if (!mounted) return;
    setState(() {
      for (final s in saved) {
        final sample = _Sample()
          ..carcass.text = s.carcassNumber
          ..injector.text = s.injectorNumber
          ..initial.text = s.initialMassG
          ..after.text = s.afterMassG
          ..finalMass.text = s.finalMassG;
        _samples.add(sample);
      }
      if (_samples.isEmpty) _samples.add(_Sample());
    });
  }

  @override
  void dispose() {
    for (final s in _samples) {
      s.dispose();
    }
    for (final c in [
      _clientName,
      _iteration,
      _documentName,
      _deviationComment,
      _directionRemarks,
      _directionAction,
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

  /// Mean pick-up across the samples that have one.
  ///
  /// Samples still being entered are skipped rather than counted as zero,
  /// which would drag the average down while the inspector is mid-way through.
  String get _averagePickup {
    final values = [
      for (final s in _samples)
        if (double.tryParse(s.pickup) != null) double.parse(s.pickup),
    ];
    if (values.isEmpty) return '';
    return (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(2);
  }

  Future<void> _save({required bool completed}) async {
    setState(() => _saving = true);

    // The refusal lives on the signature rows, where the tick-box is.
    final signatures = await widget.captureRepository
        .signaturesFor(widget.inspection.clientUuid);
    final declined =
        signatures.any((s) => s.role == 'no_client' && s.declined);

    await widget.captureRepository.replaceQuidSamples(
      widget.inspection.clientUuid,
      [
        for (final s in _samples)
          PoultryQuidSamplesCompanion.insert(
            inspectionUuid: widget.inspection.clientUuid,
            carcassNumber: Value(s.carcass.text.trim()),
            injectorNumber: Value(s.injector.text.trim()),
            initialMassG: Value(s.initial.text.trim()),
            afterMassG: Value(s.after.text.trim()),
            finalMassG: Value(s.finalMass.text.trim()),
            pickupPercent: Value(s.pickup),
          ),
      ],
    );

    await widget.captureRepository.saveQuidInspection(
      PoultryQuidInspectionsCompanion.insert(
        clientUuid: widget.inspection.clientUuid,
        inspectedAt: widget.inspection.inspectedAt,
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspection.inspectorUsername),
        status: Value(completed ? 'completed' : 'draft'),
        // The set-up half is carried through untouched.
        locationId: Value(widget.inspection.locationId),
        reasonId: Value(widget.inspection.reasonId),
        facilityName: Value(widget.inspection.facilityName),
        producerTradingName: Value(widget.inspection.producerTradingName),
        facilityAddress: Value(widget.inspection.facilityAddress),
        facilityTelephone: Value(widget.inspection.facilityTelephone),
        companyRegNumber: Value(widget.inspection.companyRegNumber),
        contactPerson: Value(widget.inspection.contactPerson),
        contactPersonEmail: Value(widget.inspection.contactPersonEmail),
        productDetails: Value(widget.inspection.productDetails),
        isWaterChilled: Value(widget.inspection.isWaterChilled),
        isWholeCarcass: Value(widget.inspection.isWholeCarcass),
        injectorName: Value(widget.inspection.injectorName),
        isRegulatedStandard: Value(widget.inspection.isRegulatedStandard),
        dispensationQuidPercent:
            Value(widget.inspection.dispensationQuidPercent),
        setupComplete: Value(widget.inspection.setupComplete),
        clientName: Value(_clientName.text.trim()),
        iterationNumber: Value(_iteration.text.trim()),
        averageInjectorPickup: Value(_averagePickup),
        waterChillingComplete: Value(_waterChillingComplete),
        airChillingComplete: Value(_airChillingComplete),
        injectorSamplingComplete: Value(_injectorSamplingComplete),
        quidPercent: Value(_averagePickup),
        quidDeterminationComplete: Value(completed),
        repeatQuidDetermination: Value(_repeatQuid),
        documentName: Value(_documentName.text.trim()),
        documentVerified: Value(_documentVerified),
        documentDeviationPresent: Value(_documentDeviationPresent),
        documentDeviationComment: Value(_deviationComment.text.trim()),
        directionRemarkTypeId: Value(_remarkTypeId),
        directionRemarks: Value(_directionRemarks.text.trim()),
        directionAction: Value(_directionAction.text.trim()),
        managerName: Value(_managerName.text.trim()),
        managerEmail: Value(_managerEmail.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        clientEmail2: Value(_clientEmail2.text.trim()),
        noClientSignaturePresent: Value(declined),
        generalComments: Value(_generalComments.text.trim()),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'QUID Determination',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<List<PoultryDesignationRef>>(
        future: _remarks,
        builder: (context, snap) {
          final remarks = snap.data ?? const <PoultryDesignationRef>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                widget.inspection.facilityName.isEmpty
                    ? '(no facility)'
                    : widget.inspection.facilityName,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              Text(
                'Injector: ${widget.inspection.injectorName.isEmpty ? "—" : widget.inspection.injectorName}'
                '   •   ${widget.inspection.isWaterChilled ? "Water chilled" : "Air chilled"}'
                '   •   ${widget.inspection.isWholeCarcass ? "Whole carcass" : "Portions"}',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),

              poultrySection('Inspection'),
              poultryField(_clientName, 'Client Name'),
              poultryField(_iteration, 'Iteration #'),

              poultrySection('Carcass sampling'),
              for (var i = 0; i < _samples.length; i++) _sampleCard(i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _samples.add(_Sample())),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add carcass #${_samples.length + 1}'),
                ),
              ),

              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Average pick up',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      _averagePickup.isEmpty ? '—' : '$_averagePickup %',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),

              poultrySwitch(
                label: 'Water Chilling for Samples Complete',
                value: _waterChillingComplete,
                onChanged: (v) => setState(() => _waterChillingComplete = v),
              ),
              poultrySwitch(
                label: 'Air Chilling for Samples Complete',
                value: _airChillingComplete,
                onChanged: (v) => setState(() => _airChillingComplete = v),
              ),
              poultrySwitch(
                label: 'Injector(s) Sampling Complete',
                value: _injectorSamplingComplete,
                onChanged: (v) =>
                    setState(() => _injectorSamplingComplete = v),
              ),
              poultrySwitch(
                label: 'Repeat QUID Determine Vertification',
                value: _repeatQuid,
                onChanged: (v) => setState(() => _repeatQuid = v),
              ),

              poultrySection('Document verification'),
              poultryField(_documentName, 'Name/Document Number'),
              poultrySwitch(
                label: 'Document Verified',
                value: _documentVerified,
                onChanged: (v) => setState(() => _documentVerified = v),
              ),
              poultrySwitch(
                label: 'Deviation(s) Present',
                value: _documentDeviationPresent,
                onChanged: (v) =>
                    setState(() => _documentDeviationPresent = v),
              ),
              if (_documentDeviationPresent)
                poultryField(_deviationComment, 'Deviation Comment', lines: 2),

              // The QUID record already exists on disk (set-up saved it), so
              // evidence always has a parent — no draft persist needed here.
              PoultryEvidenceSection(
                repository: widget.captureRepository,
                recordUuid: widget.inspection.clientUuid,
                kind: 'quid',
              ),

              poultrySection('Direction Form'),
              poultryDropdown(
                label: 'QUID Non-Conformance Remarks',
                value: _remarkTypeId,
                items: remarks,
                onChanged: (v) => setState(() => _remarkTypeId = v),
              ),
              poultryField(_directionRemarks, 'List of Added Remarks',
                  lines: 2),
              poultryField(
                  _directionAction, 'Batch No. and/or Quantity Removed'),

              poultrySection('Signatures Control'),
              poultryField(_managerName, 'Authorised Representative name'),
              poultryField(
                _managerEmail,
                'Representative Email address',
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
              // Signatures block above — one tick-box, not two that can
              // disagree.

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => _save(completed: false),
                        child: const Text('Save draft'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed:
                            _saving ? null : () => _save(completed: true),
                        child: Text(_saving ? 'Saving…' : 'Complete'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sampleCard(int index) {
    final s = _samples[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
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
                  'Carcass ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                s.pickup.isEmpty ? '—' : '${s.pickup} %',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandTeal,
                ),
              ),
              if (_samples.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _samples.removeAt(index).dispose();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: poultryField(s.carcass, 'Carcass #')),
              const SizedBox(width: 10),
              Expanded(child: poultryField(s.injector, 'Injector Number')),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: poultryField(
                  s.initial,
                  'Initial Mass (g)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // Recomputes the pick-up as the masses are typed, so the
                  // inspector sees the figure they are about to record.
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: poultryField(
                  s.after,
                  'After Mass (g)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          poultryField(
            s.finalMass,
            'Final Mass (g)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
  }
}
