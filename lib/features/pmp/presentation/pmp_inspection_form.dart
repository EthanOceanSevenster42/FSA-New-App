import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/batch_number.dart';
import '../../../core/data/local_database.dart';
import '../../../core/data/restricted_particulars_catalogue.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../../../core/data/sample_number.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../../core/widgets/search_picker.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../../poultry/domain/poultry_rules.dart' show PoultryDesignationRef;
import '../../poultry/presentation/poultry_evidence_section.dart';
import '../../poultry/presentation/poultry_form_widgets.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../../eggs/presentation/new_directory_entry_sheet.dart';
import '../data/pmp_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../domain/pmp_rules.dart';
import '../../../core/widgets/correct_by_date_field.dart';

/// New PMP Inspection.
///
/// Field captions and section order are the original's, verbatim. The
/// tick-list is five sections, each behind its own "... Present" switch —
/// a section that is not present contributes nothing, because the requirement
/// does not arise. Switching a section off clears its ticks, so compliance
/// nobody assessed is never carried into the record.
class PmpInspectionForm extends StatefulWidget {
  const PmpInspectionForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.existingUuid,
    this.visit,
  });

  final PmpRepository repository;

  /// The shared evidence store (photographs and signatures), keyed on the
  /// record's uuid with kind `pmp`.
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;
  final String? existingUuid;

  /// Set when this record is one of a grouped inspection: the facility
  /// fields arrive filled, and the signatures are taken once at the end of
  /// the group.
  final VisitPrefill? visit;

  @override
  State<PmpInspectionForm> createState() => _PmpInspectionFormState();
}

class _Reference {
  _Reference({
    required this.reasons,
    required this.locations,
    required this.storageTypes,
    required this.producers,
    required this.products,
    required this.subClasses,
    required this.ingredients,
    required this.laboratories,
    required this.restricted,
    required this.shared,
    required this.remarks,
    required this.checklist,
    required this.facilities,
  });

  final List<PmpRef> reasons;
  final List<PmpRef> locations;
  final List<PmpRef> storageTypes;
  final List<PmpRef> producers;
  final List<PmpRef> products;
  final List<PmpRef> subClasses;
  final List<PmpRef> ingredients;
  final List<PmpRef> laboratories;
  final List<PmpRef> restricted;
  final List<String> shared;
  final List<PmpRef> remarks;
  final List<PmpChecklistItemRef> checklist;
  final List<EggFacility> facilities;
}

class _PmpInspectionFormState extends State<PmpInspectionForm> {
  late Future<_Reference> _reference;
  final _formKey = GlobalKey<FormState>();

  /// The required fields a refused save flagged, so the page can take the
  /// inspector to the first and mark each red.
  final _missing = MissingFields();

  late final String _clientUuid = widget.existingUuid ?? const Uuid().v4();

  int? _locationId;

  /// True when the door-side facility type settled [_locationId], so the
  /// form does not ask again.
  bool _locationFromVisit = false;
  int? _reasonId;

  /// True when the reason chosen at the door settled [_reasonId].
  bool _reasonFromVisit = false;
  int? _storageTypeId;
  int? _subClassId;
  int? _ingredientId;
  int? _laboratoryId;
  int? _remarkTypeId;

  final _facilityName = TextEditingController();
  final _tradingName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityTelephone = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _followUp = TextEditingController();
  final _producerName = TextEditingController();
  final _newProducerDetails = TextEditingController();
  final _newFacilityName = TextEditingController();
  final _newItemSizeG = TextEditingController();
  final _newItemBarcode = TextEditingController();
  final _productItem = TextEditingController();
  final _newProductItem = TextEditingController();
  final _batchNumber = TextEditingController();

  /// Watched so an empty batch box fills itself in with N/A the moment the
  /// inspector moves off it.
  final _batchFocus = FocusNode();

  /// Leaving the box empty fills in N/A, as it does on the egg form.
  void _normaliseBatch() {
    if (_batchFocus.hasFocus) return;
    final tidied = BatchNumber.tidy(_batchNumber.text);
    if (tidied == _batchNumber.text) return;
    setState(() => _batchNumber.text = tidied);
  }

  final _manuPackedDate = TextEditingController();
  final _primarySampleSize = TextEditingController();

  /// Particulars typed in because the Agency's list did not have them.
  final _typedRestricted = <String>{};
  final _newIngredient = TextEditingController();
  final _internalSampleNumber = TextEditingController();
  final _testSampleSize = TextEditingController();
  final _ingredientPercentage = TextEditingController();
  final _directionRemarks = TextEditingController();
  final _correctByDate = TextEditingController();
  final _nonConformanceComments = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _generalComments = TextEditingController();

  final _compliant = <int>{};
  final _restricted = <int>{};

  bool _markingPresent = false;
  bool _scalePresent = false;
  bool _containersPresent = false;
  bool _fridgePresent = false;
  bool _noticePresent = false;
  bool _restrictedPresent = false;
  bool _labelPackComplete = false;
  bool _isSampled = false;
  bool _recipeAvailable = false;
  bool _recipeComplete = false;
  bool _isCouriered = false;
  bool _labInfoComplete = false;
  bool _saving = false;

  /// Set once and restored on resume, so touching a draft does not move it
  /// between days and out from under the date filter that found it.
  late DateTime _inspectedAt = DateTime.now();
  String _waybill = '';
  DateTime? _correctBy;

  /// The annexure's own date for [_correctBy], and whether the inspector has
  /// moved the rejection to a later one of their choosing.
  DateTime? _sopCorrectBy;
  bool _correctByPicked = false;

  /// The date a reopened record was saved with, until the annexure's date is
  /// known to tell whether the inspector had chosen it.
  DateTime? _savedCorrectBy;

  /// The inspector's answer when the product-name row is unticked.
  bool _productNameAbsent = false;

  /// Whether the seizure question has been put on this visit to the form.
  bool _seizureAsked = false;
  SeizureDecision? _seizureDecision;

  /// The recipe rows, one per line: "<n>. <description> <pct>%".
  final _ingredients = <String>[];

  @override
  void initState() {
    super.initState();
    _batchFocus.addListener(_normaliseBatch);
    _applyVisitPrefill();
    _reference = _load();
    if (widget.existingUuid != null) _restore(widget.existingUuid!);
  }

  /// Fields the grouped inspection already knows arrive filled; only empty
  /// ones take the value, so a resumed draft keeps its own.
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
    // The producer named once on the visit; changed here only where
    // this product's differs.
    fill(_producerName, visit.producer);
  }

  static Set<int> _idSet(String csv) => {
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  Future<void> _restore(String uuid) async {
    final saved = await widget.repository.inspectionByUuid(uuid);
    if (saved == null || !mounted) return;
    setState(() {
      _inspectedAt = saved.inspectedAt;
      _waybill = saved.waybill;
      _locationId = saved.locationId;
      _reasonId = saved.reasonId;
      _storageTypeId = saved.storageTypeId;
      _subClassId = saved.subClassProductId;
      _ingredientId = saved.ingredientId;
      _laboratoryId = saved.laboratoryId;
      _remarkTypeId = saved.directionRemarkTypeId;
      _facilityName.text = saved.facilityName;
      _tradingName.text = saved.producerTradingName;
      _facilityAddress.text = saved.facilityAddress;
      _facilityTelephone.text = saved.facilityTelephone;
      _contactPerson.text = saved.contactPerson;
      _contactEmail.text = saved.contactPersonEmail;
      _followUp.text = saved.followUpDirectionParticulars;
      _producerName.text = saved.producerName;
      _newProducerDetails.text = saved.newProducerDetails;
      _newFacilityName.text = saved.newFacilityName;
      _newItemSizeG.text = saved.newItemSizeG;
      _newItemBarcode.text = saved.newItemBarcode;
      _productItem.text = saved.productItem;
      _newProductItem.text = saved.newProductItem;
      _batchNumber.text = saved.batchNumber;
      _manuPackedDate.text = saved.manufacturedPackedDate;
      _primarySampleSize.text = saved.primarySampleSize;
      _typedRestricted
        ..clear()
        ..addAll(TypedParticulars.unpack(saved.restrictedParticularsText));
      _newIngredient.text = saved.newIngredient;
      _internalSampleNumber.text = saved.internalSampleNumber;
      _testSampleSize.text = saved.testSampleSize;
      _directionRemarks.text = saved.directionRemarks;
      _correctBy = saved.correctByDate;
      _savedCorrectBy = saved.correctByDate;
      _correctByDate.text =
          saved.correctByDate == null ? '' : _dmy(saved.correctByDate!);
      _productNameAbsent = saved.productNameAbsent;
      _seizureDecision = SeizureDecision.of(saved.seizureDecision);
      _seizureAsked = _seizureDecision != null;
      _ingredients
        ..clear()
        ..addAll([
          for (final line in saved.ingredientPercentages.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ]);
      _nonConformanceComments.text = saved.nonConformanceComments;
      _managerName.text = saved.managerName;
      _managerEmail.text = saved.managerEmail;
      _clientEmail.text = saved.clientEmail;
      _clientEmail2.text = saved.clientEmail2;
      _generalComments.text = saved.generalComments;
      _markingPresent = saved.markingLabelsPresent;
      _scalePresent = saved.scaleLabelsPresent;
      _containersPresent = saved.containersPresent;
      _fridgePresent = saved.displayFridgePresent;
      _noticePresent = saved.noticeBoardsPresent;
      _restrictedPresent = saved.restrictedParticularsPresent;
      _labelPackComplete = saved.labelPackComplete;
      _isSampled = saved.isSampled;
      _recipeAvailable = saved.recipeAvailable;
      _recipeComplete = saved.recipeComplete;
      _isCouriered = saved.isCouriered;
      _labInfoComplete = saved.labInfoComplete;
      _compliant
        ..clear()
        ..addAll(_idSet(saved.compliantItemIds));
      _restricted
        ..clear()
        ..addAll(_idSet(saved.restrictedParticularIds));
    });
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
  void _startCompliant(List<PmpChecklistItemRef> checklist) {
    if (_compliant.isNotEmpty) return;
    _compliant.addAll([for (final item in checklist) item.id]);
  }

  Future<_Reference> _load() async {
    final repo = widget.repository;
    final checklist = await repo.checklistItems();
    _startCompliant(checklist);
    return _Reference(
      reasons: await repo.reasons(),
      locations: await repo.locations(),
      storageTypes: await repo.storageTypes(),
      producers: await repo.producers(),
      products: await repo.products(),
      subClasses: await repo.subClassProducts(),
      ingredients: await repo.ingredients(),
      laboratories: await repo.laboratories(),
      restricted: await repo.restrictedParticulars(),
      // Every commodity's list, so this form offers the same menu as the
      // rest.
      shared: await RestrictedParticularsCatalogue.names(repo.database),
      remarks: await repo.directionRemarks(),
      checklist: checklist,
      facilities: await repo.facilities(),
    );
  }

  @override
  void dispose() {
    _batchFocus.removeListener(_normaliseBatch);
    _batchFocus.dispose();
    for (final c in [
      _facilityName,
      _tradingName,
      _facilityAddress,
      _facilityTelephone,
      _contactPerson,
      _contactEmail,
      _followUp,
      _producerName,
      _newProducerDetails,
      _productItem,
      _newProductItem,
      _batchNumber,
      _manuPackedDate,
      _primarySampleSize,
      _newIngredient,
      _internalSampleNumber,
      _testSampleSize,
      _ingredientPercentage,
      _directionRemarks,
      _correctByDate,
      _nonConformanceComments,
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

  Set<PmpSection> get _presentSections => {
        if (_markingPresent) PmpSection.marking,
        if (_scalePresent) PmpSection.scale,
        if (_containersPresent) PmpSection.container,
        if (_fridgePresent) PmpSection.fridge,
        if (_noticePresent) PmpSection.notice,
      };

  /// Writes the form silently, so evidence can persist a draft the moment a
  /// photograph or signature lands.
  Future<void> _persist({required bool completed}) async {
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined = signatures.any((s) => s.role == 'no_client' && s.declined);

    await widget.repository.saveInspection(
      PmpInspectionsCompanion.insert(
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
        contactPerson: Value(_contactPerson.text.trim()),
        contactPersonEmail: Value(_contactEmail.text.trim()),
        followUpDirectionParticulars: Value(_followUp.text.trim()),
        producerName: Value(_producerName.text.trim()),
        newProducerDetails: Value(_newProducerDetails.text.trim()),
        newFacilityName: Value(_newFacilityName.text.trim()),
        newItemSizeG: Value(_newItemSizeG.text.trim()),
        newItemBarcode: Value(_newItemBarcode.text.trim()),
        productItem: Value(_productItem.text.trim()),
        newProductItem: Value(_newProductItem.text.trim()),
        batchNumber: Value(BatchNumber.forRecord(_batchNumber.text)),
        manufacturedPackedDate: Value(_manuPackedDate.text.trim()),
        storageTypeId: Value(_storageTypeId),
        primarySampleSize: Value(_primarySampleSize.text.trim()),
        markingLabelsPresent: Value(_markingPresent),
        scaleLabelsPresent: Value(_scalePresent),
        containersPresent: Value(_containersPresent),
        displayFridgePresent: Value(_fridgePresent),
        noticeBoardsPresent: Value(_noticePresent),
        compliantItemIds: Value(_compliant.join(',')),
        restrictedParticularsPresent: Value(_restrictedPresent),
        restrictedParticularIds: Value(_restricted.join(',')),
        restrictedParticularsText:
            Value(TypedParticulars.pack(_typedRestricted)),
        labelPackComplete: Value(_labelPackComplete),
        isSampled: Value(_isSampled),
        recipeAvailable: Value(_recipeAvailable),
        recipeComplete: Value(_recipeComplete),
        subClassProductId: Value(_subClassId),
        ingredientId: Value(_ingredientId),
        newIngredient: Value(_newIngredient.text.trim()),
        ingredientPercentages: Value(_ingredients.join('\n')),
        laboratoryId: Value(_laboratoryId),
        internalSampleNumber: Value(_internalSampleNumber.text.trim()),
        testSampleSize: Value(_testSampleSize.text.trim()),
        isCouriered: Value(_isCouriered),
        labInfoComplete: Value(_labInfoComplete),
        waybill: Value(_waybill),
        directionRemarkTypeId: Value(_remarkTypeId),
        directionRemarks: Value(_directionRemarks.text.trim()),
        correctByDate: Value(_correctBy),
        productNameAbsent: Value(_productNameAbsent),
        seizureDecision: Value(_seizureDecision?.stored ?? ''),
        nonConformanceComments: Value(_nonConformanceComments.text.trim()),
        managerName: Value(_managerName.text.trim()),
        managerEmail: Value(_managerEmail.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        clientEmail2: Value(_clientEmail2.text.trim()),
        noClientSignaturePresent: Value(declined),
        generalComments: Value(_generalComments.text.trim()),
      ),
    );
  }

  /// The required fields still empty, in page order, as ids for [_missing]
  /// with the message each is refused with.
  ///
  /// Read from the controllers rather than left to `Form.validate()`: the
  /// form is a lazy list, and a field scrolled off screen is not built, so
  /// `validate()` never sees it.
  List<({String id, String message})> _missingRequired() => [
        // Required on every commodity (Ethan, 2026-09-24).
        if (BatchNumber.missing(_batchNumber.text) case final batch?)
          (id: 'batchNumber', message: batch),
        if (_primarySizeIssue() case final size?)
          (id: 'primarySampleSize', message: size),
        if (_labSizeIssue() case final size?)
          (id: 'testSampleSize', message: size),
      ];

  /// Wraps a required field so a refused save can scroll to it and mark it.
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

  Future<void> _save(_Reference reference, {required bool completed}) async {
    if (completed) {
      // Marks whatever is on screen red; the list below finds the rest.
      final formValid = _formKey.currentState?.validate() ?? false;
      final missing = _missingRequired();
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(missing.first.message)));
        await _missing.flag(
          context,
          [for (final m in missing) m.id],
          stillMissing: (id) => _missingRequired().any((m) => m.id == id),
        );
        return;
      }
      if (!formValid) return;
    }
    if (completed &&
        (await widget.captureRepository.photosFor(_clientUuid)).isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content:
              Text('Capture at least one inspection photo before completing.'),
        ));
      await _missing.flag(context, const ['photos']);
      return;
    }
    if (completed) _missing.clear();
    setState(() => _saving = true);
    await _persist(completed: completed);
    if (!mounted) return;
    setState(() => _saving = false);

    final findings = PmpRules.findings(
      items: reference.checklist,
      present: _presentSections,
      compliantItemIds: _compliant,
    );

    // The original raises the direction inside the inspection save — a
    // deviated consignment never leaves without its notice on record.
    if (completed && findings.isNotEmpty) {
      await _spawnDirection(reference, findings);
      if (!mounted) return;
    }

    // Inside a grouped inspection there is nothing to announce — the record
    // waits for the group's one sign-off, so go straight back to the visit.
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
                      'recorded. A rejection has been issued — it is '
                      'filed under Rejection Management.'
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

  /// Unticking a row is the normal path; unticking the *product name* asks
  /// one further question, because Annexure B treats the two answers
  /// differently — a name shown but deficient is a 30-day rectification, a
  /// name not shown at all is a seizure.
  Future<void> _toggleChecklistItem(PmpChecklistItemRef item) async {
    final wasCompliant = _compliant.contains(item.id);
    if (wasCompliant && PmpRules.isProductNameRow(item)) {
      final absent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Product name'),
          content: const Text(
            'Is the appropriate product name shown on the label at all?',
            style: TextStyle(height: 1.4),
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
      if (absent == null || !mounted) return;
      _productNameAbsent = absent;
    } else if (!wasCompliant && PmpRules.isProductNameRow(item)) {
      // Ticked back as compliant: the earlier answer no longer applies.
      _productNameAbsent = false;
    }
    _toggle(item.id);
    await _applySop();
  }

  /// FSA-SOP-APS-001, Annexure B: the rectification period follows from
  /// the deviations ticked, and a deviation the annexure seizes on puts the
  /// seizure question — once, on the premises.
  Future<void> _applySop() async {
    final reference = await _reference;
    if (!mounted) return;
    final days = PmpRules.rectificationDays(
      items: reference.checklist,
      present: _presentSections,
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
    );
    setState(() {
      _sopCorrectBy =
          PmpRules.correctByDate(inspectedAt: _inspectedAt, days: days);
      final saved = _savedCorrectBy;
      if (saved != null) {
        _savedCorrectBy = null;
        _correctByPicked = CorrectByDateField.isFuture(saved) &&
            !DateUtils.isSameDay(saved, _sopCorrectBy);
        if (_correctByPicked) _correctBy = saved;
      }
      // The inspector's own date stands while the annexure still gives a
      // period to move; none, or an immediate one, puts the annexure's back.
      if (!_correctByPicked || !CorrectByDateField.isFuture(_sopCorrectBy)) {
        _correctBy = _sopCorrectBy;
        _correctByPicked = false;
      }
      _correctByDate.text = _correctBy == null ? '' : _dmy(_correctBy!);
    });
    await _askAboutSeizureIfNeeded(reference);
  }

  Future<void> _askAboutSeizureIfNeeded(_Reference reference) async {
    if (_seizureAsked) return;
    final rows = PmpRules.seizureFindings(
      items: reference.checklist,
      present: _presentSections,
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
    );
    if (rows.isEmpty || !mounted) return;
    _seizureAsked = true;
    final answer =
        await askAboutSeizure(context, reason: _seizureReason(rows));
    if (answer == null || !mounted) {
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
          recordUuid: _clientUuid,
          recordKind: 'pmp',
          visitUuid: widget.visit?.uuid ?? '',
          inspectorUsername: widget.inspectorName,
          natureOfDeviation: _seizureReason(rows),
          regulation: 'R.1283 of 4 October 2019',
          clientName: _facilityName.text,
          clientAddress: _facilityAddress.text,
          clientTelephone: _facilityTelephone.text,
          clientEmail: _contactEmail.text,
          inspectionPoint: _locationName(reference),
          productName: _newProductItem.text.trim().isNotEmpty
              ? _newProductItem.text
              : _productItem.text,
          receiverName: _managerName.text,
        ),
      );
    }
  }

  /// The facility type chosen at the door, by name.
  String _locationName(_Reference reference) => reference.locations
      .where((l) => l.id == _locationId)
      .map((l) => l.name)
      .firstWhere((_) => true, orElse: () => '');

  /// Why this consignment is to be seized, in the annexure's terms.
  String _seizureReason(List<PmpChecklistItemRef> rows) {
    final reasons = <String>[
      if (rows.any(PmpRules.isBatchRow))
        'no batch code is indicated, so the consignment cannot be traced',
      if (rows.any(PmpRules.isProductNameRow))
        'the product name is not indicated at all',
      if (rows.any((r) => r.section == PmpSection.container))
        'the container does not comply with Regulation 7',
    ];
    return 'Seizure under FSA-SOP-APS-001 Annexure B: ${reasons.join('; ')}.';
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
    final days = PmpRules.rectificationDays(
      items: reference.checklist,
      present: _presentSections,
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
    );
    if (days == null) return 'Set by FSA-SOP-APS-001 Annexure B from the deviations ticked.';
    return '${PmpRules.periodLabel(days)}, per FSA-SOP-APS-001 Annexure B, '
        'counted from the inspection date.';
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
                'consignment (FSA-SOP-APS-001 Annexure B).'
            : 'Seizure declined on the premises; the rejection stands and is '
                'to be put right immediately.',
        style: TextStyle(color: colour, fontSize: 13, height: 1.4),
      ),
    );
  }

  /// Whether the ticked checklist demands a direction — the original shows
  /// the Direction Form block only while a deviation stands.
  bool _directionPresent(_Reference reference) => PmpRules.findings(
        items: reference.checklist,
        present: _presentSections,
        compliantItemIds: _compliant,
      ).isNotEmpty;

  /// Raises (or refreshes) the direction for this inspection, copying the
  /// client and product particulars onto the notice the way the original's
  /// SaveDirection does. Non-conformance ids are each deviated row's
  /// position within its own section — the original's bitmask arithmetic,
  /// cross-section aliasing quirks included.
  Future<void> _spawnDirection(
    _Reference reference,
    List<PmpChecklistItemRef> findings,
  ) async {
    final existing =
        await widget.repository.directionForInspection(_clientUuid);
    final bySection = <PmpSection, List<PmpChecklistItemRef>>{};
    for (final item in reference.checklist) {
      bySection.putIfAbsent(item.section, () => []).add(item);
    }
    final findingIds = {for (final f in findings) f.id};
    final positions = <int>[];
    for (final section in PmpSection.values) {
      final items = bySection[section] ?? const [];
      for (var i = 0; i < items.length; i++) {
        if (findingIds.contains(items[i].id)) positions.add(i + 1);
      }
    }
    await widget.repository.saveDirection(
      PmpDirectionsCompanion.insert(
        clientUuid: existing?.clientUuid ?? const Uuid().v4(),
        issuedAt: existing?.issuedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        status: const Value('completed'),
        sourceInspectionUuid: Value(_clientUuid),
        facilityName: Value(_facilityName.text.trim()),
        clientName: Value(_contactPerson.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        remarkTypeId: Value(_remarkTypeId),
        remarks: Value(_directionRemarks.text.trim()),
        comments: Value(_nonConformanceComments.text.trim()),
        nonConformanceIds: Value(positions.join(',')),
        producerName: Value(_producerName.text.trim()),
        newProducerName: Value(_newProducerDetails.text.trim()),
        batchNumber: Value(BatchNumber.forRecord(_batchNumber.text)),
        manufacturedPackedDate: Value(_manuPackedDate.text.trim()),
        primarySampleSize: Value(_primarySampleSize.text.trim()),
        restrictedParticularIds: Value(_restricted.join(',')),
        isUploaded: const Value(false),
      ),
    );
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// "Add" on the ingredient recipe: the picked (or new) ingredient plus its
  /// percentage becomes a numbered row, and the entry resets for the next
  /// one — the original's flow, with its "Incomplete ingredient details"
  /// refusal when either half is missing.
  void _addIngredient(_Reference reference) {
    final pct = double.tryParse(_ingredientPercentage.text.trim());
    final newText = _newIngredient.text.trim();
    final picked = [
      for (final i in reference.ingredients)
        if (i.id == _ingredientId) i,
    ];
    final description = newText.isNotEmpty
        ? newText
        : picked.isEmpty
            ? ''
            : picked.first.name;
    if (pct == null || pct <= 0 || description.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Incomplete ingredient details'),
            backgroundColor: AppColors.ink,
          ),
        );
      return;
    }
    setState(() {
      _ingredients.add(
        '${_ingredients.length + 1}. $description '
        '${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%',
      );
      _ingredientPercentage.clear();
      _newIngredient.clear();
      _ingredientId = null;
    });
  }

  List<PoultryDesignationRef> _asRefs(List<PmpRef> items) =>
      [for (final i in items) PoultryDesignationRef(id: i.id, name: i.name)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Processed Meat Product Inspection',
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
            return const PoultryNoRules();
          }
          return _form(reference);
        },
      )),
    );
  }

  /// One gated section, drawn as raw draws it (Ethan, 2026-09-25): the
  /// switch, then the block's own title and every one of its rows. The rows
  /// stay on screen with the section switched off, greyed and not tickable,
  /// so an inspector can read what the block asks before deciding whether
  /// it applies — rather than switching each block on just to see it.
  Widget _gatedChecklist({
    required String switchLabel,
    required String blockTitle,
    required bool present,
    required ValueChanged<bool> onChanged,
    required List<PmpChecklistItemRef> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poultrySwitch(
          label: switchLabel,
          value: present,
          onChanged: (on) {
            setState(() {
              onChanged(on);
              for (final item in items) {
                if (on) {
                  // Every requirement starts Compliant and the inspector
                  // marks the ones the product fails, as raw and the egg
                  // form work.
                  _compliant.add(item.id);
                } else {
                  // Ticks on rows that no longer apply would carry
                  // compliance nobody assessed into the record.
                  _compliant.remove(item.id);
                }
              }
            });
            // Rows taken off the plan change what the annexure prescribes.
            unawaited(_applySop());
          },
        ),
        if (present)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Every requirement starts Compliant. Mark only the ones the '
              'product fails.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(
            blockTitle.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.ink,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            'Labelling requirement  ·  Regulation  ·  Min lettering (mm)  —  '
            'tick for No Deviation',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ),
        Opacity(
          opacity: present ? 1 : 0.45,
          child: Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.description,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            if (_note(item) != null) _note(item)!,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ComplianceSlider(
                        compliant: _compliant.contains(item.id),
                        enabled: present,
                        onChanged: (_) =>
                            unawaited(_toggleChecklistItem(item)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget? _note(PmpChecklistItemRef item) {
    final parts = [
      if (item.regulationReference.isNotEmpty) item.regulationReference,
      if (item.minLetteringHeight.isNotEmpty)
        'Min lettering ${item.minLetteringHeight} mm',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join('   •   '),
      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
    );
  }

  /// A one-line notice at the foot of the screen — the same voice every
  /// other form uses for "added" and "could not".
  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addFacility(String name) async {
    final values = await showNewDirectoryEntrySheet(context,
        title: 'New facility',
        subtitle: 'Add it here and use it for this inspection.',
        saveLabel: 'Add facility',
        fields: [
          DirectoryField(
              label: 'Name', key: 'name', initial: name, isRequired: true),
          const DirectoryField(label: 'Trading name', key: 'tradingName'),
          const DirectoryField(label: 'Address', key: 'address'),
          const DirectoryField(
              label: 'Telephone / cellphone',
              key: 'telephone',
              keyboardType: TextInputType.phone),
        ]);
    if (values == null || !mounted) return;
    setState(() {
      _facilityName.text = values['name']!;
      _newFacilityName.text = values['name']!;
      _tradingName.text = values['tradingName'] ?? '';
      _facilityAddress.text = values['address'] ?? '';
      _facilityTelephone.text = values['telephone'] ?? '';
    });
  }

  /// Fills in the internal sample number the first time the consignment
  /// is sampled; a number already on the record stays.
  Future<void> _numberTheSample() async {
    if (_internalSampleNumber.text.trim().isNotEmpty) return;
    final number = await SampleNumber.next(
      widget.repository.database,
      inspectorUsername: widget.inspectorName,
      exceptUuid: _clientUuid,
      on: _inspectedAt,
    );
    if (!mounted) return;
    setState(() => _internalSampleNumber.text = number);
  }

  /// The producer named once on the visit: shown there, not asked again.
  bool get _producerFromVisit =>
      (widget.visit?.producer ?? '').trim().isNotEmpty;

  /// Why the sample sizes cannot be saved as they are, or null when they can
  /// (Ethan, 2026-09-25): both are required, in grams.
  String? _primarySizeIssue() =>
      double.tryParse(_primarySampleSize.text.trim().replaceAll(',', '.')) ==
              null
          ? 'Primary Sample Size (g) is required — a number of grams.'
          : null;

  /// The lab sample size's half of [_primarySizeIssue]: asked only while the
  /// consignment is sampled.
  String? _labSizeIssue() => _isSampled &&
          double.tryParse(_testSampleSize.text.trim().replaceAll(',', '.')) ==
              null
      ? 'Lab Sample Size (g) is required — a number of grams.'
      : null;

  Future<void> _addProducer(String name) async {
    // No sheet: it held one box, already filled with the name just typed,
    // and asked the inspector to type it a second time to confirm it.
    final typed = name.trim();
    if (typed.isEmpty) return;
    try {
      final producer = await widget.repository.addProducer(typed);
      if (!mounted) return;
      setState(() {
        _producerName.text = producer.name;
        // Kept on the record as "new producer details" for the office's
        // reports; the directory row is the convenience on top.
        _newProducerDetails.text = producer.name;
        _reference = _load();
      });
      _toast('Producer added.');
    } on Object catch (e) {
      if (mounted) _toast('Could not add the producer. $e');
    }
  }

  Future<void> _addProduct(String name) async {
    final values = await showNewDirectoryEntrySheet(context,
        title: 'New processed meat product',
        subtitle: 'Add the product details to this inspection.',
        saveLabel: 'Add product',
        fields: [
          DirectoryField(
              label: 'Product name',
              key: 'name',
              initial: name,
              isRequired: true),
          const DirectoryField(
              label: 'Size (g)',
              key: 'size',
              keyboardType: TextInputType.number),
          const DirectoryField(label: 'Barcode', key: 'barcode'),
        ]);
    if (values == null || !mounted) return;
    try {
      final product = await widget.repository.addProduct(values['name']!);
      if (!mounted) return;
      setState(() {
        _productItem.text = product.name;
        _newProductItem.text = product.name;
        _newItemSizeG.text = values['size'] ?? '';
        _newItemBarcode.text = values['barcode'] ?? '';
        _reference = _load();
      });
      _toast('Product added.');
    } on Object catch (e) {
      if (mounted) _toast('Could not add the product. $e');
    }
  }

  Widget _form(_Reference reference) {
    // Chosen once at the door: find this commodity's row for it. Runs
    // on every build but settles on the first; no setState, the value
    // is read by the widgets built right below.
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
    List<PmpChecklistItemRef> of(PmpSection section) => [
          for (final item in reference.checklist)
            if (item.section == section) item,
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
          // Inside a visit the door has already asked both (Ethan,
          // 2026-09-24), so they are not asked again here.
          if (widget.visit == null && !_reasonFromVisit)
            poultryDropdown(
              label: 'Reason for Inspection',
              value: _reasonId,
              items: _asRefs(reference.reasons),
              onChanged: (v) => setState(() => _reasonId = v),
            ),
          if (widget.visit == null && !_locationFromVisit)
            poultryDropdown(
              label: 'Inspection Facility Type',
              value: _locationId,
              items: _asRefs(reference.locations),
              onChanged: (v) => setState(() => _locationId = v),
            ),
          // The facility is captured once, at the top of the grouped
          // inspection, so it is not asked for again on every record inside
          // it. The name and address still travel with the record; they are
          // filled in from the visit rather than typed here.
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
              addNewLabel: 'Add new facility',
              onAddNew: _addFacility,
            ),
          ],

          poultrySection('Product'),
          // Named once on the visit (Ethan, 2026-09-25); asked here only
          // when the visit did not name one.
          if (!_producerFromVisit)
            SearchPickerField<PmpRef>(
              label: 'Producer',
              controller: _producerName,
              options: reference.producers,
              optionLabel: (p) => p.name,
              minQueryLength: 1,
              onSelected: (p) => setState(() => _producerName.text = p.name),
              emptyHint: 'No producers on this device yet. Sync to download '
                  'the directory, or add one here.',
              addNewLabel: 'Add new producer',
              onAddNew: _addProducer,
            ),
          SearchPickerField<PmpRef>(
            label: 'Processed Meat Product Name',
            controller: _productItem,
            options: reference.products,
            optionLabel: (p) => p.name,
            minQueryLength: 1,
            onSelected: (p) => setState(() => _productItem.text = p.name),
            emptyHint: 'No product directory on this device yet.',
            addNewLabel: 'Add new product',
            onAddNew: _addProduct,
          ),
          _anchor(
            'batchNumber',
            listenable: _batchNumber,
            poultryField(
              _batchNumber,
              'Batch Number',
              required: true,
              focusNode: _batchFocus,
              helper: 'The number off the pack, or N/A if it has none.',
            ),
          ),
          // Was a typed box, the only date on any form without a calendar.
          // The same control as everywhere else now, stored as the
          // dd/MM/yyyy text the record has always kept.
          DateField(
            label: 'Manufactured/Packed Date',
            // Made or packed already — never a date still to come
            // (Ethan, 2026-09-24).
            lastDate: DateTime.now(),
            value: DateField.parseDmy(_manuPackedDate.text),
            onChanged: (d) => setState(
                () => _manuPackedDate.text = d == null ? '' : DateField.dmy(d)),
          ),
          poultryDropdown(
            label: 'Storage Method',
            value: _storageTypeId,
            items: _asRefs(reference.storageTypes),
            onChanged: (v) => setState(() => _storageTypeId = v),
          ),
          // "Follow Up Rejection Particulars" is no longer asked
          // (Ethan, 2026-09-24); a draft that held one keeps it.
          _anchor(
            'primarySampleSize',
            listenable: _primarySampleSize,
            poultryField(_primarySampleSize, 'Primary Sample Size (g)',
                required: true,
                keyboard:
                    const TextInputType.numberWithOptions(decimal: true)),
          ),

          poultrySection('Mark/Label Checklist'),
          _gatedChecklist(
            switchLabel: 'Marking Label Present',
            blockTitle: 'Label Marking',
            present: _markingPresent,
            onChanged: (v) => _markingPresent = v,
            items: of(PmpSection.marking),
          ),
          _gatedChecklist(
            switchLabel: 'Scale Label Present',
            blockTitle: 'Scale Label',
            present: _scalePresent,
            onChanged: (v) => _scalePresent = v,
            items: of(PmpSection.scale),
          ),
          _gatedChecklist(
            switchLabel: 'Container/Outer Container Present',
            blockTitle: 'Container and Outer-Container',
            present: _containersPresent,
            onChanged: (v) => _containersPresent = v,
            items: of(PmpSection.container),
          ),
          _gatedChecklist(
            switchLabel: 'Display Fridge Present',
            blockTitle: 'Display Fridge',
            present: _fridgePresent,
            onChanged: (v) => _fridgePresent = v,
            items: of(PmpSection.fridge),
          ),
          _gatedChecklist(
            switchLabel: 'Notice Boards, Signage, etc. Present',
            blockTitle: 'Notice Boards, Signage, etc.',
            present: _noticePresent,
            onChanged: (v) => _noticePresent = v,
            items: of(PmpSection.notice),
          ),
          poultrySwitch(
            label: 'Restricted Particulars Present',
            value: _restrictedPresent,
            onChanged: (v) => setState(() => _restrictedPresent = v),
          ),
          if (_restrictedPresent) ...[
            poultryRestrictedParticulars(
              context: context,
              options: _asRefs(reference.restricted),
              selected: _restricted,
              typed: _typedRestricted,
              shared: reference.shared,
              onChanged: () => setState(() {}),
              note: 'Add the restricted particulars that appear on the '
                  'label. A label with none is normal. One the list does '
                  'not have can be typed in.',
            ),
          ],
          poultrySwitch(
            label: 'Label and Pack Checklist Complete',
            value: _labelPackComplete,
            onChanged: (v) => setState(() => _labelPackComplete = v),
          ),

          poultrySection('Sample Ingredient Details'),
          poultrySwitch(
            label: 'Is Sampled',
            value: _isSampled,
            onChanged: (v) {
              setState(() => _isSampled = v);
              if (v) unawaited(_numberTheSample());
            },
          ),
          if (_isSampled) ...[
            poultrySwitch(
              label: 'Product Recipe is Available',
              value: _recipeAvailable,
              onChanged: (v) => setState(() => _recipeAvailable = v),
            ),
            // Nothing below is asked when the recipe is not available.
            //
            // A retailer very often does not hold the manufacturer's
            // recipe, and the ingredient rows sitting on screen read as a
            // demand: inspectors were asking the producer for a figure and
            // capturing whatever they were told, which puts a number on the
            // record that nobody can stand behind. The old system asked
            // only whether a complete recipe was available, and that is
            // what is asked first here (FSA, 2026-09-08).
            if (!_recipeAvailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No recipe to record. The sample still goes to the '
                  'laboratory and the inspection can be completed as it '
                  'is — the composition is determined from the analysis, '
                  'not from the label.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.muted, height: 1.35),
                ),
              ),
            if (_recipeAvailable) ...[
              poultrySwitch(
                label: 'Product Recipe is Complete',
                value: _recipeComplete,
                onChanged: (v) => setState(() => _recipeComplete = v),
              ),
              // What the rows are for, said where they are entered.
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Copy the recipe as the manufacturer states it — each '
                  'ingredient and the percentage shown on the recipe or the '
                  'label. Record only what is written down. If a figure is '
                  'not stated, leave it out rather than asking someone to '
                  'estimate it: the office checks the declared recipe '
                  'against the laboratory result, so a number that was '
                  'guessed is worse than no number at all.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.muted, height: 1.35),
                ),
              ),
              poultryDropdown(
                label: 'Sub Class Product Type',
                value: _subClassId,
                items: _asRefs(reference.subClasses),
                onChanged: (v) => setState(() => _subClassId = v),
              ),
              poultryDropdown(
                label: 'Ingredient Component',
                value: _ingredientId,
                items: _asRefs(reference.ingredients),
                onChanged: (v) => setState(() => _ingredientId = v),
              ),
              poultryField(_newIngredient, 'New Ingredient Details'),
              poultryField(
                _ingredientPercentage,
                'Ingredient Percentage (%)',
                keyboard: TextInputType.number,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => _addIngredient(reference),
                          child: const Text('Add'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _ingredients.isEmpty
                              ? null
                              : () => setState(_ingredients.clear),
                          child: const Text('Clear List'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_ingredients.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in _ingredients)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              line,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            poultrySection('Laboratory Details'),
            poultryDropdown(
              label: 'Laboratory',
              value: _laboratoryId,
              items: _asRefs(reference.laboratories),
              onChanged: (v) => setState(() => _laboratoryId = v),
            ),
            // Made up by the app, not typed (Ethan, 2026-09-25): one
            // number per sample this inspector takes today, for the bag
            // and the laboratory's sheet.
            poultryField(
              _internalSampleNumber,
              'Internal Sample Number',
              readOnly: true,
              helper: 'Generated for this sample — write it on the bag.',
            ),
            _anchor(
              'testSampleSize',
              listenable: _testSampleSize,
              poultryField(_testSampleSize, 'Lab Sample Size (g)',
                  required: true,
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true)),
            ),
            poultrySwitch(
              // The original's field is named IsCouriered but captioned
              // "Hand Delivered". The caption is what the inspector reads,
              // so it stays; the Pending Courier screen filters the field.
              label: 'Hand Delivered',
              value: _isCouriered,
              onChanged: (v) => setState(() => _isCouriered = v),
            ),
            poultrySwitch(
              label: 'Lab info is complete',
              value: _labInfoComplete,
              onChanged: (v) => setState(() => _labInfoComplete = v),
            ),
          ],

          _anchor(
            'photos',
            framed: true,
            PoultryEvidenceSection(
            repository: widget.captureRepository,
            recordUuid: _clientUuid,
            kind: 'pmp',
            photosTitle: 'Product Photos',
            captureLabel: 'Take Product Photos',
            guidance: 'Photograph the product as it is offered for sale. '
                'Show the label square-on, with the product name, the '
                'manufacturer or packer and the batch code readable.',
            // In a grouped inspection the manager and inspector sign once,
            // at the end, and those signatures fan out to every member.
            showSignatures: widget.visit == null,
            onChanged: () => unawaited(_persist(completed: false)),
          ),
          ),

          if (_directionPresent(reference)) ...[
            poultrySection('Rejection Form'),
            poultryDropdown(
              label: 'Label/Pack Rejection Remarks',
              value: _remarkTypeId,
              items: _asRefs(reference.remarks),
              onChanged: (v) => setState(() => _remarkTypeId = v),
            ),
            poultryField(_directionRemarks, 'List of Added Remarks', lines: 2),
            // Opens on FSA-SOP-APS-001 Annexure C's date; the inspector may move it
            // later, never into the past (see CorrectByDateField).
            CorrectByDateField(
              value: _correctBy,
              sopDate: _sopCorrectBy,
              helperText: _periodHelper(reference),
              onChanged: _correctByChanged,
            ),
            if (_seizureDecision != null) _seizureNotice(),
            poultryField(
              _nonConformanceComments,
              'Non-Conformance Comments',
              lines: 3,
            ),
          ],

          if (widget.visit == null) ...[
            poultrySection('Signatures Control'),
            poultryField(_managerName, 'Authorised Manager name'),
            poultryField(
              _managerEmail,
              'Manager Email address',
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
