import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/data/sqlite_connection.dart';
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
  _Sample(this.iteration, {required this.waterChilled});

  /// The round this carcass was weighed in.
  final int iteration;

  /// Whether the plant water chills. Then the weight going onto the
  /// injector is also the weight off the water chiller, so Step 1 asks the
  /// weight before water chilling only and the pick-up follows Step 2's
  /// weight (Ethan, 2026-10-04) — the weighing is not asked twice.
  final bool waterChilled;

  /// Stage 1: the carcass on the way in, before (water) chilling.
  final initial = TextEditingController();

  /// Stage 2: which injector ran it, and the carcass on and off it.
  int? assignedInjector;
  final beforeMass = TextEditingController();
  final injectorAfter = TextEditingController();

  /// Stage 3: the carcass off the process.
  final quidFinal = TextEditingController();

  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  static double? _numText(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.'));

  /// The weight going onto the injector, weighed and typed on the injector
  /// step as the original's Before Mass is (Ethan, 2026-10-01).
  String get before => beforeMass.text.trim();

  bool get hasInitial => (_num(initial) ?? 0) > 0;
  bool get hasBefore => (_num(beforeMass) ?? 0) > 0;

  /// Nothing weighed on it: a carcass Next or a new injector opened and
  /// nobody typed into. Being on an injector already does not make it one.
  bool get isEmpty =>
      initial.text.trim().isEmpty &&
      beforeMass.text.trim().isEmpty &&
      injectorAfter.text.trim().isEmpty &&
      quidFinal.text.trim().isEmpty;

  /// "The entered water chilled weight value cannot be less than that of
  /// the initial weight." — the weight off the water chiller being the
  /// weight going onto the injector.
  String? get waterFinalError {
    if (!waterChilled) return null;
    final a = _num(initial);
    final b = _num(beforeMass);
    if (a == null || b == null) return null;
    return b < a
        ? 'The entered water chilled weight value cannot be less than that of '
            'the initial weight.'
        : null;
  }

  /// "The Value cannot be less than the Before Mass".
  String? get injectorAfterError {
    final a = _numText(before);
    final b = _num(injectorAfter);
    if (a == null || b == null) return null;
    return b <= a
        ? 'The weight after the injector must be more than the weight going '
            'onto it.'
        : null;
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

  /// Water pick-up over the mass off the chiller — the weight going onto
  /// the injector — three decimals. Empty on air chilling.
  String get pickup => !waterChilled || waterFinalError != null
      ? ''
      : quidPercentOf(_num(initial), _num(beforeMass));

  String get gain {
    if (injectorAfterError != null) return '';
    final a = _numText(before);
    final b = _num(injectorAfter);
    if (a == null || b == null) return '';
    return (b - a).toStringAsFixed(3);
  }

  /// "Sample Injector Rate (%)": the gain over the mass off the injector.
  String get injectorRate => injectorAfterError != null
      ? ''
      : quidPercentOf(_numText(before), _num(injectorAfter));

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
        waterFinal: waterChilled && waterFinalError == null ? before : '',
        injector: assignedInjector,
        injectorAfter:
            injectorAfterError == null ? injectorAfter.text.trim() : '',
        quidPercent: quidPercent,
      );

  void dispose() {
    initial.dispose();
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

  // Records checked at the plant: one document, photographed when
  // something is wrong with it (Ethan, 2026-10-01). No Add, no list.
  final _documentName = TextEditingController();
  final _deviationComment = TextEditingController();
  DateTime? _documentDate;
  bool _documentVerified = false;
  bool _documentDeviationPresent = false;

  /// Documents a record from before this change listed after its first.
  /// Kept on the record as they were; the page shows the first only.
  final _moreRecords = <QuidVerificationRecord>[];

  /// The document's photographs, kind `document`, as they stand on disk.
  /// At least one when something is wrong with the document, and at most
  /// [_maxDocumentPhotos] (Ethan, 2026-10-01).
  var _documentPhotos = <PoultryPhoto>[];
  static const _maxDocumentPhotos = 3;
  bool _photographingDocument = false;

  int? _remarkTypeId;
  DateTime? _correctBy;

  /// The round being weighed: 1, or 2 when repeated.
  int _iteration = 1;

  /// The step the screen shows for the injector being weighed. Worked out
  /// from what is weighed when the weighing opens or goes to another
  /// injector, and moved on by Next once the injector's five are done —
  /// never while a weight is still being typed (Ethan, 2026-09-30).
  QuidStage _view = QuidStage.chilling;

  /// Where an injector stands, from what has been weighed on it: five
  /// carcasses chilled, then five on and off it, then five final weights.
  QuidStage _stepFor(int position) {
    final mine = [
      for (final s in _round)
        if (s.assignedInjector == position) s,
    ];
    int count(bool Function(_Sample s) done) => mine.where(done).length;
    if (count((s) => s.hasInitial) < quidMinimumSampleSet) {
      return QuidStage.chilling;
    }
    if (count((s) => s.injectorRate.isNotEmpty) < quidMinimumSampleSet) {
      return QuidStage.injector;
    }
    if (count((s) => s.quidPercent.isNotEmpty) < quidMinimumSampleSet) {
      return QuidStage.determination;
    }
    return QuidStage.finished;
  }

  bool _allPast(QuidStage stage) =>
      _injectors.isNotEmpty &&
      _injectors.every((i) => _stepFor(i.position).index > stage.index);

  // Where the round stands, for the record: a step is complete once every
  // injector is past it, or the weighing ended in a rejection.
  bool get _chillingComplete =>
      _directionRequired || _allPast(QuidStage.chilling);
  bool get _injectorComplete =>
      _directionRequired || _allPast(QuidStage.injector);
  bool get _determinationComplete =>
      _directionRequired || _allPast(QuidStage.determination);

  /// Every injector weighed through all three steps.
  bool get _allDone => _allPast(QuidStage.determination);

  /// An injector whose carcasses are not all weighed in yet: until there is
  /// none, no injector goes on to Step 2 — the carcasses are weighed in
  /// first, as the original weighs them (Ethan, 2026-09-30).
  bool get _anyChilling =>
      _injectors.any((i) => _stepFor(i.position) == QuidStage.chilling);

  /// The next injector still to weigh after the one on screen, or null.
  int? _nextOpenInjector() {
    for (var n = 1; n < _injectors.length; n++) {
      final at = (_onInjector + n) % _injectors.length;
      if (_stepFor(_injectors[at].position) != QuidStage.finished) return at;
    }
    return null;
  }

  /// The average of [of] over the carcasses of the injector on screen.
  String _averageOnFocused(String Function(_Sample s) of) => quidMean([
        for (final s in _round)
          if (s.assignedInjector == _focused?.position) of(s),
      ]);

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

  /// The injector being weighed, as an index into [_injectors]: all of one
  /// injector's carcasses, then the next (Ethan, 2026-09-30).
  int _onInjector = 0;

  PoultryQuidInjector? get _focused => _injectors.isEmpty
      ? null
      : _injectors[_onInjector.clamp(0, _injectors.length - 1)];

  static String _nameOf(PoultryQuidInjector i) =>
      i.name.isEmpty ? 'Injector ${i.position}' : i.name;

  /// Carcasses on [position] with this stage's weighing done.
  int _doneOn(int position) => _countIn(position, _stage);

  /// Carcasses on [position] with [step]'s weighing done.
  int _countIn(int position, QuidStage step) => _round
      .where((s) =>
          s.assignedInjector == position &&
          switch (step) {
            QuidStage.chilling => s.hasInitial,
            QuidStage.injector => s.injectorRate.isNotEmpty,
            _ => s.quidPercent.isNotEmpty,
          })
      .length;

  /// The weight still missing on the carcass on screen, as the field's
  /// [_missing] id and the words to say so, or null when it is all there.
  ({String id, String say})? _weightMissing() {
    final c = _sample;
    return switch (_stage) {
      QuidStage.chilling when !c.hasInitial => (
          id: 'initialMass',
          say: _isWater
              ? 'Type the weight before water chilling first.'
              : 'Type the weight before chilling first.'
        ),
      QuidStage.injector when !c.hasBefore => (
          id: 'beforeMass',
          say: 'Type the initial weight before the injector first.'
        ),
      QuidStage.injector when c.injectorRate.isEmpty => (
          id: 'injectorAfter',
          say: 'Type the weight after the injector first.'
        ),
      QuidStage.determination when c.quidPercent.isEmpty => (
          id: 'quidFinal',
          say: 'Type the final weight first.'
        ),
      _ => null,
    };
  }

  /// Whether carcass [s] is the injector's being weighed — or, on the
  /// injector stage, still free to go on it.
  bool _onFocused(_Sample s) {
    final focused = _focused;
    if (focused == null) return true;
    return switch (_stage) {
      QuidStage.chilling ||
      QuidStage.injector =>
        s.assignedInjector == null || s.assignedInjector == focused.position,
      _ => s.assignedInjector == focused.position,
    };
  }

  /// The first carcass for the injector being weighed. In Step 1 an
  /// injector with none yet gets a new one, rather than the screen showing
  /// another injector's carcass under its name.
  int _firstForFocus() {
    final round = _round;
    for (var n = 0; n < round.length; n++) {
      if (_onFocused(round[n])) return n;
    }
    if (_stage == QuidStage.chilling && _focused != null) {
      _samples.add(_Sample(_iteration, waterChilled: _isWater)..assignedInjector = _focused!.position);
      return round.length;
    }
    return 0;
  }

  /// Picks up where a reopened weighing stood: the first injector still
  /// short of its five, and its first carcass.
  void _settleFocus() {
    if (_injectors.isEmpty) return;
    final chilling = _injectors
        .indexWhere((i) => _stepFor(i.position) == QuidStage.chilling);
    final open = chilling >= 0
        ? chilling
        : _injectors
            .indexWhere((i) => _stepFor(i.position) != QuidStage.finished);
    _onInjector = open < 0 ? _injectors.length - 1 : open;
    _view = _stepFor(_focused!.position);
    _current = _firstForFocus();
  }

  void _toInjector(int index) {
    _missing.clear();
    setState(() {
      // A carcass opened and never weighed is dropped, so the next
      // injector's numbering carries straight on.
      if (_stage == QuidStage.chilling) {
        final unused = [
          for (final s in _round)
            if (s.isEmpty) s,
        ];
        for (final s in unused) {
          _samples.remove(s);
          s.dispose();
        }
      }
      _onInjector = index;
      _view = _anyChilling ? QuidStage.chilling : _stepFor(_focused!.position);
      _current = _firstForFocus();
    });
    _keep();
  }

  /// Kept as the inspector goes, carcass by carcass, so an app closed by
  /// the phone or a flat battery loses nothing already weighed (Ethan,
  /// 2026-09-30). A weighing already submitted stays submitted. Called on
  /// every move to another carcass, so it also puts the cursor back.
  void _keep() {
    _focusStepBox();
    if (!_restored) return;
    unawaited(_persist(completed: widget.inspection.status != 'draft'));
  }

  // The box each step is typed into: after Next or Prev the cursor goes
  // straight back there, with the keyboard up, rather than a tap on it
  // every carcass (Ethan, 2026-09-30).
  final _beforeChillingBox = FocusNode();
  final _beforeInjectorBox = FocusNode();
  final _afterInjectorBox = FocusNode();
  final _finalWeightBox = FocusNode();

  void _focusStepBox() {
    final box = switch (_stage) {
      QuidStage.chilling => _beforeChillingBox,
      QuidStage.injector => _beforeInjectorBox,
      QuidStage.determination => _finalWeightBox,
      QuidStage.finished => null,
    };
    if (box == null) return;
    // The keyboard sits over Prev and Next on the tablet, so it is put away
    // to reach them — and the box keeps the cursor meanwhile, so asking for
    // focus again did nothing and the keyboard stayed down. Letting go of
    // the box first makes taking it back open the keyboard (Ethan,
    // 2026-10-01).
    if (box.hasFocus) box.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && box.context != null) box.requestFocus();
    });
  }

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

  /// The step on screen: the injector's own, or done once the weighing
  /// ended in a rejection.
  QuidStage get _stage => _directionRequired ? QuidStage.finished : _view;

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
    final records = QuidVerificationRecord.decode(i.verificationRecordsJson);
    // The document as it was saved: the first of a record that kept a
    // list, or the one older records held in these fields.
    final first = records.firstOrNull ??
        (i.documentName.trim().isEmpty
            ? null
            : QuidVerificationRecord(
                date: i.documentDate,
                documentName: i.documentName,
                verified: i.documentVerified,
                deviationPresent: i.documentDeviationPresent,
                deviationComment: i.documentDeviationComment,
              ));
    // The date on the document is usually today's.
    _documentDate = first?.date ?? DateTime.now();
    _documentName.text = first?.documentName ?? '';
    _documentVerified = first?.verified ?? false;
    _documentDeviationPresent = first?.deviationPresent ?? false;
    _deviationComment.text = first?.deviationComment ?? '';
    _moreRecords.addAll(records.skip(1));
    unawaited(_reloadDocumentPhotos());
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
        // A carcass saved with nothing weighed on it is not a carcass: left
        // out, so the numbering has no gaps.
        if ([
          s.initialMassG,
          s.finalMassG,
          s.beforeMassG,
          s.injectorAfterMassG,
          s.quidFinalMassG,
        ].every((m) => m.trim().isEmpty)) {
          continue;
        }
        final assigned = int.tryParse(s.assignedInjector);
        _samples.add(_Sample(s.iteration, waterChilled: _isWater)
          ..initial.text = s.initialMassG
          ..assignedInjector =
              _injectorPositions.contains(assigned) ? assigned : null
          ..beforeMass.text =
              s.beforeMassG.trim().isNotEmpty ? s.beforeMassG : s.finalMassG
          ..injectorAfter.text = s.injectorAfterMassG
          ..quidFinal.text = s.quidFinalMassG);
      }
      if (_round.isEmpty) _samples.add(_Sample(_iteration, waterChilled: _isWater));
      _settleFocus();
      _restored = true;
    });
    // Ready to type the moment the page is open, as after every Next
    // (Ethan, 2026-10-01).
    _focusStepBox();
  }

  @override
  void dispose() {
    _beforeChillingBox.dispose();
    _beforeInjectorBox.dispose();
    _afterInjectorBox.dispose();
    _finalWeightBox.dispose();
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
    final round = _round;
    var back = _current - 1;
    while (back >= 0 && !_onFocused(round[back])) {
      back--;
    }
    if (back < 0) {
      await _alert('First carcass', 'This is the first carcass.');
      return;
    }
    _missing.clear();
    setState(() => _current = back);
    _keep();
  }

  Future<void> _next() async {
    final round = _round;
    final focused = _focused;
    final missing = _weightMissing();
    if (missing != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(missing.say)));
      await _missing.flag(
        context,
        [missing.id],
        stillMissing: (id) => _weightMissing()?.id == id,
      );
      return;
    }
    _missing.clear();
    if (_stage == QuidStage.chilling) {
      _sample.assignedInjector ??= focused?.position;
    }
    var on = _current + 1;
    while (on < round.length && !_onFocused(round[on])) {
      on++;
    }
    // Its five are weighed and there is none of its carcasses after this
    // one: straight on to its next step, with nothing to confirm.
    if (focused != null &&
        on >= round.length &&
        _stage != QuidStage.finished &&
        _doneOn(focused.position) >= quidMinimumSampleSet) {
      await _onwards();
      return;
    }
    if (on < round.length) {
      setState(() => _current = on);
      _keep();
      return;
    }
    if (_stage == QuidStage.chilling) {
      // The next carcass of the set, for the injector being weighed.
      setState(() {
        _samples.add(_Sample(_iteration, waterChilled: _isWater)..assignedInjector = focused?.position);
        _current = round.length;
      });
      _keep();
      return;
    }
    await _alert(
        'Carcasses still to weigh',
        'Every carcass on this injector needs its weights before it moves on. '
            'Go back to the ones still empty with Prev.');
  }

  /// Where Next goes once this injector's five are done in the step on
  /// screen — with nothing to confirm.
  Future<void> _onwards() async {
    final focused = _focused!;
    if (_view == QuidStage.chilling) {
      // Every injector's carcasses are weighed in first, one injector after
      // the other.
      final waiting = _injectors.indexWhere((i) =>
          i.position != focused.position &&
          _stepFor(i.position) == QuidStage.chilling);
      if (waiting >= 0) {
        _toInjector(waiting);
        return;
      }
      // All weighed in: on to the injectors, the first still to do first.
      // Water chilling goes the same way as air (Ethan, 2026-10-04): the
      // water taken up is worked out and shown beside each carcass and on
      // the sheet, and the set moves on.
      // On to the injectors, the first still to do first.
      final first = _injectors
          .indexWhere((i) => _stepFor(i.position) != QuidStage.finished);
      _toInjector(first < 0 ? 0 : first);
      return;
    }
    if (_view.index < _stepFor(focused.position).index) {
      // Looking back at a step already done: on to the next, nothing checked
      // again.
      setState(() {
        _view = QuidStage.values[_view.index + 1];
        _current = _firstForFocus();
      });
      _focusStepBox();
      return;
    }
    await _advance();
  }

  /// A step tapped on the bar: back to one already done, or forward to one
  /// this injector has reached.
  void _goToStep(QuidStage step) {
    final focused = _focused;
    if (focused == null || _directionRequired || step == _view) return;
    String? refused;
    if (step != QuidStage.chilling && _anyChilling) {
      refused = "Weigh every injector's carcasses in Step 1 first.";
    } else if (step.index > _stepFor(focused.position).index) {
      refused = '${_nameOf(focused)} has not reached that step yet: finish '
          'step ${_stepFor(focused.position).index + 1} first.';
    }
    if (refused != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(refused)));
      return;
    }
    _missing.clear();
    setState(() {
      _view = step;
      _current = _firstForFocus();
    });
  }

  /// The injector's step is done: on to its next one. The regulation's
  /// checks are made here, and only speak up when something is over.
  Future<void> _advance() async {
    final focused = _focused!;
    switch (_view) {
      case QuidStage.determination:
        final verdict =
            _verdicts.where((v) => v.position == focused.position).firstOrNull;
        if (verdict?.passes == false) {
          await _determinationFailed(verdict!);
          return;
        }
      default:
        break;
    }
    setState(() {
      _view = _stepFor(focused.position);
      _current = _firstForFocus();
    });
    _keep();
  }

  /// Over 7% water on average: weighed again, or on the second set, a
  /// rejection.
  /// An injector over its QUID limit: weighed again, or on the second set,
  /// a rejection.
  Future<void> _determinationFailed(QuidInjectorVerdict v) async {
    final name = v.name.isEmpty ? 'Injector ${v.position}' : v.name;
    switch (quidOnFailure(_iteration)) {
      case QuidFailureStep.repeat:
        await _alert(
            'Too much QUID',
            '$name is over its limit: ${v.averagePercent}% against the '
                '${_trimNumber(v.limitPercent)}% allowed. Weigh a new set of '
                'carcasses to check again.');
        await _startNewRound();
      case QuidFailureStep.reject:
        setState(() {
          _directionRequired = true;
          _directionReason = '$name: average QUID ${v.averagePercent}% '
              'exceeds the permitted ${v.limitPercent.toStringAsFixed(3)}% '
              'over ${v.sampleCount} carcasses, on the second determination.';
          _correctBy = _rectifyImmediately();
        });
        await _persist(completed: false);
        await _askAboutQuidSeizure();
    }
  }

  // ------------------------------------------------------------ stages

  Future<void> _repeat(bool on) async {
    if (!on) return;
    if (_iteration >= quidMaxIterations) {
      await _alert(
          'No more rounds',
          'The weighing has already been done twice, which is the most '
              'allowed.');
      return;
    }
    final ok = await _confirm(
      'Weigh a new set?',
      'A new set of carcasses is weighed. This set stays on the record; the '
          'new one decides.',
      yes: 'Yes, weigh a new set',
      no: 'Not now',
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
      // Seized: the product is taken, so the weighing ends here — only the
      // photographs are still asked for (Ethan, 2026-09-30).
      await _submit();
      return;
    }
    await _persist(completed: false);
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

  /// A new sample set: the round before stays on the record.
  Future<void> _startNewRound() async {
    setState(() {
      _iteration++;
      _directionRequired = false;
      _directionReason = '';
      _seizureDecision = null;
      _seizureAsked = false;
      _onInjector = 0;
      _view = QuidStage.chilling;
      _samples.add(_Sample(_iteration, waterChilled: _isWater)..assignedInjector = _focused?.position);
      _current = 0;
    });
    await _persist(completed: false);
  }

  // ------------------------------------------------------------ records

  /// Photographs the document something is wrong with, straight onto the
  /// record as a `document` photo — nothing to Add (Ethan, 2026-10-01).
  Future<void> _takeDocumentPhoto() async {
    if (_photographingDocument ||
        _documentPhotos.length >= _maxDocumentPhotos) {
      return;
    }
    final name = _documentName.text.trim();
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
    setState(() => _photographingDocument = true);
    try {
      final storage = await PhotoStorage.instance();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await storage.adopt(
        File(shot),
        name: 'poultry_${widget.inspection.clientUuid}_document_$stamp.jpg',
      );
      await widget.captureRepository.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: widget.inspection.clientUuid,
          kind: 'document',
          filePath: path,
          caption: Value(
              name.isEmpty ? 'Document photograph' : 'Document: $name'),
          capturedAt: DateTime.now(),
        ),
      );
      await _reloadDocumentPhotos();
    } on Object catch (e) {
      if (mounted) {
        await _alert('Photo/Camera error', photoSaveFailure(e));
      }
    } finally {
      if (mounted) setState(() => _photographingDocument = false);
    }
  }

  /// Takes one of the document's photographs off the record.
  Future<void> _removeDocumentPhoto(PoultryPhoto photo) async {
    await widget.captureRepository.deletePhoto(photo.id);
    await _reloadDocumentPhotos();
  }

  Future<void> _reloadDocumentPhotos() async {
    final photos = await widget.captureRepository
        .photosFor(widget.inspection.clientUuid, kind: 'document');
    if (mounted) setState(() => _documentPhotos = photos);
  }

  /// The document checked, or null while nothing about one is filled in.
  QuidVerificationRecord? get _documentRecord {
    final name = _documentName.text.trim();
    if (name.isEmpty &&
        !_documentVerified &&
        !_documentDeviationPresent &&
        _documentPhotos.isEmpty) {
      return null;
    }
    return QuidVerificationRecord(
      date: _documentDate,
      documentName: name,
      verified: _documentVerified,
      deviationPresent: _documentDeviationPresent,
      deviationComment:
          _documentDeviationPresent ? _deviationComment.text.trim() : '',
      photoPath: _documentPhotos.firstOrNull?.filePath ?? '',
    );
  }

  /// One of the document's photographs, with its remove.
  Widget _documentThumb(PoultryPhoto photo) => Stack(
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
              onTap: _photographingDocument
                  ? null
                  : () => unawaited(_removeDocumentPhoto(photo)),
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
          finalMassG: Value(s.waterChilled ? s.before : ''),
          pickupPercent: Value(s.pickup),
          beforeMassG: Value(s.before),
          injectorAfterMassG: Value(s.injectorAfter.text.trim()),
          gainG: Value(s.gain),
          injectorRatePercent: Value(s.injectorRate),
          quidFinalMassG: Value(s.quidFinal.text.trim()),
          quidGainG: Value(s.quidGain),
          quidPercent: Value(s.quidPercent),
          assignedInjector: Value(s.assignedInjector?.toString() ?? ''),
        ),
    ]);

    // The document as the page has it, then any a record listed after it
    // before the list went (Ethan, 2026-10-01).
    final first = _documentRecord;
    final records = [if (first != null) first, ..._moreRecords];
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
        verificationRecordsJson: Value(QuidVerificationRecord.encode(records)),
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

  Future<void> _submit() async {
    if (!_restored) return;
    // Seized, the rest of the weighing is not asked for — only the
    // photographs (Ethan, 2026-09-30).
    final seized = _seizureDecision == SeizureDecision.seize;
    // An injector over its limit must not submit as a pass. The failure was
    // only ever caught on the way out of the determination stage, so a
    // weighing that reached the end by another route went up clean: four
    // determinations at Country fair product averaged 16.4 to 18.1% against
    // the 16.5% then allowed, all finished on the first round with no second set
    // and no rejection, and the inspector could not find the document she
    // had every reason to expect (Kutlwano, 2026-10-29). Checked here as
    // well, so the verdict decides the outcome wherever the inspector got
    // to. Routed through the same handler: the first failure asks for a new
    // sample set, the last one raises the rejection.
    if (!seized && !_directionRequired) {
      final failed =
          _verdicts.where((v) => v.passes == false).firstOrNull;
      if (failed != null) {
        await _determinationFailed(failed);
        return;
      }
    }
    if (!seized && !_allDone && !_directionRequired) {
      final open = _nextOpenInjector() ?? _onInjector;
      await _alert(
          'Not finished',
          'Weigh every injector through all three steps first. '
              '${_injectors.isEmpty ? '' : '${_nameOf(_injectors[open])} is '
                  'still to do.'}');
      return;
    }
    if (!seized &&
        _directionRequired &&
        (_directionRemarks.text.trim().isEmpty ||
            _directionAction.text.trim().isEmpty)) {
      await _alert(
          'Rejection details missing',
          'Add the non-conformance remarks and the batch number and/or '
              'quantity rejected before submitting.');
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
    // Something wrong with the document is photographed, at least once
    // (Ethan, 2026-10-01).
    if (!seized && _documentDeviationPresent && _documentPhotos.isEmpty) {
      await _alert(
          'Document photograph',
          'Something is wrong with the document: take at least 1 photograph '
              'of it before completing.');
      if (!mounted) return;
      await _missing.flag(
        context,
        const ['documentPhoto'],
        stillMissing: (_) =>
            _documentDeviationPresent && _documentPhotos.isEmpty,
      );
      return;
    }
    // Photographs belong to the rejection, as in the original: two of them
    // when one is issued, none asked for otherwise.
    if (_directionRequired || seized) {
      final taken = (await widget.captureRepository
              .photosFor(widget.inspection.clientUuid, kind: 'quid'))
          .length;
      if (!mounted) return;
      if (quidRejectionPhotosOutstanding(taken)) {
        await _alert(
            seized ? 'Seizure photographs' : 'Rejection photographs',
            seized
                ? seizurePhotosOwed('$quidMinRejectionPhotos photographs — '
                    '$taken of $quidMinRejectionPhotos taken')
                : 'Take $quidMinRejectionPhotos photographs for the '
                    'rejection before completing — $taken of '
                    '$quidMinRejectionPhotos taken.');
        if (!mounted) return;
        await _missing.flag(context, const ['rejectionPhotos']);
        return;
      }
    }
    _missing.clear();
    final ok = seized ||
        await _confirm(
          'Submit this QUID checklist?',
          _inVisit
              ? 'It is kept as finished and goes in with the rest of the visit at '
                  'the sign-off.'
              : 'It is kept as finished. Send it from Inspection Management.',
          yes: 'Submit',
          no: 'Not yet',
        );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    await _persist(completed: true);
    if (!mounted) return;
    setState(() => _saving = false);
    if (seized) announceSeizureDone(context);
    Navigator.of(context).pop(true);
  }

  // ------------------------------------------------------------ build

  static const _pass = Color(0xFF2E7D32);
  static const _fail = Color(0xFFC62828);

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
    // The carcass is counted within the injector it is on — its first,
    // second, … — not across the whole round (Ethan, 2026-10-04).
    final on = round.isEmpty
        ? _focused?.position
        : round[at].assignedInjector ?? _focused?.position;
    var number = 1;
    for (var n = 0; n < at; n++) {
      if (round[n].assignedInjector == on) number++;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              round.isEmpty || _injectors.isEmpty
                  ? 'Carcass $number'
                  : 'Carcass $number — ${_nameOf(_injectors.firstWhere(
                      (i) => i.position == on,
                      orElse: () => _focused!,
                    ))}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// Prev and Next, just below the box the step is typed into.
  Widget _carcassButtons() => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                    onPressed: _previous, child: const Text('Prev')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 46,
                child:
                    FilledButton(onPressed: _next, child: const Text('Next')),
              ),
            ),
          ],
        ),
      );

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
    // Ruled like the QUID sheet's tables (Ethan, 2026-10-04): a line
    // between the columns and between the rows.
    Widget cell(String t, int i, {bool bold = false}) => Expanded(
          flex: f[i],
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: BoxDecoration(
              border: Border(
                left: i == 0
                    ? BorderSide.none
                    : BorderSide(color: AppColors.border),
              ),
            ),
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
            decoration: BoxDecoration(
              color: color,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
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
    // The selected injector's own table, its carcasses numbered 1 to 5
    // (Ethan, 2026-10-04), as the Step 2 and Step 3 tables are laid out.
    // The columns are the QUID sheet's chilling table (Ethan, 2026-10-04):
    // on water the final mass is the weight off the chiller, typed on
    // Step 2; on air those two columns stay blank, as they do on the sheet.
    final method = _isWater ? 'Water chilling' : 'Air chilling';
    Widget table(PoultryQuidInjector? inj) {
      final rows = <List<String>>[];
      final indexes = <int>[];
      for (var n = 0; n < round.length; n++) {
        if (!round[n].hasInitial) continue;
        if (inj != null && round[n].assignedInjector != inj.position) continue;
        rows.add([
          '${rows.length + 1}',
          round[n].initial.text.trim(),
          _isWater ? round[n].before : '',
          round[n].pickup,
        ]);
        indexes.add(n);
      }
      final here = indexes.indexOf(_current);
      return _grid(
        title: inj == null ? method : '$method — ${_nameOf(inj)}',
        head: [
          'Carcass number',
          'Initial mass (g)',
          'Final mass (g)',
          '> $_allowablePercent% pick up',
        ],
        rows: rows,
        foot: [
          'Average pick up',
          '',
          '',
          quidMean([for (final n in indexes) round[n].pickup]),
        ],
        flex: const [2, 2, 2, 2],
        current: here < 0 ? null : here,
        onTap: (r) => setState(() => _current = indexes[r]),
      );
    }

    if (_injectors.isEmpty) return table(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final inj in _injectors)
          if (inj.position == _focused?.position)
            table(inj),
      ],
    );
  }

  /// The percentage the sheet's pick-up heading is read against: the
  /// plant's dispensation, or the regulated figure when it has none.
  String get _allowablePercent {
    final dispensation = widget.inspection.dispensationQuidPercent.trim();
    if (dispensation.isNotEmpty) return dispensation;
    return _trimNumber(
        quidRegulatedPercent(isWholeCarcass: widget.inspection.isWholeCarcass));
  }

  /// The injector being weighed, its carcasses on and off it.
  List<Widget> _injectorLists() {
    final round = _round;
    return [
      // The selected injector's own table — switching injector switches
      // the table, done or not (Ethan, 2026-10-04) — its samples numbered
      // 1 to 5.
      for (final inj in _injectors)
        if (inj.position == _focused?.position)
          () {
            final mine = [
              for (final s in round)
                if (s.assignedInjector == inj.position && s.gain.isNotEmpty) s,
            ];
            return _grid(
              // The QUID sheet's injector table (Ethan, 2026-10-04).
              title: 'Injector name: ${_nameOf(inj)}',
              head: const [
                'Sample no',
                'Before (g)',
                'After (g)',
                'Gain (g)',
                'Injection rate (%)',
              ],
              rows: [
                for (final s in mine)
                  [
                    '${mine.indexOf(s) + 1}',
                    s.before,
                    s.injectorAfter.text.trim(),
                    _trimGrams(s.gain),
                    s.injectorRate,
                  ],
              ],
              foot: [
                'Average',
                '',
                '',
                '',
                quidMean([for (final s in mine) s.injectorRate]),
              ],
              flex: const [2, 2, 2, 2, 2],
            );
          }(),
    ];
  }

  /// The selected injector's final weights and QUID; switching injector
  /// switches the table, done or not (Ethan, 2026-10-04).
  List<Widget> _determinationLists() {
    final round = _round;
    return [
      for (final inj in _injectors)
        if (inj.position == _focused?.position)
          () {
            final mine = [
              for (final s in round)
                if (s.assignedInjector == inj.position &&
                    s.quidPercent.isNotEmpty)
                  s,
            ];
            return _grid(
              // The QUID sheet's determination table (Ethan, 2026-10-04),
              // the injector's setting in the QUID column's heading.
              title: 'Determination of QUID — ${_nameOf(inj)}',
              head: [
                'Sample #',
                'Initial mass (g)',
                'Final mass (g)',
                'QUID ${inj.quidPercent}%',
              ],
              rows: [
                for (final s in mine)
                  [
                    '${mine.indexOf(s) + 1}',
                    s.initial.text.trim(),
                    s.quidFinal.text.trim(),
                    s.quidPercent,
                  ],
              ],
              foot: [
                'Average',
                '',
                '',
                quidMean([for (final s in mine) s.quidPercent]),
              ],
              flex: const [2, 2, 2, 2],
            );
          }(),
    ];
  }

  /// Each injector's result: what it is set to against the QUID found.
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
                width: 80, child: cell('Set to %', head: true, right: true)),
            SizedBox(
                width: 130,
                child: cell('Average QUID %', head: true, right: true)),
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
                width: 130,
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
                  '${v.passes! ? 'Within the limit' : 'Over the limit'}: '
                  '${v.averagePercent}% against the '
                  '${_trimNumber(v.limitPercent)}% allowed (set to '
                  '${v.setPercent}% plus the tolerance), over '
                  '${v.sampleCount} carcasses.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: v.passes! ? _pass : _fail),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Grams as a person writes them: 140, or 135.5 — not 140.000.
  static String _trimGrams(String value) {
    final n = double.tryParse(value);
    if (n == null) return value;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
  }

  /// A figure without trailing zeros: 11, not 11.000.
  static String _trimNumber(double n) {
    final s = n.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// What is being weighed, in one card.
  Widget _summaryCard() {
    final whole = widget.inspection.isWholeCarcass;
    final set = quidRegulatedPercent(isWholeCarcass: whole);
    final tolerance =
        whole ? quidWholeCarcassTolerance : quidCutPortionTolerance;
    Widget fact(String label, String value) => SizedBox(
          width: 230,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          fact('Client', _clientForDisplay),
          fact(
              'Product',
              widget.inspection.productDetails.trim().isEmpty
                  ? '—'
                  : widget.inspection.productDetails.trim()),
          fact('Product type', whole ? 'Whole carcass' : 'Portions'),
          fact('Chilling', _isWater ? 'Water' : 'Air'),
          fact(
              'Allowed QUID',
              'Up to ${_trimNumber(set)}% (${_trimNumber(set + tolerance)}% '
                  'with tolerance)'),
          fact('Round', '$_iteration of $quidMaxIterations'),
        ],
      ),
    );
  }

  /// Where every injector stands, so what is still missing shows at a
  /// glance: "Brine 2 — Step 1 of 3: 3/5 completed".
  Widget _progressList() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in _injectors)
              () {
                final step = _stepFor(i.position);
                final done = step == QuidStage.finished;
                final count =
                    done ? quidMinimumSampleSet : _countIn(i.position, step);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: done ? _pass : AppColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          done
                              ? '${_nameOf(i)}: all 3 steps completed'
                              : '${_nameOf(i)} — Step ${step.index + 1} of 3: '
                                  '$count/$quidMinimumSampleSet completed',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: i.position == _focused?.position
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }(),
          ],
        ),
      );

  /// The three steps: the one in hand lit, those behind ticked.
  Widget _stepBar(QuidStage stage) {
    const names = ['Weigh carcasses', 'On the injector', 'Final weight'];
    final at = stage.index;
    final focused = _focused;
    final reached = focused == null ? at : _stepFor(focused.position).index;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Row(
        children: [
          for (var i = 0; i < names.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: i == at
                    ? AppColors.brandPrimary.withValues(alpha: 0.10)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  // Back to a step already done, or on to one reached.
                  onTap: () => _goToStep(QuidStage.values[i]),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: i == at
                              ? AppColors.brandPrimary
                              : AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          i < reached
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 18,
                          color: i < reached
                              ? _pass
                              : (i == at
                                  ? AppColors.brandPrimary
                                  : AppColors.muted),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${names[i]}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  i == at ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
      poultrySection('Step 1 of 3: Weigh the carcasses'),
      if (_injectors.isNotEmpty) _injectorCard(),
      _sampleControl(),
      _anchor(
          'initialMass',
          listenable: s.initial,
          poultryField(s.initial, _beforeChillingLabel,
              markRequired: true,
              maxLength: 12,
              focusNode: _beforeChillingBox,
              keyboard: _grams,
              enabled: open,
              onChanged: (_) => setState(() {
                    s.assignedInjector ??= _focused?.position;
                  }))),
      // Water or air, Step 1 is the one weight (Ethan, 2026-10-04): the
      // weight off the water chiller is the weight onto the injector, asked
      // on Step 2.
      _carcassButtons(),
      _chillingList(),
    ];
  }

  /// Step 1's field, named for the chilling the plant does.
  String get _beforeChillingLabel => _isWater
      ? 'Weight before water chilling (g)'
      : 'Weight before chilling (g)';

  List<Widget> _injectorStage() {
    final s = _sample;
    final open = _stage == QuidStage.injector;
    return [
      poultrySection('Step 2 of 3: Weigh off the injector'),
      if (_injectors.isEmpty)
        Text('No injectors on the set-up to weigh this carcass on.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted))
      else
        _injectorCard(),
      _sampleControl(),
      // Weighed on the way onto the injector and again off it (Ethan,
      // 2026-10-01), as the original's Before Mass and After Mass.
      _anchor(
          'beforeMass',
          listenable: s.beforeMass,
          poultryField(s.beforeMass, 'Initial weight before the injector (g)',
              markRequired: true,
              maxLength: 12,
              focusNode: _beforeInjectorBox,
              keyboard: _grams,
              enabled: open,
              onChanged: (_) => setState(() {
                    s.assignedInjector ??= _focused?.position;
                  }))),
      if (_isWater) _error(s.waterFinalError),
      _anchor(
          'injectorAfter',
          listenable: s.injectorAfter,
          poultryField(s.injectorAfter, 'Weight after the injector (g)',
              markRequired: true,
              maxLength: 12,
              focusNode: _afterInjectorBox,
              keyboard: _grams,
              enabled: open,
              onChanged: (_) => setState(() {
                    s.assignedInjector ??= _focused?.position;
                  }))),
      _error(s.injectorAfterError),
      _carcassButtons(),
      if (_isWater) ...[
        _readout('Water this carcass took up (%)', s.pickup,
            passes: s.pickup.isEmpty ? null : quidWaterPickupPasses(s.pickup)),
        () {
          final average = _averageOnFocused((s) => s.pickup);
          return _readout('Average water taken up (%)', average,
              passes: average.isEmpty ? null : quidWaterPickupPasses(average));
        }(),
      ],
      _readout('Weight gained (g)', _trimGrams(s.gain), unit: 'g'),
      _readout('Brine this carcass took up (%)', s.injectorRate),
      _readout('Average brine taken up (%)',
          _averageOnFocused((s) => s.injectorRate)),
      ..._injectorLists(),
    ];
  }

  /// The injector being weighed, how far it is, and the way on to the next.
  Widget _injectorCard() {
    final focused = _focused!;
    final finished = _stage == QuidStage.finished;
    final done = _doneOn(focused.position);
    final enough = done >= quidMinimumSampleSet;
    final next = finished ? _nextOpenInjector() : null;
    final what = switch (_stage) {
      QuidStage.chilling => _isWater
          ? 'Weigh each of its carcasses before water chilling.'
          : 'Weigh each of its carcasses before chilling.',
      QuidStage.injector => _isWater
          ? 'Weigh each of its carcasses off the water chiller going onto '
              'the injector and again as it comes off.'
          : 'Weigh each of its carcasses going onto the injector and again '
              'as it comes off.',
      QuidStage.determination =>
        'Weigh each of its carcasses at the end of the line. It is set to '
            '${focused.quidPercent}%.',
      QuidStage.finished => 'Done: all three steps are weighed, and its '
          'result is below.',
    };
    final then = switch (_stage) {
      QuidStage.chilling => () {
          final waiting = _injectors
              .where((i) =>
                  i.position != focused.position &&
                  _stepFor(i.position) == QuidStage.chilling)
              .firstOrNull;
          return waiting == null
              ? 'When its five are weighed, Next goes on to the injectors.'
              : 'When its five are weighed, Next goes on to the carcasses '
                  'for ${_nameOf(waiting)}.';
        }(),
      QuidStage.injector =>
        'When its five are weighed, Next takes it on to the final weight.',
      QuidStage.determination =>
        'When its five are weighed, Next works out its QUID.',
      QuidStage.finished => '',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Injector ${_onInjector + 1} of ${_injectors.length}: '
            '${_nameOf(focused)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(what,
              style: TextStyle(
                  fontSize: 13.5, height: 1.35, color: AppColors.inkSoft)),
          if (then.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(then,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.35, color: AppColors.muted)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (done / quidMinimumSampleSet).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    color: enough ? _pass : AppColors.brandPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_nameOf(focused)}: $done/$quidMinimumSampleSet completed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: enough ? _pass : AppColors.ink,
                ),
              ),
            ],
          ),
          if (_injectors.length > 1 || next != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                // Any injector, any time: tap one to go to it. A tick is one
                // weighed through.
                if (_injectors.length > 1)
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (var n = 0; n < _injectors.length; n++)
                          ChoiceChip(
                            showCheckmark: false,
                            avatar: _stepFor(_injectors[n].position) ==
                                    QuidStage.finished
                                ? const Icon(Icons.check_circle,
                                    size: 18, color: _pass)
                                : null,
                            label: Text(_nameOf(_injectors[n])),
                            selected: n == _onInjector,
                            onSelected: (_) {
                              if (n != _onInjector) _toInjector(n);
                            },
                          ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (next != null) ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => _toInjector(next),
                    child: Text('Go to injector ${next + 1}: '
                        '${_nameOf(_injectors[next])}'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _determinationStage() {
    final s = _sample;
    final open = _stage == QuidStage.determination;
    return [
      poultrySection('Step 3 of 3: Final weight and QUID'),
      if (_injectors.isNotEmpty) _injectorCard(),
      _sampleControl(),
      _readout(_beforeChillingLabel, s.initial.text.trim(), unit: 'g'),
      _anchor(
          'quidFinal',
          listenable: s.quidFinal,
          poultryField(s.quidFinal, 'Final weight (g)',
              maxLength: 12,
              markRequired: true,
              focusNode: _finalWeightBox,
              keyboard: _grams,
              enabled: open,
              onChanged: (_) => setState(() {}))),
      _error(s.quidFinalError),
      _carcassButtons(),
      _readout('Weight gained in total (g)', _trimGrams(s.quidGain), unit: 'g'),
      _readout('QUID of this carcass (%)', s.quidPercent),
      _injectorStatus(),
      ..._determinationLists(),
      if (!_directionRequired && _iteration < quidMaxIterations)
        poultrySwitch(
          label: 'Start again with a new set of carcasses?',
          value: false,
          onChanged: (v) => unawaited(_repeat(v)),
          helper: 'Only if this set needs weighing again. It stays on the '
              'record; the new set decides.',
        ),
    ];
  }

  /// Back out of the weighing: what is weighed waits as a draft, which is
  /// why there is no Temporary Save (Ethan, 2026-09-30). A weighing already
  /// finished is left as it was; only Complete changes it.
  Future<void> _leave() async {
    if (_restored && widget.inspection.status == 'draft') {
      setState(() => _saving = true);
      await _persist(completed: false);
      if (!mounted) return;
      setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || _saving) return;
          await _leave();
        },
        child: _page(),
      );

  Widget _page() {
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
              _summaryCard(),
              _stepBar(stage),
              if (_injectors.length > 1 && !_directionRequired) _progressList(),

              // What is already behind the inspector, one line a stage.
              if (_iteration > 1)
                _stageDone('Round 1 is on the record. This is the repeat, '
                    'and it is the round the determination is judged on.'),
              if (_allDone && !_directionRequired)
                _stageDone('Every injector is weighed through and within its '
                    'limit.'),

              if (stage != QuidStage.finished) ...[
                if (stage == QuidStage.chilling) ..._chillingStage(),
                if (stage == QuidStage.injector) ..._injectorStage(),
                if (stage == QuidStage.determination) ..._determinationStage(),
              ] else ...[
                if (_injectors.isNotEmpty && !_directionRequired)
                  _injectorCard(),
                if (_verdicts.any((v) => v.passes != null)) ...[
                  _injectorStatus(),
                  ..._determinationLists(),
                ],
              ],

              poultrySection('Records checked at the plant'),
              DateField(
                label: 'Date',
                value: _documentDate,
                // "Document Date cannot set be set into the future."
                lastDate: DateTime.now(),
                onChanged: (d) => setState(() => _documentDate = d),
                emptyHint: 'The date on the document.',
              ),
              _anchor(
                  'documentName',
                  listenable: _documentName,
                  poultryField(_documentName, 'Document name or number',
                      onChanged: (_) => setState(() {}))),
              poultrySwitch(
                label: 'Document checked and correct?',
                value: _documentVerified,
                onChanged: (v) => setState(() => _documentVerified = v),
              ),
              poultrySwitch(
                label: 'Anything wrong with this document?',
                value: _documentDeviationPresent,
                onChanged: (v) => setState(() => _documentDeviationPresent = v),
              ),
              if (_documentDeviationPresent) ...[
                poultryField(_deviationComment, 'What is wrong with it',
                    lines: 2),
                // Something wrong with the document is photographed, at
                // least once. The shot goes straight onto the record, with
                // a remove on its thumbnail — no Add (Ethan, 2026-10-01).
                _anchor(
                  'documentPhoto',
                  framed: true,
                  message: 'Take at least 1 photograph of the document',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_documentPhotos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              for (final p in _documentPhotos)
                                _documentThumb(p),
                            ],
                          ),
                        ),
                      // Up to three; the button goes once they are taken.
                      if (_documentPhotos.length < _maxDocumentPhotos)
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: _photographingDocument
                                ? null
                                : () => unawaited(_takeDocumentPhoto()),
                            icon: const Icon(Icons.photo_camera_outlined,
                                size: 18),
                            label: Text(_documentPhotos.isEmpty
                                ? 'Take photo of the document '
                                    '(up to $_maxDocumentPhotos)'
                                : 'Take another photo '
                                    '(${_documentPhotos.length} of '
                                    '$_maxDocumentPhotos)'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // No photograph block of its own (Ethan, 2026-10-01): the
              // shots are taken on the rejection when one is issued.
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
                    poultryField(_directionRemarks, 'Added Remarks',
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
                // A seizure declined says nothing here: the rejection above stands
                // as it is (Ethan, 2026-09-30).
                if (_seizureDecision == SeizureDecision.seize) _seizureNotice(),
                _anchor(
                    'directionAction',
                    listenable: _directionAction,
                    poultryField(_directionAction,
                        'Batch No. and/or Quantity Rejected')),
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
              // No Temporary Save: going back keeps the weighing as a
              // draft, and the visit shows it in progress.
              // Until every injector is done the way on is the next one,
              // not a Submit that would only refuse.
              Builder(builder: (context) {
                final next =
                    _allDone || _directionRequired ? null : _nextOpenInjector();
                if (next != null && _stage == QuidStage.finished) {
                  return SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => _toInjector(next),
                      child: Text('Go to injector ${next + 1}: '
                          '${_nameOf(_injectors[next])}'),
                    ),
                  );
                }
                final ready = _allDone || _directionRequired;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving || !ready ? null : _submit,
                        child: Text(_saving ? 'Saving…' : 'Submit Checklist'),
                      ),
                    ),
                    if (!ready)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Submit opens once every injector is weighed '
                          'through all three steps.',
                          style:
                              TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ),
                  ],
                );
              }),
            ],
          );
        },
      )),
    );
  }
}
