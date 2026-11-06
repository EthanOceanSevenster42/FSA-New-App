import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/responsive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/data/restricted_particulars_catalogue.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../domain/label_grading.dart';
import '../domain/poultry_rules.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../../../core/widgets/search_picker.dart';
import 'poultry_evidence_section.dart';
import 'poultry_form_widgets.dart';
import 'poultry_inspection_form.dart';
import '../../../core/widgets/correct_by_date_field.dart';

/// New Label/Container Checklist.
///
/// The original asks the same nine lettering requirements twice — once of the
/// product label, once of the outer container — then how the container is
/// built. That shape is kept: an inspector can find the product label
/// compliant and the outer container not, and the record has to be able to
/// say which.
///
/// It stops there. The original's page does carry a second copy of the
/// grading and portion lists, in a `RetailInspection` grid it declares
/// `IsVisible="False"` and never once refers to from its code-behind — dead
/// markup, not a step of this inspection. Classification and grading are
/// captured on their own screen.
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
    this.visit,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;
  final String? existingUuid;

  /// Set when this checklist belongs to a store visit: the facility fields
  /// arrive filled and the signatures are taken once, at the end of the
  /// visit.
  final VisitPrefill? visit;

  /// The grading record graded underneath the labelling of the checklist
  /// [labelUuid]. Worked out from the checklist's own id, so the two find
  /// each other without a column to link them.
  static String gradingUuidFor(String labelUuid) =>
      gradingUuidForLabel(labelUuid);

  @override
  State<PoultryLabelChecklistForm> createState() =>
      _PoultryLabelChecklistFormState();
}

class _LabelReference {
  _LabelReference({
    required this.checklist,
    required this.reasons,
    required this.locations,
    required this.restricted,
    required this.shared,
    required this.remarks,
    required this.facilities,
  });

  // Classification and grading reference — meat types, portion types,
  // designations and the grade links — is not loaded here. It belongs to the
  // grading screen; this one verifies lettering and containers.
  final List<PoultryChecklistItemRef> checklist;
  final List<PoultryDesignationRef> reasons;
  final List<PoultryDesignationRef> locations;
  final List<PoultryDesignationRef> restricted;
  final List<String> shared;
  final List<PoultryDesignationRef> remarks;

  /// The premises directory, shared with the egg module.
  final List<EggFacility> facilities;
}

class _PoultryLabelChecklistFormState extends State<PoultryLabelChecklistForm> {
  late Future<_LabelReference> _reference;
  final _formKey = GlobalKey<FormState>();

  late final String _clientUuid = widget.existingUuid ?? const Uuid().v4();

  int? _locationId;

  /// True when the facility type chosen at the door settled [_locationId], so
  /// this form does not ask a question the group has already answered.
  bool _locationFromVisit = false;
  int? _reasonId;

  /// True when the reason chosen at the door settled [_reasonId].
  bool _reasonFromVisit = false;
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
  /// Particulars typed in because the Agency's list did not have them.
  final _typedRestricted = <String>{};
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

  /// FSA-SOP-APS-001 Annexure C: whether the class or grade designation was
  /// left off the label altogether (a seizure) rather than shown wrong (30
  /// days) — the inspector's answer when that row is unticked.
  bool _classOmitted = false;
  bool _gradeOmitted = false;

  /// "Correct by/on" — set by the annexure from the deviations, not typed.
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

  /// Whether the grading and classification checklist is done as well,
  /// underneath the labelling on this form.
  bool _gradingToFollow = false;
  final _gradingControl = PoultryGradingController();

  /// A seizure raised by the grading underneath: it ends this checklist
  /// as well (Ethan, 2026-09-30).
  bool _gradingSeized = false;
  late final String _gradingUuid =
      PoultryLabelChecklistForm.gradingUuidFor(_clientUuid);
  bool _saving = false;

  /// The record was already finished when it was opened: going back
  /// leaves it so, rather than turning it into a draft.
  bool _wasCompleted = false;

  /// Set once and restored on resume, so touching a draft does not move it
  /// between days and out from under the date filter that found it.
  late DateTime _inspectedAt = DateTime.now();

  /// The required fields a refused save flagged, so the page can take the
  /// inspector to the first and mark each red.
  final _missing = MissingFields();

  @override
  void initState() {
    super.initState();
    _applyVisitPrefill();
    _reference = _loadReference();
    if (widget.existingUuid != null) _restore(widget.existingUuid!);
    unawaited(_carryRegistrationNumber());
    // Typing keeps the draft too, not only what redraws the form.
    for (final c in _typed) {
      c.addListener(_autosave);
    }
  }

  /// The boxes the inspector types into.
  List<TextEditingController> get _typed => [
        _facilityName,
        _tradingName,
        _facilityAddress,
        _facilityTelephone,
        _registrationNumber,
        _contactPerson,
        _contactEmail,
        _productDetails,
        _followUp,
        _nonConformanceComments,
        _directionRemarks,
        _managerName,
        _managerEmail,
        _clientEmail,
        _clientEmail2,
        _generalComments,
      ];

  /// Kept as it is filled in (Ethan, 2026-09-30): the draft was written only
  /// on leaving the form or taking a label photo, so an app closed mid-way —
  /// by the phone, a flat battery, an update — lost the labelling, while the
  /// grading underneath survived and reopened as an inspection of its own.
  Timer? _autosaveTimer;

  /// Set once Complete is pressed, so a pending keep cannot turn the
  /// finished record back into a draft.
  bool _finishing = false;

  void _autosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), () {
      // A finished record is only changed by Complete, as on leaving.
      if (!mounted || _finishing || _wasCompleted) return;
      unawaited(_persist(completed: false));
    });
  }

  /// Every answer that redraws the form — a slider, a picker, the grading
  /// question — is kept as well.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _autosave();
  }

  /// Takes the registration number from whichever poultry record in this
  /// visit captured it first — the premises has one, and it is not worth
  /// typing on each record.
  ///
  /// Only ever fills an empty field, so a resumed draft and anything the
  /// inspector has already typed win over the carried value.
  Future<void> _carryRegistrationNumber() async {
    final visit = widget.visit;
    if (visit == null || _registrationNumber.text.trim().isNotEmpty) return;
    final carried =
        await widget.captureRepository.registrationNumberForVisit(visit.uuid);
    if (!mounted ||
        carried.isEmpty ||
        _registrationNumber.text.trim().isNotEmpty) {
      return;
    }
    setState(() => _registrationNumber.text = carried);
  }

  /// Fields the visit already knows arrive filled; only empty ones take the
  /// value, so a resumed draft keeps its own.
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
    fill(_managerName, visit.managerName);
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
      _wasCompleted = saved.status != 'draft';
      _locationId = saved.locationId;
      _reasonId = saved.reasonId;
      _remarkTypeId = saved.directionRemarkTypeId;
      _outerLabelsPresent = saved.outerLabelsPresent;
      _gradingToFollow = saved.gradingToFollow;
      _facilityName.text = saved.facilityName;
      _tradingName.text = saved.producerTradingName;
      _facilityAddress.text = saved.facilityAddress;
      _facilityTelephone.text = saved.facilityTelephone;
      _registrationNumber.text = saved.registrationNumber;
      _contactPerson.text = saved.contactPerson;
      _contactEmail.text = saved.contactPersonEmail;
      _productDetails.text = saved.productDetails;
      _followUp.text = saved.selectedDirectionForFollowup;
      _typedRestricted
        ..clear()
        ..addAll(TypedParticulars.unpack(saved.restrictedParticularsText));
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
      _classOmitted = saved.classOmitted;
      _gradeOmitted = saved.gradeOmitted;
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

  Future<_LabelReference> _loadReference() =>
      _load().timeout(const Duration(seconds: 20));

  void _retryReference() {
    if (!mounted) return;
    setState(() => _reference = _loadReference());
  }

  Future<_LabelReference> _load() async {
    final repo = widget.repository;
    final checklist = await repo.checklistItems();
    _startCompliant(checklist);
    return _LabelReference(
      checklist: checklist,
      reasons: await repo.inspectionReasons(),
      locations: await repo.inspectionLocations(),
      restricted: await repo.restrictedParticulars(),
      // Every commodity's list, so this form offers the same menu as the
      // rest.
      shared: await RestrictedParticularsCatalogue.names(repo.database),
      remarks: await repo.directionRemarks(),
      facilities: await repo.facilities(),
    );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
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
      _nonConformanceComments,
      _directionRemarks,
      _correctByDate,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _generalComments,
    ]) {
      c.dispose();
    }
    _missing.dispose();
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

  // `labelGrading` and `labelPortion` were scraped off the original's
  // `RetailInspection` grid, which that page declares `IsVisible="False"` and
  // its code-behind never touches — grading is not part of this screen. They
  // are excluded here too: counted as applicable but never shown, every row
  // would have read as a finding nobody could answer.
  bool _appliesHere(PoultryChecklistKind kind) => switch (kind) {
        PoultryChecklistKind.labelInner => true,
        PoultryChecklistKind.labelOuter => _outerLabelsPresent,
        PoultryChecklistKind.container => true,
        _ => false,
      };

  /// Writes the form to the local store — silently, so the evidence section
  /// can persist a draft the moment a photograph or signature lands.
  /// Whether any requirement is marked a deviation — the only time there
  /// is a rejection, and so non-conformance remarks, at all (Ethan,
  /// 2026-09-30).
  bool _deviated(_LabelReference reference) => PoultryRules.findings(
        items: _applicable(reference),
        compliantItemIds: _compliant,
      ).isNotEmpty;

  Future<void> _persist({required bool completed}) async {
    final deviated = _deviated(await _reference);
    // Read from the signature rows rather than tracked twice, so the record
    // field can never contradict what the Signatures block shows.
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined = signatures.any((s) => s.role == 'no_client' && s.declined);

    await widget.captureRepository.saveLabelInspection(
      PoultryLabelInspectionsCompanion.insert(
        clientUuid: _clientUuid,
        visitUuid: Value(widget.visit?.uuid ?? ''),
        inspectedAt: _inspectedAt,
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        // In a grouped inspection a finished member waits as `ready`; the
        // group's one sign-off submits everything together.
        status: Value(completed
            ? (widget.visit != null ? 'ready' : 'completed')
            : 'draft'),
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
        outerLabelsPresent: Value(_outerLabelsPresent),
        gradingToFollow: Value(_gradingToFollow),
        compliantItemIds: Value(_compliant.join(',')),
        restrictedParticularIds: Value(_restricted.join(',')),
        restrictedParticularsText:
            Value(TypedParticulars.pack(_typedRestricted)),
        // No deviation, no rejection: nothing kept that a document would
        // print as non-conformance remarks.
        nonConformanceComments:
            Value(deviated ? _nonConformanceComments.text.trim() : ''),
        directionRemarks: Value(deviated ? _directionRemarks.text.trim() : ''),
        directionRemarkTypeId: Value(_remarkTypeId),
        classOmitted: Value(_classOmitted),
        gradeOmitted: Value(_gradeOmitted),
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

  Future<void> _save(
    _LabelReference reference, {
    required bool completed,
  }) async {
    _autosaveTimer?.cancel();
    // Near the top of a long list, so usually scrolled out of it by the time
    // Complete is pressed, and validate() would pass straight over it:
    // checked from the controller, and the form taken back to it.
    // Seized — the labelling, or the grading underneath — the product is
    // taken, so the rest of the checklist is not asked for: only the
    // photographs (Ethan, 2026-09-30).
    final seized = _seizureDecision == SeizureDecision.seize || _gradingSeized;
    if (completed && !seized && _productDetails.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Fill in the Product Name before completing.'),
        ));
      await _missing.flag(
        context,
        const ['productName'],
        stillMissing: (_) => _productDetails.text.trim().isEmpty,
      );
      return;
    }
    if (completed &&
        !seized &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (completed) {
      // The original will not enable its completion switch until two label
      // photographs are on the record, and the label is what the whole
      // checklist is read against.
      final taken =
          (await widget.captureRepository.photosFor(_clientUuid)).length;
      if (PoultryRules.photographsOutstanding(taken)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(seized
                ? seizurePhotosOwed('the ${PoultryRules.requiredPhotos} label '
                    'photographs — $taken of ${PoultryRules.requiredPhotos} '
                    'taken')
                : 'Take ${PoultryRules.requiredPhotos} label photographs '
                    'before completing — $taken of '
                    '${PoultryRules.requiredPhotos} taken.'),
          ));
        await _missing.flag(context, const ['photos']);
        return;
      }
      _missing.clear();
      if (!await _gradingDone(
              hostSeized: _seizureDecision == SeizureDecision.seize) ||
          !mounted) {
        return;
      }
    } else if (_gradingToFollow) {
      await _gradingControl.save();
      if (!mounted) return;
    }
    if (completed) _finishing = true;
    setState(() => _saving = true);

    await _persist(completed: completed);
    if (!mounted) return;
    setState(() => _saving = false);

    final findings = PoultryRules.findings(
      items: _applicable(reference),
      compliantItemIds: _compliant,
    );

    // A finished checklist with deviations raises the rejection here, as
    // the grading checklist does. Until now the label's findings reached
    // the office with no notice behind them, and the correct-by date
    // FSA-SOP-APS-001 Annexure C sets had nowhere to go.
    if (completed && findings.isNotEmpty) {
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
          comments: Value(_nonConformanceComments.text.trim()),
          actionTaken: Value(_seizureDecision == SeizureDecision.seize
              ? 'Seizure under section 8 of the APS Act '
                  '(FSA-SOP-APS-001 Annexure C).'
              : 'Generated from poultry labelling findings.'),
          nonConformanceIds:
              Value(findings.map((f) => f.item.id).toSet().join(',')),
          // Annexure C's date, or the later one the inspector chose.
          correctByDate: Value(_correctBy),
        ),
      );
      if (!mounted) return;
    }

    // Seized: said so, and back to where the inspection was opened from.
    if (completed && seized) {
      announceSeizureDone(context);
      Navigator.of(context).pop(true);
      return;
    }

    // Inside a grouped inspection there is nothing to announce — the record
    // waits for the group's one sign-off.
    if (widget.visit == null) {
      await _announceSaved(completed: completed, findings: findings.length);
      if (!mounted) return;
    }
    // The grading, when asked for, was finished with it on this form.
    if (mounted) Navigator.of(context).pop(true);
  }

  /// What the grading underneath takes from this form, read as it is
  /// written.
  PoultryGradingHost _gradingHost() => (
        reasonId: _reasonId,
        locationId: _locationId,
        facilityName: _facilityName.text.trim(),
        tradingName: _tradingName.text.trim(),
        facilityAddress: _facilityAddress.text.trim(),
        facilityTelephone: _facilityTelephone.text.trim(),
        registrationNumber: _registrationNumber.text.trim(),
        contactPerson: _contactPerson.text.trim(),
        contactEmail: _contactEmail.text.trim(),
        productName: _productDetails.text.trim(),
        managerName: _managerName.text.trim(),
        managerEmail: _managerEmail.text.trim(),
        clientEmail: _clientEmail.text.trim(),
        clientEmail2: _clientEmail2.text.trim(),
      );

  /// YES shows the grading underneath the labelling; NO takes it off, and
  /// with it anything already graded — asked first when there is.
  Future<void> _setGrading(bool on) async {
    if (on) {
      setState(() => _gradingToFollow = true);
      return;
    }
    final graded = await widget.repository.inspectionByUuid(_gradingUuid);
    if (!mounted) return;
    if (graded != null) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove the grading?'),
          content: const Text(
            'The grading answers and the photographs taken for it are '
            'removed from this checklist.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (remove != true || !mounted) return;
      // Off the form first, so nothing still waiting to be kept writes the
      // grading back after it is removed.
      setState(() => _gradingToFollow = false);
      await WidgetsBinding.instance.endOfFrame;
      await widget.captureRepository.deleteGradingInspection(_gradingUuid);
      return;
    }
    setState(() => _gradingToFollow = false);
  }

  /// With grading answered YES, the grading is finished with the labelling:
  /// its own checks run and mark what is still to do.
  Future<bool> _gradingDone({bool hostSeized = false}) async {
    if (!_gradingToFollow) return true;
    // Outside a visit the checklist is signed here, and the grading with it.
    if (widget.visit == null) await _signGrading();
    if (!mounted) return false;
    // Scrolled past before it was ever built: brought on screen to be asked.
    if (!_gradingControl.attached) {
      await _missing.reveal(context, 'grading');
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;
    }
    return _gradingControl.finish(hostSeized: hostSeized);
  }

  /// The checklist's signatures, onto the grading record. Each image is its
  /// own copy, so removing the grading never takes the checklist's signature
  /// file with it.
  Future<void> _signGrading() async {
    final repo = widget.captureRepository;
    for (final s in await repo.signaturesFor(_clientUuid)) {
      var path = '';
      if (s.filePath.trim().isNotEmpty) {
        try {
          final copy = '${s.filePath}.grading.png';
          await File(s.filePath).copy(copy);
          path = copy;
        } on FileSystemException {
          continue;
        }
      }
      await repo.saveSignature(PoultrySignaturesCompanion.insert(
        recordUuid: _gradingUuid,
        role: s.role,
        signedName: Value(s.signedName),
        filePath: Value(path),
        declined: Value(s.declined),
        signedAt: s.signedAt,
      ));
    }
  }

  /// Takes the red off the photographs once enough of them are on the record.
  Future<void> _recheckPhotos() async {
    if (!_missing.flagged.contains('photos')) return;
    final taken =
        (await widget.captureRepository.photosFor(_clientUuid)).length;
    if (mounted && !PoultryRules.photographsOutstanding(taken)) {
      _missing.clear();
    }
  }

  Future<void> _announceSaved({
    required bool completed,
    required int findings,
  }) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(completed ? 'Checklist saved' : 'Draft saved'),
          content: Text(
            completed
                ? findings == 0
                    ? 'No deviations recorded. Send it from Inspection '
                        'Management when you have signal.'
                    : '$findings '
                        '${findings == 1 ? "deviation" : "deviations"} '
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

  void _toggle(int id) => setState(() {
        if (!_compliant.remove(id)) _compliant.add(id);
      });

  /// Unticking a row is the normal path; unticking the class or grade
  /// designation asks one further question, because Annexure C treats the
  /// two answers differently — a designation shown but wrong is a 30-day
  /// rectification, one not shown at all is a seizure.
  Future<void> _toggleRow(_LabelReference reference, int id) async {
    final item = reference.checklist.firstWhere((i) => i.id == id);
    final wasCompliant = _compliant.contains(id);
    if (wasCompliant && PoultryRules.isClassRow(item)) {
      final absent = await _askIndicatedAtAll('class designation');
      if (absent == null || !mounted) return;
      _classOmitted = absent;
    } else if (wasCompliant && PoultryRules.isGradeRow(item)) {
      final absent = await _askIndicatedAtAll('grade designation');
      if (absent == null || !mounted) return;
      _gradeOmitted = absent;
    } else if (!wasCompliant && PoultryRules.isClassRow(item)) {
      // Ticked back as compliant: the earlier answer no longer applies.
      _classOmitted = false;
    } else if (!wasCompliant && PoultryRules.isGradeRow(item)) {
      _gradeOmitted = false;
    }
    _toggle(id);
    await _applySop();
  }

  Future<bool?> _askIndicatedAtAll(String what) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${what[0].toUpperCase()}${what.substring(1)}'),
          content: Text(
            'Is the $what shown on the label at all?',
            style: const TextStyle(height: 1.4),
          ),
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

  /// The deviations on the rows that apply.
  Iterable<PoultryChecklistItemRef> _deviations(_LabelReference reference) =>
      PoultryRules.findings(
        items: _applicable(reference),
        compliantItemIds: _compliant,
      ).map((f) => f.item);

  /// FSA-SOP-APS-001, Annexure C: the rectification period follows from
  /// the deviations ticked, and a deviation the annexure seizes on puts the
  /// seizure question — once, on the premises.
  Future<void> _applySop({bool ask = true}) async {
    final reference = await _reference;
    if (!mounted) return;
    final days = PoultryRules.rectificationDays(
      deviations: _deviations(reference),
      classOmitted: _classOmitted,
      gradeOmitted: _gradeOmitted,
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

  Future<void> _askAboutSeizureIfNeeded(_LabelReference reference) async {
    final rows = PoultryRules.seizureFindings(
      deviations: _deviations(reference),
      classOmitted: _classOmitted,
      gradeOmitted: _gradeOmitted,
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
    final answer =
        await askAboutSeizure(context, reason: _seizureReason(rows));
    if (answer == null || !mounted) {
      _seizureAsked = false;
      return;
    }
    _answeredFindings = findings;
    setState(() => _seizureDecision = answer);
    // Seized: the Annexure E sheet is drawn up here, on the premises.
    if (answer == SeizureDecision.seize) {
      await recordSeizure(
        context,
        database: widget.repository.database,
        draft: SeizureDraft(
          recordUuid: _clientUuid,
          recordKind: 'poultry_label',
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
      // Seized: the product is taken, so the inspection ends here — only
      // its photographs are still asked for (Ethan, 2026-09-30).
      if (mounted) await _save(reference, completed: true);
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
      if (rows.any(PoultryRules.isLotRow))
        'no production lot code is indicated, so the consignment cannot be '
            'traced (Reg. 12)',
      if (rows.any(PoultryRules.isClassRow))
        'the class designation is not indicated at all (Reg. 8 and 9)',
      if (rows.any(PoultryRules.isGradeRow))
        'the grade designation is not indicated at all (Reg. 10)',
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
  String _periodHelper(_LabelReference reference) {
    final days = PoultryRules.rectificationDays(
      deviations: _deviations(reference),
      classOmitted: _classOmitted,
      gradeOmitted: _gradeOmitted,
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

  /// Back out of the form: the work waits as a draft. A record already
  /// finished is left as it was finished; only Complete changes it.
  Future<void> _leave() async {
    if (!_wasCompleted) {
      setState(() => _saving = true);
      await _persist(completed: false);
      // The grading underneath, kept with it.
      if (_gradingToFollow) await _gradingControl.save();
      if (!mounted) return;
      setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
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
          'Label/Container Checklist',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_LabelReference>(
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

  Widget _form(_LabelReference reference) {
    // Answered once at the door for the whole group: find this commodity's own
    // row for it instead of asking again. Runs on every build but settles on
    // the first; no setState, the value is read by the widgets below.
    //
    // Every time, a reopened draft included: the draft keeps the facility
    // type it was saved with, and matching only while it was empty left the
    // question on the form again each time the draft was reopened. The
    // visit's answer is the one that stands (Ethan, 2026-09-30).
    final doorType = widget.visit?.facilityType ?? '';
    if (doorType.isNotEmpty) {
      final i = FacilityTypeMatch.indexOf(
          doorType, reference.locations.map((l) => l.name).toList());
      if (i != null) {
        _locationId = reference.locations[i].id;
        _locationFromVisit = true;
      }
    }
    final doorReason = widget.visit?.inspectionReason ?? '';
    if (doorReason.isNotEmpty) {
      final i = InspectionReasonMatch.indexOf(
          doorReason, reference.reasons.map((r) => r.name).toList());
      if (i != null) {
        _reasonId = reference.reasons[i].id;
        _reasonFromVisit = true;
      }
    }

    List<PoultryChecklistItemRef> of(PoultryChecklistKind kind) => [
          for (final item in reference.checklist)
            if (item.kind == kind) item,
        ];

    return Form(
      key: _formKey,
      child: ListView(
        // Clear the system navigation bar: the submit button is the last
        // thing on the page, and the bar was drawing over it and taking the
        // tap — which dropped the inspector out of the app mid-save.
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          poultrySection('Inspection Details'),
          if (!_reasonFromVisit)
            poultryDropdown(
              label: 'Reason for Inspection',
              value: _reasonId,
              items: reference.reasons,
              onChanged: (v) => setState(() => _reasonId = v),
            ),
          // Inside a visit the facility type is the one chosen at the top of
          // it, and not asked again here (Ethan, 2026-09-30).
          if (!_locationFromVisit && widget.visit == null)
            poultryDropdown(
              label: 'Inspection Facility Type',
              value: _locationId,
              items: reference.locations,
              onChanged: (v) => setState(() => _locationId = v),
            ),
          // The synced premises directory, as on the egg form: pick a known
          // facility and its details fill themselves, or type a new name.
          // The facility is captured once, at the top of the grouped
          // inspection, so it is not asked for again on every record inside
          // it. The name and address still travel with the record.
          if (widget.visit == null) ...[
            SearchPickerField<EggFacility>(
              label: 'New Facility Name',
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
            poultryField(_tradingName, 'Name or Trading Name of New Facility'),
            // Searchable by facility name; a plain typed box with no
            // signal or no key (Ethan, 2026-10-08).
            AddressSearchField(
              controller: _facilityAddress,
              tokenProvider: widget.repository.storedToken,
              child: poultryField(_facilityAddress, 'Facility Address', lines: 2),
            ),
            poultryField(
              _facilityTelephone,
              'Facility Primary Contact Telephone/Cellphone Number',
              keyboard: TextInputType.phone,
            ),
            poultryField(_contactPerson, 'Representative Name'),
            poultryField(
              _contactEmail,
              'Representative Email Address',
              keyboard: TextInputType.emailAddress,
            ),
          ],
          // Asked here rather than inside the block above: the visit does not
          // capture it, so it is needed either way — and asking it in both
          // places put the same question on the screen twice, bound to the
          // one controller.
          poultryField(_registrationNumber, 'Registration Number (optional)'),
          // Required (Ethan, 2026-09-30): the label is read against the
          // product named here.
          MissingFieldAnchor(
            fields: _missing,
            id: 'productName',
            framed: false,
            listenable: _productDetails,
            child: poultryField(_productDetails, 'Product Name',
                required: true),
          ),

          poultryChecklist(
            title: 'Product Label',
            items: of(PoultryChecklistKind.labelInner),
            compliant: _compliant,
            onToggle: (id) => unawaited(_toggleRow(reference, id)),
          ),

          poultrySection('Outer Container Label'),
          poultrySwitch(
            label: 'Outer Container Label Present',
            value: _outerLabelsPresent,
            onChanged: (v) {
              setState(() {
                _outerLabelsPresent = v;
                for (final item in of(PoultryChecklistKind.labelOuter)) {
                  if (v) {
                    // Outer labelling starts Compliant, like every other
                    // row. Only the OFF branch existed, so a block opened a
                    // second time — or on a draft resumed with it off —
                    // came back with every row already a deviation.
                    _compliant.add(item.id);
                  } else {
                    // Ticks on rows that no longer apply would be carried
                    // into the record as compliance nobody assessed.
                    _compliant.remove(item.id);
                  }
                }
              });
              // Rows that stop applying stop counting, so the period and
              // the seizure question follow the switch.
              unawaited(_applySop());
            },
          ),
          if (_outerLabelsPresent)
            poultryChecklist(
              title: 'Outer Container Lettering',
              items: of(PoultryChecklistKind.labelOuter),
              compliant: _compliant,
              onToggle: (id) => unawaited(_toggleRow(reference, id)),
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
            onToggle: (id) => unawaited(_toggleRow(reference, id)),
          ),

          // The same picker the egg, raw and PMP forms use: a dropdown, an
          // Add, and the chosen particulars listed as chips. This form alone
          // still drew the Agency's list as a column of tick boxes, so the
          // one question looked different on every commodity (Ethan,
          // 2026-09-23). The picker carries its own heading.
          poultryRestrictedParticulars(
            context: context,
            options: reference.restricted,
            selected: _restricted,
            typed: _typedRestricted,
            shared: reference.shared,
            onChanged: () => setState(() {}),
            note: 'Add the restricted particulars that appear on the label. '
                'A label with none is normal. One the list does not have '
                'can be typed in.',
          ),

          MissingFieldAnchor(
            fields: _missing,
            id: 'photos',
            child: PoultryEvidenceSection(
            repository: widget.captureRepository,
            recordUuid: _clientUuid,
            kind: 'label',
            captureLabel: 'Take label photograph',
            guidance: 'Photograph the label and the container it is on. Show '
                'the class or grade designation, the packer, the production '
                'lot code and, where there is one, the outer container '
                'label.',
            // Two, as the original demands before it will let the checklist
            // be completed, and one spare for whatever the first two could
            // not fit in frame.
            minPhotos: PoultryRules.requiredPhotos,
            maxPhotos: PoultryRules.maxPhotos,
            // In a grouped inspection the manager and inspector sign once,
            // at the end, and those signatures fan out to every member.
            showSignatures: widget.visit == null,
            // A draft is persisted the moment evidence lands, so a photograph
            // never points at a record that was never saved.
            onChanged: () {
              unawaited(_persist(completed: false));
              unawaited(_recheckPhotos());
            },
          ),
          ),

          // Only with a deviation: with none there is no rejection, and no
          // non-conformance to remark on (Ethan, 2026-09-30).
          if (_deviated(reference)) ...[
            poultrySection('Rejection Form'),
            // A labelling checklist: its rejection is for labelling findings,
            // so the grading remarks picker the grading form carries is not
            // asked here.
            poultryField(
              _nonConformanceComments,
              'Labelling Non-Conformance Comments',
              lines: 3,
            ),
            poultryField(_directionRemarks, 'Added Remarks', lines: 2),
            // Opens on FSA-SOP-APS-001 Annexure C's date; the inspector may
            // move it later, never into the past (see CorrectByDateField).
            CorrectByDateField(
              value: _correctBy,
              sopDate: _sopCorrectBy,
              helperText: _periodHelper(reference),
              onChanged: _correctByChanged,
            ),
            // A seizure declined says nothing here: the rejection above
            // stands as it is (Ethan, 2026-09-30).
            if (_seizureDecision == SeizureDecision.seize) _seizureNotice(),
          ],

          // Underneath the labelling: whether this product is graded as
          // well. YES shows the grading and classification checklist here,
          // on this form; NO records the labelling only.
          MissingFieldAnchor(
            fields: _missing,
            id: 'grading',
            child: poultrySwitch(
              label: 'Grading and classification as well?',
              value: _gradingToFollow,
              onChanged: (v) => unawaited(_setGrading(v)),
              helper: 'YES shows the grading and classification checklist '
                  'below, for this product. NO records the labelling only.',
            ),
          ),
          if (_gradingToFollow)
            PoultryInspectionForm(
              key: ValueKey('grading:$_gradingUuid'),
              repository: widget.repository,
              captureRepository: widget.captureRepository,
              inspectorName: widget.inspectorName,
              existingUuid: _gradingUuid,
              visit: widget.visit,
              embedded: true,
              controller: _gradingControl,
              host: _gradingHost,
              onNoGrade: () => unawaited(_setGrading(false)),
              // Seized here, the grading below asks for nothing.
              hostSeized: _seizureDecision == SeizureDecision.seize,
              onSeized: () {
                _gradingSeized = true;
                unawaited(_save(reference, completed: true));
              },
            ),

          if (widget.visit == null) ...[
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
          // Signatures block — one tick-box, not two that can disagree.

          const SizedBox(height: 20),
          // No Save draft: going back keeps the work as a draft, and the
          // visit shows it in progress (Ethan, 2026-09-30).
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () => _save(reference, completed: true),
              child: Text(_saving ? 'Saving…' : 'Complete'),
            ),
          ),
        ],
      ),
    );
  }
}
