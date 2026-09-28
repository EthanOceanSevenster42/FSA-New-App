import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/services/in_app_camera.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../domain/poultry_rules.dart';
import '../domain/quid_determination.dart';
import '../domain/quid_flow.dart';
import 'poultry_evidence_section.dart';
import 'poultry_form_widgets.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/picker_menu_field.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../../eggs/presentation/date_field.dart';

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
    final all =
        await widget.captureRepository.quidInspections(widget.user.userName);
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
      body: ContentWidth(
          child: FutureBuilder<List<PoultryQuidInspection>>(
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
      )),
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

/// The weighing half of a QUID checklist, walked the way the original walks
/// it: one carcass at a time, one stage at a time.
///
/// Chilling, then the injector, then the determination of QUID — each stage
/// opens when the one before it is marked complete, and closing a stage is
/// checked (five carcasses, per injector where it matters) and confirmed.
/// A failure on the first round means the determination is weighed again;
/// on the second, a rejection. The rules are in `quid_flow.dart`, where they
/// are tested on their own.
///
/// Percentages are worked out from the masses rather than typed, and every
/// mass is stored exactly as entered.
class PoultryQuidWeighingForm extends StatefulWidget {
  const PoultryQuidWeighingForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspection,
    this.takePhoto = capturePhoto,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final PoultryQuidInspection inspection;

  /// Opens the camera for a verification document's photograph and returns
  /// the file it took, or null when the inspector backed out. Replaced in
  /// tests, where there is no camera.
  final Future<String?> Function(BuildContext context, {required String title})
      takePhoto;

  @override
  State<PoultryQuidWeighingForm> createState() =>
      _PoultryQuidWeighingFormState();
}

class _Sample {
  _Sample(this.iteration);

  /// The round this carcass was weighed in.
  final int iteration;

  /// Stage 1: the carcass on the way in, and off the water chiller.
  final initial = TextEditingController();
  final waterFinal = TextEditingController();

  /// Stage 2: which injector ran it, and the carcass on and off it.
  int? assignedInjector;
  final beforeMass = TextEditingController();
  final injectorAfter = TextEditingController();

  /// Stage 3: the carcass off the process.
  final quidFinal = TextEditingController();

  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  bool get hasInitial => (_num(initial) ?? 0) > 0;

  bool get isEmpty =>
      initial.text.trim().isEmpty &&
      waterFinal.text.trim().isEmpty &&
      beforeMass.text.trim().isEmpty &&
      injectorAfter.text.trim().isEmpty &&
      quidFinal.text.trim().isEmpty &&
      assignedInjector == null;

  /// "The entered water chilled weight value cannot be less than that of
  /// the initial weight."
  String? get waterFinalError {
    final a = _num(initial);
    final b = _num(waterFinal);
    if (a == null || b == null) return null;
    return b < a
        ? 'The entered water chilled weight value cannot be less than that of '
            'the initial weight.'
        : null;
  }

  /// "The Value cannot be less than the Before Mass".
  String? get injectorAfterError {
    final a = _num(beforeMass);
    final b = _num(injectorAfter);
    if (a == null || b == null) return null;
    return b <= a ? 'The Value cannot be less than the Before Mass' : null;
  }

  /// "The Value cannot be less than the inital sample weight."
  String? get quidFinalError {
    final a = _num(initial);
    final b = _num(quidFinal);
    if (a == null || b == null) return null;
    return b < a
        ? 'The Value cannot be less than the initial sample weight.'
        : null;
  }

  /// Water pick-up over the mass off the chiller, three decimals.
  String get pickup => waterFinalError != null
      ? ''
      : quidPercentOf(_num(initial), _num(waterFinal));

  String get gain {
    if (injectorAfterError != null) return '';
    final a = _num(beforeMass);
    final b = _num(injectorAfter);
    if (a == null || b == null) return '';
    return (b - a).toStringAsFixed(3);
  }

  /// "Sample Injector Rate (%)": the gain over the mass off the injector.
  String get injectorRate => injectorAfterError != null
      ? ''
      : quidPercentOf(_num(beforeMass), _num(injectorAfter));

  String get quidGain {
    if (quidFinalError != null) return '';
    final a = _num(initial);
    final b = _num(quidFinal);
    if (a == null || b == null) return '';
    return (b - a).toStringAsFixed(3);
  }

  /// This carcass's QUID: (final − initial) / final × 100.
  String get quidPercent => quidFinalError != null
      ? ''
      : quidPercentOf(_num(initial), _num(quidFinal));

  QuidStageSample get forRules => (
        initial: initial.text.trim(),
        waterFinal: waterFinalError == null ? waterFinal.text.trim() : '',
        injector: assignedInjector,
        injectorAfter:
            injectorAfterError == null ? injectorAfter.text.trim() : '',
        quidPercent: quidPercent,
      );

  void dispose() {
    initial.dispose();
    waterFinal.dispose();
    beforeMass.dispose();
    injectorAfter.dispose();
    quidFinal.dispose();
  }
}

class _PoultryQuidWeighingFormState extends State<PoultryQuidWeighingForm> {
  /// Every carcass, every round. The screen works on [_round].
  final _samples = <_Sample>[];
  late Future<List<PoultryDesignationRef>> _remarks;

  final _directionRemarks = TextEditingController();
  final _directionAction = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _generalComments = TextEditingController();

  // Verification of Records — the entry being typed, and the list.
  final _documentName = TextEditingController();
  final _deviationComment = TextEditingController();
  DateTime? _documentDate;
  bool _documentVerified = false;
  bool _documentDeviationPresent = false;
  final _records = <QuidVerificationRecord>[];

  /// The photograph taken for the document being typed, until Add puts it
  /// on the list. Add waits for it, as the original's does.
  String? _documentPhotoPath;

  int? _remarkTypeId;
  DateTime? _correctBy;

  /// The round being weighed: 1, or 2 when repeated.
  int _iteration = 1;

  // Where the current round stands.
  bool _chillingComplete = false;
  bool _injectorComplete = false;
  bool _determinationComplete = false;

  /// Set when the weighing ended in a rejection, with the reason.
  bool _directionRequired = false;
  String _directionReason = '';

  /// FSA-SOP-APS-001 Annexure C: a QUID deviation is an immediate seizure,
  /// so the question is put when the weighing ends in a rejection.
  bool _seizureAsked = false;
  SeizureDecision? _seizureDecision;

  List<PoultryQuidInjector> _injectors = const [];

  /// Which carcass of the round is in front of the inspector, 0-based.
  int _current = 0;

  bool _saving = false;

  /// False until the record has been read back off disk: the samples are
  /// replaced wholesale on save, and saving before they land would write
  /// an empty list over carcasses already weighed.
  bool _restored = false;

  /// The required fields a refused Next, Add or Submit flagged, so the page
  /// can take the inspector to the first and mark each red.
  final _missing = MissingFields();

  bool get _isWater => widget.inspection.isWaterChilled;
  bool get _inVisit => widget.inspection.visitUuid.trim().isNotEmpty;

  QuidStage get _stage => quidStage(
        chillingComplete: _chillingComplete,
        injectorComplete: _injectorComplete,
        determinationComplete: _determinationComplete,
      );

  List<_Sample> get _round => [
        for (final s in _samples)
          if (s.iteration == _iteration) s,
      ];

  _Sample get _sample {
    final round = _round;
    return round[_current.clamp(0, round.length - 1)];
  }

  List<int> get _injectorPositions => [for (final i in _injectors) i.position];

  @override
  void initState() {
    super.initState();
    _remarks = widget.repository.directionRemarks();
    final i = widget.inspection;
    _directionRemarks.text = i.directionRemarks;
    _directionAction.text = i.directionAction;
    _managerName.text = i.managerName;
    _managerEmail.text = i.managerEmail;
    _clientEmail.text = i.clientEmail;
    _clientEmail2.text = i.clientEmail2;
    _generalComments.text = i.generalComments;
    _remarkTypeId = i.directionRemarkTypeId;
    _correctBy = i.correctByDate;
    _iteration = int.tryParse(i.iterationNumber.trim()) ?? 1;
    if (_iteration < 1) _iteration = 1;
    _chillingComplete =
        _isWater ? i.waterChillingComplete : i.airChillingComplete;
    _injectorComplete = i.injectorSamplingComplete;
    _determinationComplete = i.quidDeterminationComplete;
    _directionRequired = i.directionRequired;
    _directionReason = i.directionReason;
    _seizureDecision = SeizureDecision.of(i.seizureDecision);
    _seizureAsked = _seizureDecision != null;
    // The annexure gives a QUID deviation no period: the rejection runs
    // from the inspection date.
    if (_directionRequired) {
      _correctBy ??=
          DateTime(i.inspectedAt.year, i.inspectedAt.month, i.inspectedAt.day);
    }
    _records.addAll(QuidVerificationRecord.decode(i.verificationRecordsJson));
    // The record being verified is usually today's; the original's date
    // picker opens on today and goes back to it after every Add.
    _documentDate = DateTime.now();
    // A record from before the list kept its one document in these fields.
    if (_records.isEmpty && i.documentName.trim().isNotEmpty) {
      _records.add(QuidVerificationRecord(
        date: i.documentDate,
        documentName: i.documentName,
        verified: i.documentVerified,
        deviationPresent: i.documentDeviationPresent,
        deviationComment: i.documentDeviationComment,
      ));
    }
    _restore();
  }

  Future<void> _restore() async {
    // The injector list first: assignments are checked against it.
    final injectors = await widget.captureRepository
        .quidInjectors(widget.inspection.clientUuid);
    if (!mounted) return;
    _injectors = injectors;
    final saved = await widget.captureRepository
        .quidSamples(widget.inspection.clientUuid);
    if (!mounted) return;
    setState(() {
      for (final s in saved) {
        final assigned = int.tryParse(s.assignedInjector);
        _samples.add(_Sample(s.iteration)
          ..initial.text = s.initialMassG
          ..waterFinal.text = s.finalMassG
          ..assignedInjector =
              _injectorPositions.contains(assigned) ? assigned : null
          ..beforeMass.text = s.beforeMassG
          ..injectorAfter.text = s.injectorAfterMassG
          ..quidFinal.text = s.quidFinalMassG);
      }
      if (_round.isEmpty) _samples.add(_Sample(_iteration));
      _restored = true;
    });
  }

  @override
  void dispose() {
    for (final s in _samples) {
      s.dispose();
    }
    for (final c in [
      _directionRemarks,
      _directionAction,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _generalComments,
      _documentName,
      _deviationComment,
    ]) {
      c.dispose();
    }
    _missing.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ figures

  String get _averageWaterPickup =>
      quidMean([for (final s in _round) s.pickup]);
  String get _averageInjectorRate =>
      quidMean([for (final s in _round) s.injectorRate]);
  String get _averageQuid => quidMean([for (final s in _round) s.quidPercent]);

  List<QuidInjectorVerdict> get _verdicts => quidVerdicts(
        injectors: [
          for (final i in _injectors)
            (position: i.position, name: i.name, quidPercent: i.quidPercent),
        ],
        weighings: [
          for (final s in _round)
            (assignedInjector: s.assignedInjector, quidPercent: s.quidPercent),
        ],
        isWholeCarcass: widget.inspection.isWholeCarcass,
      );

  String get _clientForDisplay {
    final client = widget.inspection.clientName.trim();
    return client.isNotEmpty ? client : widget.inspection.facilityName.trim();
  }

  // ------------------------------------------------------------ dialogs

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

  Future<bool> _confirm(String title, String message,
      {required String yes, required String no}) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(no),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return answer == true;
  }

  // ------------------------------------------------------------ carcasses

  Future<void> _previous() async {
    if (_current <= 0) {
      await _alert('Min. Sample reached', 'Minimum Sample number reached.');
      return;
    }
    _missing.clear();
    setState(() => _current--);
  }

  Future<void> _next() async {
    final round = _round;
    if (_stage == QuidStage.chilling) {
      if (!_sample.hasInitial) {
        await _alert('Incomplete Input', 'No Initial Mass has been inputted.');
        if (!mounted) return;
        await _missing.flag(
          context,
          const ['initialMass'],
          stillMissing: (_) =>
              _stage == QuidStage.chilling && !_sample.hasInitial,
        );
        return;
      }
      _missing.clear();
      if (_current >= round.length - 1) {
        // The next carcass of the set.
        setState(() {
          _samples.add(_Sample(_iteration));
          _current = round.length;
        });
        return;
      }
    } else if (_current >= round.length - 1) {
      await _alert(
          'No New Samples',
          'The current set of conditions has made the inclusion or adding of '
              'new samples no longer permissible.');
      return;
    }
    setState(() => _current++);
  }

  // ------------------------------------------------------------ stages

  Future<void> _closeChilling(bool on) async {
    if (!on || _chillingComplete) return;
    final round = [for (final s in _round) s.forRules];
    final blocked = quidChillingBlocked(round, isWaterChilled: _isWater);
    if (blocked != null) {
      await _alert('Insufficient Sample Size', blocked);
      return;
    }
    final ok = await _confirm(
      'Confirm Completion',
      'Please confirm that all the necessary samples for the '
          '${_isWater ? 'water' : 'air'} chilling method has been captured.',
      yes: 'Confirm',
      no: 'Review/Edit',
    );
    if (!ok || !mounted) return;

    if (_isWater) {
      final average = quidNumber(_averageWaterPickup) ?? 0;
      if (average > quidMaxWaterPickupPercent) {
        switch (quidOnFailure(_iteration)) {
          case QuidFailureStep.repeat:
            await _alert(
                'Redo Inspection',
                'The average Water Chilling Pickup percentage exceeds allowed '
                    'value as per APS regulation. A new sample set and new '
                    'inspection process is required.');
            await _startNewRound();
          case QuidFailureStep.reject:
            await _alert(
                'Rejection Issued',
                'A rejection will now be issued, as no further QUID '
                    'determination is permitted.');
            setState(() {
              _chillingComplete = true;
              _injectorComplete = true;
              _determinationComplete = true;
              _directionRequired = true;
              _directionReason = 'Water chilling pick-up averaged '
                  '$_averageWaterPickup% over ${_round.where((s) => s.pickup.isNotEmpty).length} '
                  'carcasses on the second sample set, above the '
                  '${quidMaxWaterPickupPercent.toStringAsFixed(0)}% allowed.';
              _correctBy = _rectifyImmediately();
            });
            // On the record before the question is put, so a process
            // reclaimed mid-question still holds the rejection.
            await _persist(completed: false);
            await _askAboutQuidSeizure();
        }
        return;
      }
    }
    setState(() {
      _chillingComplete = true;
      _current = 0;
    });
    await _persist(completed: false);
  }

  Future<void> _closeInjector(bool on) async {
    if (!on || _injectorComplete) return;
    final ok = await _confirm(
      'Confirm Injector Sampling Complete',
      'Please that all the sampling allocation to the current injector(s) has '
          'been completed.',
      yes: 'Confirm to QUID Determination',
      no: 'Return to Injector Sampling',
    );
    if (!ok || !mounted) return;
    final blocked = quidInjectorBlocked(
        [for (final s in _round) s.forRules], _injectorPositions);
    if (blocked != null) {
      await _alert('Incomplete min. sample set', blocked);
      return;
    }
    setState(() {
      _injectorComplete = true;
      _current = 0;
    });
    await _persist(completed: false);
  }

  Future<void> _closeDetermination(bool on) async {
    if (!on || _determinationComplete) return;
    final blocked = quidDeterminationBlocked(
        [for (final s in _round) s.forRules], _injectorPositions);
    if (blocked != null) {
      await _alert('Insufficient QUID Samples', blocked);
      return;
    }
    final ok = await _confirm(
      'Confirm QUID Sampling Complete',
      'Confirm that the sampling process for the QUID Determination is '
          'complete.',
      yes: 'Proceed',
      no: 'Review/Edit',
    );
    if (!ok || !mounted) return;
    final failing = [
      for (final v in _verdicts)
        if (v.passes == false) v,
    ];
    if (failing.isNotEmpty) {
      switch (quidOnFailure(_iteration)) {
        case QuidFailureStep.repeat:
          await _alert(
              'QUID Deviation Present',
              'A QUID deviation was found on one or more of the injectors. '
                  'Repeat of the QUID Determination Process must be done.');
          await _startNewRound();
          return;
        case QuidFailureStep.reject:
          setState(() {
            _directionRequired = true;
            _directionReason = [
              for (final v in failing)
                '${v.name.isEmpty ? 'Injector ${v.position}' : v.name}: '
                    'average QUID ${v.averagePercent}% exceeds the permitted '
                    '${v.limitPercent.toStringAsFixed(3)}% over '
                    '${v.sampleCount} carcasses, on the second determination.',
            ].join('\n');
            _correctBy = _rectifyImmediately();
          });
      }
    }
    if (!mounted) return;
    setState(() => _determinationComplete = true);
    await _persist(completed: false);
    if (_directionRequired) await _askAboutQuidSeizure();
  }

  Future<void> _repeat(bool on) async {
    if (!on) return;
    if (_iteration >= quidMaxIterations) {
      await _alert('Maximum Iteration Reached',
          'No further repeat iterations of the process is permitted!.');
      return;
    }
    final ok = await _confirm(
      'Repeat QUID Process',
      'Confirm that a new iteration of this QUID Determination Inspection '
          'will be performed. The current QUID results will be saved.',
      yes: 'Proceed',
      no: 'Review/Edit',
    );
    if (!ok || !mounted) return;
    await _startNewRound();
  }

  /// Today, as a date: FSA-SOP-APS-001 Annexure C gives a QUID deviation
  /// no rectification period.
  static DateTime _rectifyImmediately() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Puts the seizure question, once, when the weighing ends in a
  /// rejection: the annexure seizes on a QUID deviation, and the decision
  /// is the inspector's to take on the premises.
  Future<void> _askAboutQuidSeizure() async {
    if (_seizureAsked || !mounted) return;
    _seizureAsked = true;
    final answer = await askAboutSeizure(
      context,
      reason: 'Seizure under FSA-SOP-APS-001 Annexure C: the consignment '
          'does not comply with the absorbed moisture or formulated solution '
          'limits (Reg. 4(2), 4(9), 5(4) and 14).\n\n$_directionReason',
    );
    if (answer == null || !mounted) {
      _seizureAsked = false;
      return;
    }
    setState(() => _seizureDecision = answer);
    // Seized: the Annexure E sheet is drawn up here, on the premises.
    if (answer == SeizureDecision.seize) {
      final i = widget.inspection;
      await recordSeizure(
        context,
        database: widget.repository.database,
        draft: SeizureDraft(
          recordUuid: i.clientUuid,
          recordKind: 'quid',
          visitUuid: i.visitUuid,
          inspectorUsername: i.inspectorUsername,
          natureOfDeviation: 'Seizure under FSA-SOP-APS-001 Annexure C: the '
              'consignment does not comply with the absorbed moisture or '
              'formulated solution limits. $_directionReason',
          regulation: 'R.946 of 27 March 1992 — Reg. 4(2), 4(9), 5(4), 14',
          clientName: i.facilityName,
          clientAddress: i.facilityAddress,
          clientTelephone: i.facilityTelephone,
          clientEmail: i.contactPersonEmail,
          productName: i.productDetails,
          receiverName: _managerName.text,
        ),
      );
      if (!mounted) return;
    }
    await _persist(completed: false);
  }

  /// The seizure decision, once taken, stated on the form.
  Widget _seizureNotice() {
    final seized = _seizureDecision == SeizureDecision.seize;
    final colour = seized ? AppColors.brandRed : AppColors.inkSoft;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        seized
            ? 'Seizure under section 8 of the APS Act recorded for this '
                'consignment (FSA-SOP-APS-001 Annexure C).'
            : 'Seizure declined on the premises; the rejection stands and is '
                'to be put right immediately.',
        style: TextStyle(color: colour, fontSize: 13, height: 1.4),
      ),
    );
  }

  /// A new sample set: the round before stays on the record.
  Future<void> _startNewRound() async {
    setState(() {
      _iteration++;
      _chillingComplete = false;
      _injectorComplete = false;
      _determinationComplete = false;
      _directionRequired = false;
      _directionReason = '';
      _seizureDecision = null;
      _seizureAsked = false;
      _samples.add(_Sample(_iteration));
      _current = 0;
    });
    await _persist(completed: false);
  }

  // ------------------------------------------------------------ records

  /// "Take Photo" on the verification block: one photograph of the document
  /// named in the box, kept against the record as a `document` photo.
  Future<void> _takeDocumentPhoto() async {
    final name = _documentName.text.trim();
    if (name.isEmpty) {
      await _alert('Document particulars',
          'Give the name or number of the document before photographing it.');
      return;
    }
    final String? shot;
    try {
      shot = await widget.takePhoto(context, title: 'Document photograph');
    } on Object catch (e) {
      if (mounted) {
        await _alert('Photo/Camera error',
            'An error was encountered with the photo. Please retry again. $e');
      }
      return;
    }
    if (shot == null || !mounted) return;
    try {
      final storage = await PhotoStorage.instance();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await storage.adopt(
        File(shot),
        name: 'poultry_${widget.inspection.clientUuid}_document_$stamp.jpg',
      );
      // Retaken before Add: the earlier shot of this document goes.
      await _dropPendingDocumentPhoto();
      await widget.captureRepository.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: widget.inspection.clientUuid,
          kind: 'document',
          filePath: path,
          caption: Value('Verification record: $name'),
          capturedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() => _documentPhotoPath = path);
    } on Object catch (e) {
      if (mounted) {
        await _alert('Photo/Camera error', 'The photo could not be saved. $e');
      }
    }
  }

  /// Removes the photograph taken for the document still being typed.
  Future<void> _dropPendingDocumentPhoto() async {
    final pending = _documentPhotoPath;
    if (pending == null) return;
    for (final p in await widget.captureRepository
        .photosFor(widget.inspection.clientUuid, kind: 'document')) {
      if (p.filePath == pending) await widget.captureRepository.deletePhoto(p.id);
    }
    _documentPhotoPath = null;
  }

  Future<void> _addRecord() async {
    if (_documentName.text.trim().isEmpty) {
      await _alert('Document particulars',
          'Give the name or number of the document being verified.');
      if (!mounted) return;
      await _missing.flag(
        context,
        const ['documentName'],
        stillMissing: (_) => _documentName.text.trim().isEmpty,
      );
      return;
    }
    // The original enables Add only once the document has been
    // photographed.
    if (_documentPhotoPath == null) {
      await _alert('Document photograph',
          'Take a photograph of the document before adding it to the list.');
      if (!mounted) return;
      await _missing.flag(
        context,
        const ['documentPhoto'],
        stillMissing: (_) => _documentPhotoPath == null,
      );
      return;
    }
    _missing.clear();
    final ok = await _confirm(
      'Add Document particulars',
      'Confirm this current Document Vertification particulars is correct.',
      yes: 'Proceed',
      no: 'Edit/Review',
    );
    if (!ok || !mounted) return;
    setState(() {
      _records.add(QuidVerificationRecord(
        date: _documentDate,
        documentName: _documentName.text.trim(),
        verified: _documentVerified,
        deviationPresent: _documentDeviationPresent,
        deviationComment:
            _documentDeviationPresent ? _deviationComment.text.trim() : '',
        photoPath: _documentPhotoPath ?? '',
      ));
      _documentName.clear();
      _deviationComment.clear();
      _documentDate = DateTime.now();
      _documentVerified = false;
      _documentDeviationPresent = false;
      _documentPhotoPath = null;
    });
  }

  Future<void> _clearRecords() async {
    if (_records.isEmpty && _documentPhotoPath == null) return;
    final ok = await _confirm(
        'Clear List', 'Remove every document from the verification list?',
        yes: 'Clear', no: 'Cancel');
    if (!ok || !mounted) return;
    // Their photographs go with them, as the original empties its document
    // photo list.
    for (final p in await widget.captureRepository
        .photosFor(widget.inspection.clientUuid, kind: 'document')) {
      await widget.captureRepository.deletePhoto(p.id);
    }
    if (!mounted) return;
    setState(() {
      _records.clear();
      _documentPhotoPath = null;
      _documentDate = DateTime.now();
    });
  }

  /// "Abandon Checklist": the determination and everything captured for it
  /// are removed, as the original invalidates its sample and set-up data.
  Future<void> _abandon() async {
    final ok = await _confirm(
      'Abandon QUID Determination',
      'Confirm that the sampling process for this QUID Determination '
          'inspection is to be stopped, cancelled or abandoned. Everything '
          'captured for it — the set-up, the carcasses weighed, the records '
          'and the photographs — will be removed.',
      yes: 'Proceed to abandon',
      no: 'Return to inspection',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.captureRepository
          .deleteQuidInspection(widget.inspection.clientUuid);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _alert('Deletion Data Error',
          'Unable to delete the QUID data. Please try again. $e');
      return;
    }
    if (!mounted) return;
    await _alert(
        'Removed Data',
        'All captured data relating to this particular QUID Determination '
            'inspection has been invalidated for use.');
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _addRemark(List<PoultryDesignationRef> remarks) {
    final chosen = remarks.where((r) => r.id == _remarkTypeId).firstOrNull;
    if (chosen == null) return;
    final line = '• ${chosen.name}';
    final lines = _directionRemarks.text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.contains(line)) return;
    setState(() {
      _directionRemarks.text = [...lines, line].join('\n');
    });
  }

  // ------------------------------------------------------------ saving

  String _total(String Function(_Sample) of) {
    final values = [
      for (final s in _round)
        if (quidNumber(of(s)) != null) quidNumber(of(s))!,
    ];
    if (values.isEmpty) return '';
    return values.reduce((a, b) => a + b).toStringAsFixed(3);
  }

  Future<void> _persist({required bool completed}) async {
    final signatures = await widget.captureRepository
        .signaturesFor(widget.inspection.clientUuid);
    final declined = signatures.any((s) => s.role == 'no_client' && s.declined);
    final i = widget.inspection;

    // A blank carcass the Next button opened and nothing was typed into is
    // not a carcass.
    final kept = [
      for (final s in _samples)
        if (!s.isEmpty) s,
    ];
    final numberInRound = <int, int>{};
    await widget.captureRepository.replaceQuidSamples(i.clientUuid, [
      for (final s in kept)
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: i.clientUuid,
          iteration: Value(s.iteration),
          carcassNumber: Value(
              '${numberInRound.update(s.iteration, (n) => n + 1, ifAbsent: () => 1)}'),
          injectorNumber: Value(_injectors
                  .where((x) => x.position == s.assignedInjector)
                  .firstOrNull
                  ?.name ??
              ''),
          initialMassG: Value(s.initial.text.trim()),
          finalMassG: Value(s.waterFinal.text.trim()),
          pickupPercent: Value(s.pickup),
          beforeMassG: Value(s.beforeMass.text.trim()),
          injectorAfterMassG: Value(s.injectorAfter.text.trim()),
          gainG: Value(s.gain),
          injectorRatePercent: Value(s.injectorRate),
          quidFinalMassG: Value(s.quidFinal.text.trim()),
          quidGainG: Value(s.quidGain),
          quidPercent: Value(s.quidPercent),
          assignedInjector: Value(s.assignedInjector?.toString() ?? ''),
        ),
    ]);

    final first = _records.firstOrNull;
    await widget.captureRepository.saveQuidInspection(
      PoultryQuidInspectionsCompanion.insert(
        clientUuid: i.clientUuid,
        inspectedAt: i.inspectedAt,
        updatedAt: DateTime.now(),
        inspectorUsername: Value(i.inspectorUsername),
        status: Value(completed ? (_inVisit ? 'ready' : 'completed') : 'draft'),
        // The set-up half is carried through untouched — the visit link
        // above all, or the record falls off the visit it belongs to.
        visitUuid: Value(i.visitUuid),
        locationId: Value(i.locationId),
        reasonId: Value(i.reasonId),
        facilityName: Value(i.facilityName),
        producerTradingName: Value(i.producerTradingName),
        facilityAddress: Value(i.facilityAddress),
        facilityTelephone: Value(i.facilityTelephone),
        companyRegNumber: Value(i.companyRegNumber),
        contactPerson: Value(i.contactPerson),
        contactPersonEmail: Value(i.contactPersonEmail),
        productDetails: Value(i.productDetails),
        isWaterChilled: Value(i.isWaterChilled),
        isWholeCarcass: Value(i.isWholeCarcass),
        injectorName: Value(i.injectorName),
        isRegulatedStandard: Value(i.isRegulatedStandard),
        dispensationQuidPercent: Value(i.dispensationQuidPercent),
        setupComplete: Value(i.setupComplete),
        clientName: Value(_clientForDisplay),
        iterationNumber: Value('$_iteration'),
        averageWaterChillPickup: Value(_isWater ? _averageWaterPickup : ''),
        averageInjectorPickup: Value(_averageInjectorRate),
        quidInitialMassG: Value(_total((s) => s.initial.text.trim())),
        quidAfterMassG: Value(_total((s) => s.quidFinal.text.trim())),
        quidGainMassG: Value(_total((s) => s.quidGain)),
        waterChillingComplete: Value(_isWater && _chillingComplete),
        airChillingComplete: Value(!_isWater && _chillingComplete),
        injectorSamplingComplete: Value(_injectorComplete),
        quidPercent: Value(_averageQuid),
        quidDeterminationComplete: Value(_determinationComplete),
        repeatQuidDetermination: Value(_iteration > 1),
        documentDate: Value(first?.date),
        documentName: Value(first?.documentName ?? ''),
        documentVerified: Value(first?.verified ?? false),
        documentDeviationPresent: Value(first?.deviationPresent ?? false),
        documentDeviationComment: Value(first?.deviationComment ?? ''),
        verificationRecordsJson: Value(QuidVerificationRecord.encode(_records)),
        directionRequired: Value(_directionRequired),
        directionReason: Value(_directionReason),
        correctByDate: Value(_directionRequired ? _correctBy : null),
        directionRemarkTypeId: Value(_directionRequired ? _remarkTypeId : null),
        directionRemarks:
            Value(_directionRequired ? _directionRemarks.text.trim() : ''),
        directionAction:
            Value(_directionRequired ? _directionAction.text.trim() : ''),
        seizureDecision: Value(_seizureDecision?.stored ?? ''),
        managerName: Value(_managerName.text.trim()),
        managerEmail: Value(_managerEmail.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        clientEmail2: Value(_clientEmail2.text.trim()),
        noClientSignaturePresent: Value(declined),
        generalComments: Value(_generalComments.text.trim()),
      ),
    );
  }

  /// The completion switch of the stage [stage], as a [_missing] id.
  static String _stageSwitchId(QuidStage stage) => switch (stage) {
        QuidStage.chilling => 'chillingComplete',
        QuidStage.injector => 'injectorComplete',
        _ => 'determinationComplete',
      };

  /// Takes the red off the rejection photographs once enough are taken.
  Future<void> _recheckRejectionPhotos() async {
    if (!_missing.flagged.contains('rejectionPhotos')) return;
    final taken = (await widget.captureRepository
            .photosFor(widget.inspection.clientUuid, kind: 'quid'))
        .length;
    if (mounted && !quidRejectionPhotosOutstanding(taken)) _missing.clear();
  }

  /// Wraps a required field so a refused save can scroll to it and mark it.
  Widget _anchor(
    String id,
    Widget child, {
    bool framed = false,
    Listenable? listenable,
    String message = 'Required',
  }) =>
      MissingFieldAnchor(
        fields: _missing,
        id: id,
        framed: framed,
        listenable: listenable,
        message: message,
        child: child,
      );

  Future<void> _temporarySave() async {
    if (!_restored) return;
    setState(() => _saving = true);
    await _persist(completed: false);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    if (!_restored) return;
    if (_stage != QuidStage.finished) {
      await _alert(
          'Checklist not complete',
          'Complete the ${switch (_stage) {
            QuidStage.chilling => '${_isWater ? 'water' : 'air'} chilling',
            QuidStage.injector => 'injector sampling',
            _ => 'QUID determination',
          }} stage before submitting.');
      if (!mounted) return;
      await _missing.flag(
        context,
        [_stageSwitchId(_stage)],
        stillMissing: (id) =>
            _stage != QuidStage.finished && id == _stageSwitchId(_stage),
      );
      return;
    }
    if (_directionRequired &&
        (_directionRemarks.text.trim().isEmpty ||
            _directionAction.text.trim().isEmpty)) {
      await _alert(
          'Rejection details missing',
          'Add the non-conformance remarks and the batch number and/or '
              'quantity removed before submitting.');
      if (!mounted) return;
      await _missing.flag(
        context,
        [
          if (_directionRemarks.text.trim().isEmpty) 'directionRemarks',
          if (_directionAction.text.trim().isEmpty) 'directionAction',
        ],
        stillMissing: (id) =>
            _directionRequired &&
            switch (id) {
              'directionRemarks' => _directionRemarks.text.trim().isEmpty,
              'directionAction' => _directionAction.text.trim().isEmpty,
              _ => false,
            },
      );
      return;
    }
    // Photographs belong to the rejection, as in the original: two of them
    // when one is issued, none asked for otherwise.
    if (_directionRequired) {
      final taken = (await widget.captureRepository
              .photosFor(widget.inspection.clientUuid, kind: 'quid'))
          .length;
      if (!mounted) return;
      if (quidRejectionPhotosOutstanding(taken)) {
        await _alert(
            'Rejection photographs',
            'Take $quidMinRejectionPhotos photographs for the rejection '
                'before completing — $taken of $quidMinRejectionPhotos taken.');
        if (!mounted) return;
        await _missing.flag(context, const ['rejectionPhotos']);
        return;
      }
    }
    _missing.clear();
    final ok = await _confirm(
      'Submit Confirmation',
      'Please confirm that you want to save the entire inspection with the '
          'info captured as is?',
      yes: 'Yes',
      no: 'No',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    await _persist(completed: true);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  // ------------------------------------------------------------ build

  static const _pass = Color(0xFF2E7D32);
  static const _fail = Color(0xFFC62828);

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  /// A worked-out figure, green or red where the rule says.
  Widget _readout(String label, String value,
          {String unit = '%', bool? passes}) =>
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: switch (passes) {
                  true => _pass.withValues(alpha: 0.12),
                  false => _fail.withValues(alpha: 0.12),
                  null => null,
                },
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value.isEmpty ? '—' : '$value $unit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: switch (passes) {
                    true => _pass,
                    false => _fail,
                    null => null,
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _error(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(message,
              style: const TextStyle(fontSize: 12.5, color: _fail)),
        );

  Widget _stageDone(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: _pass),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.35)),
            ),
          ],
        ),
      );

  static const _grams = TextInputType.numberWithOptions(decimal: true);

  /// "Sample #" with Prev / Next — the carcass in front of the inspector.
  Widget _sampleControl() {
    final round = _round;
    final at = _current.clamp(0, round.length - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sample # ${at + 1}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          OutlinedButton(onPressed: _previous, child: const Text('Prev')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _next, child: const Text('Next')),
        ],
      ),
    );
  }

  /// A small table drawn the way the original draws its sample lists: a
  /// heading row, one row per carcass as it is weighed, and a closing
  /// average row. The lists grow as the inspector goes, so what has been
  /// done so far is always in view (Ethan, 2026-09-26).
  Widget _grid({
    required List<String> head,
    required List<List<String>> rows,
    List<int>? flex,
    List<String>? foot,
    int? current,
    ValueChanged<int>? onTap,
    String? title,
  }) {
    final f = flex ?? List<int>.filled(head.length, 1);
    Widget cell(String t, int i, {bool bold = false}) => Expanded(
          flex: f[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Text(
              t.isEmpty ? '—' : t,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
    Widget line(List<String> c,
            {bool bold = false, Color? color, VoidCallback? onTapRow}) =>
        InkWell(
          onTap: onTapRow,
          child: Container(
            color: color,
            child: Row(children: [
              for (var i = 0; i < c.length; i++) cell(c[i], i, bold: bold),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              color: AppColors.surfaceAlt,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w900)),
            ),
          line(head, bold: true, color: AppColors.surfaceAlt),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('None yet.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
          for (var n = 0; n < rows.length; n++)
            line(
              rows[n],
              color: n == current
                  ? AppColors.brandTeal.withValues(alpha: 0.08)
                  : null,
              onTapRow: onTap == null ? null : () => onTap(n),
            ),
          if (foot != null) line(foot, bold: true),
        ],
      ),
    );
  }

  /// "List of Samples" under the chilling stage, as the original lists
  /// them: one row per carcass weighed in, with its round and the method.
  /// A row opens its carcass.
  Widget _chillingList() {
    final round = _round;
    final rows = <List<String>>[];
    final indexes = <int>[];
    for (var n = 0; n < round.length; n++) {
      if (!round[n].hasInitial) continue;
      rows.add([
        '${n + 1}',
        '$_iteration',
        _isWater ? 'Water' : 'Air',
        round[n].initial.text.trim(),
      ]);
      indexes.add(n);
    }
    final here = indexes.indexOf(_current);
    return _grid(
      head: const ['Sample #', 'Iteration', 'Chill Method', 'Initial Weight (g)'],
      rows: rows,
      flex: const [2, 2, 3, 3],
      current: here < 0 ? null : here,
      onTap: (r) => setState(() => _current = indexes[r]),
    );
  }

  /// Each injector's carcasses as the original lists them under the
  /// injector once weighed: after mass, gain and rate, with the average.
  List<Widget> _injectorLists() {
    final round = _round;
    return [
      for (final inj in _injectors)
        () {
          final mine = [
            for (final s in round)
              if (s.assignedInjector == inj.position && s.gain.isNotEmpty) s,
          ];
          return _grid(
            title: inj.name.isEmpty ? 'Injector ${inj.position}' : inj.name,
            head: const ['Sample #', 'After (g)', 'Gain (g)', 'Inj. Rate'],
            rows: [
              for (final s in mine)
                [
                  '${round.indexOf(s) + 1}',
                  s.injectorAfter.text.trim(),
                  s.gain,
                  s.injectorRate,
                ],
            ],
            foot: [
              'Average Injector Rate (%)',
              '',
              '',
              quidMean([for (final s in mine) s.injectorRate]),
            ],
            flex: const [3, 2, 2, 2],
          );
        }(),
    ];
  }

  /// Each injector's determination as the original lists it: the carcass,
  /// its initial and final mass, the set percentage and the calculated one,
  /// with the average the injector is judged on.
  List<Widget> _determinationLists() {
    final round = _round;
    return [
      for (final inj in _injectors)
        () {
          final mine = [
            for (final s in round)
              if (s.assignedInjector == inj.position &&
                  s.quidPercent.isNotEmpty)
                s,
          ];
          return _grid(
            title:
                'Injector: ${inj.name.isEmpty ? 'Injector ${inj.position}' : inj.name}',
            head: const [
              'Sample #',
              'Initial Mass (g)',
              'Final (g)',
              'Set QUID (%)',
              'Calc. QUID (%)',
            ],
            rows: [
              for (final s in mine)
                [
                  '${round.indexOf(s) + 1}',
                  s.initial.text.trim(),
                  s.quidFinal.text.trim(),
                  inj.quidPercent,
                  s.quidPercent,
                ],
            ],
            foot: [
              'Average QUID %',
              '',
              '',
              '',
              quidMean([for (final s in mine) s.quidPercent]),
            ],
            flex: const [2, 3, 2, 2, 3],
          );
        }(),
    ];
  }

  /// The injector status table: set against calculated, per injector.
  Widget _injectorStatus() {
    Widget cell(String t,
            {bool head = false, bool right = false, Color? color}) =>
        Text(t,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: head ? FontWeight.w900 : FontWeight.w400,
            ));
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            SizedBox(width: 26, child: cell('#', head: true)),
            Expanded(child: cell('Injector', head: true)),
            SizedBox(
                width: 80, child: cell('Set QUID %', head: true, right: true)),
            SizedBox(
                width: 90,
                child: cell('Calc. QUID %', head: true, right: true)),
          ]),
          Divider(height: 10, color: AppColors.border),
          for (final v in _verdicts) ...[
            Row(children: [
              SizedBox(width: 26, child: cell('${v.position}')),
              Expanded(child: cell(v.name.isEmpty ? '—' : v.name)),
              SizedBox(
                  width: 80,
                  child: cell(v.setPercent.isEmpty ? '—' : v.setPercent,
                      right: true)),
              SizedBox(
                width: 90,
                child: cell(
                  v.averagePercent.isEmpty ? '—' : v.averagePercent,
                  right: true,
                  color: switch (v.passes) {
                    true => _pass,
                    false => _fail,
                    null => null,
                  },
                ),
              ),
            ]),
            if (v.passes != null)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2, bottom: 6),
                child: Text(
                  '${v.verdict} — limit ${v.limitPercent.toStringAsFixed(3)}% '
                  '(${v.sampleCount} carcasses)',
                  style:
                      TextStyle(fontSize: 12, color: v.passes! ? _pass : _fail),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _chillingStage() {
    final s = _sample;
    final open = _stage == QuidStage.chilling;
    return [
      poultrySection('Create Sample Set'),
      _anchor(
          'initialMass',
          listenable: s.initial,
          poultryField(s.initial, 'Initial Carcass Weight (g)',
              keyboard: _grams,
              enabled: open,
              onChanged: (_) => setState(() {}))),
      if (_isWater) ...[
        poultrySection('Water Chilling Results'),
        poultryField(s.waterFinal, 'Final Mass (g)',
            keyboard: _grams, enabled: open, onChanged: (_) => setState(() {})),
        _error(s.waterFinalError),
        _readout('Sample Pick up %', s.pickup,
            passes: s.pickup.isEmpty ? null : quidWaterPickupPasses(s.pickup)),
        _anchor(
          'chillingComplete',
          framed: true,
          poultrySwitch(
            label: 'Water Chilling for Samples Complete',
            value: _chillingComplete,
            onChanged: (v) => unawaited(_closeChilling(v)),
            helper: 'At least five carcasses. The average pick-up may not be '
                'over ${quidMaxWaterPickupPercent.toStringAsFixed(0)}%.',
          ),
        ),
        _readout('Water Chilling Average Pick up %', _averageWaterPickup,
            passes: _averageWaterPickup.isEmpty
                ? null
                : quidWaterPickupPasses(_averageWaterPickup)),
      ] else ...[
        poultrySection('Air Chilling Control'),
        _anchor(
          'chillingComplete',
          framed: true,
          poultrySwitch(
            label: 'Air Chilling for Samples Complete',
            value: _chillingComplete,
            onChanged: (v) => unawaited(_closeChilling(v)),
            helper: 'At least five carcasses weighed.',
          ),
        ),
      ],
      _chillingList(),
    ];
  }

  List<Widget> _injectorStage() {
    final s = _sample;
    final open = _stage == QuidStage.injector;
    return [
      poultrySection('Injector Info'),
      if (_injectors.isEmpty)
        Text('No injectors on the set-up to assign this carcass to.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted))
      else
        IgnorePointer(
          ignoring: !open,
          child: PickerMenuField<int>(
            label: 'Assigned to Injector',
            value: s.assignedInjector,
            hint: 'Select injector for this sample',
            options: [
              for (final i in _injectors)
                (
                  value: i.position,
                  text: i.name.isEmpty ? 'Injector ${i.position}' : i.name,
                ),
            ],
            onChanged: (v) => setState(() => s.assignedInjector = v),
          ),
        ),
      poultryField(s.beforeMass, 'Before Mass (g)',
          keyboard: _grams,
          enabled: open && s.assignedInjector != null,
          onChanged: (_) => setState(() {})),
      poultryField(s.injectorAfter, 'After Mass (g)',
          keyboard: _grams,
          enabled: open && s.beforeMass.text.trim().isNotEmpty,
          onChanged: (_) => setState(() {})),
      _error(s.injectorAfterError),
      _readout('Gain (g)', s.gain, unit: 'g'),
      _readout('Sample Injector Rate (%)', s.injectorRate),
      _anchor(
        'injectorComplete',
        framed: true,
        poultrySwitch(
          label: 'Injector(s) Sampling Complete',
          value: _injectorComplete,
          onChanged: (v) => unawaited(_closeInjector(v)),
          helper: 'At least five carcasses on every injector.',
        ),
      ),
      _readout('Average Pick up %', _averageInjectorRate),
      ..._injectorLists(),
    ];
  }

  List<Widget> _determinationStage() {
    final s = _sample;
    final open = _stage == QuidStage.determination;
    final setFor = _injectors
        .where((i) => i.position == s.assignedInjector)
        .firstOrNull
        ?.quidPercent;
    return [
      poultrySection('Determination of QUID'),
      _readout('Initial Mass (g)', s.initial.text.trim(), unit: 'g'),
      poultryField(s.quidFinal, 'After Mass (g)',
          keyboard: _grams, enabled: open, onChanged: (_) => setState(() {})),
      _error(s.quidFinalError),
      _readout('Gain Mass (g)', s.quidGain, unit: 'g'),
      _readout('QUID (%)', s.quidPercent),
      _readout('Set Injector QUID (%)', setFor ?? ''),
      _injectorStatus(),
      ..._determinationLists(),
      _anchor(
        'determinationComplete',
        framed: true,
        poultrySwitch(
          label: 'QUID Determintion Complete',
          value: _determinationComplete,
          onChanged: (v) => unawaited(_closeDetermination(v)),
          helper: 'At least five carcasses on every injector.',
        ),
      ),
      if (!_directionRequired && _iteration < quidMaxIterations)
        poultrySwitch(
          label: 'Repeat QUID Determine Vertification',
          value: false,
          onChanged: (v) => unawaited(_repeat(v)),
          helper: 'Weigh a new sample set. This round stays on the record; '
              'the new one decides.',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
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
      body: ContentWidth(
          child: FutureBuilder<List<PoultryDesignationRef>>(
        future: _remarks,
        builder: (context, snap) {
          final remarks = snap.data ?? const <PoultryDesignationRef>[];
          if (!_restored) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              poultrySection('QUID Info'),
              _detail('Client Name', _clientForDisplay),
              _detail('Chilling Method', _isWater ? 'Water' : 'Air'),
              _detail('Portion Type',
                  widget.inspection.isWholeCarcass ? 'Whole Carcass' : 'Cuts'),
              // The regulated standard the injectors are held to: 10% on
              // whole carcasses, 15% on cuts, judged with the tolerance.
              _detail(
                  'Regulated QUID Standard',
                  '${quidRegulatedPercent(isWholeCarcass: widget.inspection.isWholeCarcass).toStringAsFixed(0)}% '
                  'for ${widget.inspection.isWholeCarcass ? 'whole carcasses' : 'cuts'}, '
                  'judged with a '
                  '${(widget.inspection.isWholeCarcass ? quidWholeCarcassTolerance : quidCutPortionTolerance).toStringAsFixed(1)}% tolerance'),
              _detail('Current Inspection Iteration',
                  '$_iteration of $quidMaxIterations'),

              // What is already behind the inspector, one line a stage.
              if (_iteration > 1)
                _stageDone('Round 1 is on the record. This is the repeat, '
                    'and it is the round the determination is judged on.'),
              if (_chillingComplete &&
                  !(_directionRequired && !_injectorComplete))
                _stageDone(_isWater
                    ? 'Water chilling complete — average pick-up '
                        '$_averageWaterPickup%.'
                    : 'Air chilling complete.'),
              if (_injectorComplete &&
                  stage != QuidStage.injector &&
                  _averageInjectorRate.isNotEmpty)
                _stageDone('Injector sampling complete — average rate '
                    '$_averageInjectorRate%.'),
              if (stage == QuidStage.finished && !_directionRequired)
                _stageDone('QUID determination complete — every injector '
                    'within its limit.'),

              if (stage != QuidStage.finished) ...[
                const SizedBox(height: 6),
                _sampleControl(),
                if (stage == QuidStage.chilling) ..._chillingStage(),
                if (stage == QuidStage.injector) ..._injectorStage(),
                if (stage == QuidStage.determination) ..._determinationStage(),
              ] else if (_verdicts.any((v) => v.passes != null)) ...[
                _injectorStatus(),
                ..._determinationLists(),
              ],

              poultrySection('Verification of Records'),
              DateField(
                label: 'Date',
                value: _documentDate,
                // "Document Date cannot set be set into the future."
                lastDate: DateTime.now(),
                onChanged: (d) => setState(() => _documentDate = d),
                emptyHint: 'The date on the record being verified.',
              ),
              _anchor(
                  'documentName',
                  listenable: _documentName,
                  poultryField(_documentName, 'Name/Document Number',
                      onChanged: (_) => setState(() {}))),
              poultrySwitch(
                label: 'Document Verified',
                value: _documentVerified,
                onChanged: (v) => setState(() => _documentVerified = v),
              ),
              poultrySwitch(
                label: 'Deviation(s) Present',
                value: _documentDeviationPresent,
                onChanged: (v) => setState(() => _documentDeviationPresent = v),
              ),
              if (_documentDeviationPresent)
                poultryField(_deviationComment, 'Deviation Comment', lines: 2),
              // As the original's row: Take Photo opens once the document is
              // named, Add once it is photographed, Clear List always.
              _anchor(
                'documentPhoto',
                framed: true,
                message: 'Take a photograph of the document',
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _documentPhotoPath == null
                        ? 'Each document is photographed before it is added.'
                        : 'Photograph taken for this document.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ),
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _documentName.text.trim().isEmpty
                        ? null
                        : _takeDocumentPhoto,
                    icon: Icon(
                        _documentPhotoPath == null
                            ? Icons.photo_camera_outlined
                            : Icons.check,
                        size: 18),
                    label: Text(
                        _documentPhotoPath == null ? 'Take Photo' : 'Retake'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addRecord,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _records.isEmpty && _documentPhotoPath == null
                        ? null
                        : _clearRecords,
                    child: const Text('Clear List'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              for (var n = 0; n < _records.length; n++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1, right: 6),
                        child: Icon(
                          _records[n].hasPhoto
                              ? Icons.photo_camera
                              : Icons.no_photography_outlined,
                          size: 16,
                          color: _records[n].hasPhoto
                              ? AppColors.ink
                              : AppColors.muted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${n + 1}. ${_records[n].documentName}'
                          '${_records[n].date == null ? '' : ' — ${DateField.dmy(_records[n].date!)}'}'
                          ' — ${_records[n].verified ? 'verified' : 'not verified'}'
                          '${_records[n].deviationPresent ? ' — deviation: ${_records[n].deviationComment}' : ''}',
                          style: TextStyle(
                              fontSize: 13,
                              color:
                                  _records[n].deviationPresent ? _fail : null),
                        ),
                      ),
                    ],
                  ),
                ),

              // The original has no photo button outside the rejection
              // block; the shots may still be taken here, but nothing asks
              // for them until a rejection is issued, and then they are
              // asked for there.
              if (!_directionRequired)
                PoultryEvidenceSection(
                  repository: widget.captureRepository,
                  recordUuid: widget.inspection.clientUuid,
                  kind: 'quid',
                  captureLabel: 'Take QUID photograph',
                  guidance: 'Optional unless a rejection is issued. '
                      'Photograph the product and the scale reading '
                      'together, so the figures on the record can be traced '
                      'to what was weighed.',
                  maxPhotos: PoultryRules.maxPhotos,
                  showSignatures: false,
                ),

              // Only when the weighing ended in one, as in the original.
              if (_directionRequired) ...[
                poultrySection('Rejection Form'),
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _fail.withValues(alpha: 0.08),
                    border: Border.all(color: _fail.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_directionReason,
                      style: const TextStyle(
                          color: _fail, fontSize: 13, height: 1.4)),
                ),
                PickerMenuField<int>(
                  label: 'QUID Non-Conformance Remarks',
                  value: _remarkTypeId,
                  hint: 'Rejection Remark',
                  options: [
                    for (final r in remarks) (value: r.id, text: r.name),
                  ],
                  onChanged: (v) => setState(() => _remarkTypeId = v),
                ),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _remarkTypeId == null
                          ? null
                          : () => _addRemark(remarks),
                      child: const Text('Add Remark'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _directionRemarks.text.isEmpty
                          ? null
                          : () => setState(_directionRemarks.clear),
                      child: const Text('Clear Remarks'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                _anchor(
                    'directionRemarks',
                    listenable: _directionRemarks,
                    poultryField(_directionRemarks, 'List of Added Remarks',
                        lines: 3)),
                // FSA-SOP-APS-001 Annexure C seizes on a QUID deviation, so
                // the date is the inspection's own and not the inspector's
                // to move.
                IgnorePointer(
                  child: DateField(
                    label: 'Correct by/on Date',
                    value: _correctBy,
                    onChanged: (d) => setState(() => _correctBy = d),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Rectify immediately, per FSA-SOP-APS-001 Annexure C: '
                    'a QUID deviation is an immediate seizure.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted, height: 1.35),
                  ),
                ),
                if (_seizureDecision != null) _seizureNotice(),
                _anchor(
                    'directionAction',
                    listenable: _directionAction,
                    poultryField(
                        _directionAction, 'Batch No. and/or Quantity Removed')),
                // "Add Photo [0/2]": the rejection's own photographs.
                _anchor(
                  'rejectionPhotos',
                  framed: true,
                  PoultryEvidenceSection(
                    repository: widget.captureRepository,
                    recordUuid: widget.inspection.clientUuid,
                    kind: 'quid',
                    photosTitle: 'Rejection Photographs',
                    captureLabel: 'Add Photo',
                    guidance: 'Photograph the product and the scale reading '
                        'together. A rejection needs $quidMinRejectionPhotos '
                        'before the checklist can be submitted.',
                    minPhotos: quidMinRejectionPhotos,
                    maxPhotos: PoultryRules.maxPhotos,
                    showSignatures: false,
                    onChanged: () => unawaited(_recheckRejectionPhotos()),
                  ),
                ),
              ],

              if (!_inVisit) ...[
                poultrySection('Signatures Control'),
                poultryField(_managerName, 'Authorised Representative name'),
                poultryField(_managerEmail, 'Representative Email address',
                    keyboard: TextInputType.emailAddress),
                poultryField(_clientEmail, 'Email address #1 (optional)',
                    keyboard: TextInputType.emailAddress),
                poultryField(_clientEmail2, 'Email address #2 (optional)',
                    keyboard: TextInputType.emailAddress),
                // After the rejection, as the original orders it. A grouped
                // inspection signs once, at the end.
                PoultryEvidenceSection(
                  repository: widget.captureRepository,
                  recordUuid: widget.inspection.clientUuid,
                  kind: 'quid',
                  showPhotos: false,
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'This record is part of a grouped inspection. The manager '
                    'and inspector sign once, at the end, and those '
                    'signatures are applied to every record in it.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.muted, height: 1.4),
                  ),
                ),
              poultryField(_generalComments, 'General Comments', lines: 3),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _saving ? null : _temporarySave,
                        child: const Text('Temporary Save'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: Text(_saving ? 'Saving…' : 'Submit Checklist'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The original's third button. A determination the office
              // already holds cannot be invalidated from the handset.
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _saving || widget.inspection.isUploaded
                      ? null
                      : _abandon,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _fail,
                    side: BorderSide(color: _fail.withValues(alpha: 0.6)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Abandon Checklist'),
                ),
              ),
              if (widget.inspection.isUploaded)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'This determination is already on the server, so it '
                    'cannot be abandoned from the handset.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ),
            ],
          );
        },
      )),
    );
  }
}
