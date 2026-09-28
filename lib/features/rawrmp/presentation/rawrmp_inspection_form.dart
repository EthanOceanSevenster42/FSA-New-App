import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/required_label.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../../core/data/batch_number.dart';
import '../../../core/data/local_database.dart';
import '../../../core/data/restricted_particulars_catalogue.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/search_picker.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../../poultry/domain/poultry_rules.dart' show PoultryDesignationRef;
import '../../poultry/presentation/poultry_evidence_section.dart';
import '../../poultry/presentation/poultry_form_widgets.dart';
import '../data/rawrmp_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../domain/composition_checklist.dart';
import '../domain/raw_record_kind.dart';
import '../../../core/data/sample_number.dart';
import '../../visits/domain/visit_prefill.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';
import '../../eggs/presentation/new_directory_entry_sheet.dart';
import '../domain/rawrmp_rules.dart';

/// New Raw Red Meat Product Inspection.
///
/// Field captions and section order are the original's, verbatim — including
/// "Request Calcuim Content Test (for MRM only)". The tick-list is five
/// sections, each behind its own "... Present" switch — a section that is not
/// present contributes nothing, because the requirement does not arise.
/// Switching a section off clears its ticks, so compliance nobody assessed is
/// never carried into the record.
class RawRmpInspectionForm extends StatefulWidget {
  const RawRmpInspectionForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
    this.existingUuid,
    this.visit,
    this.recordKind = RawRecordKind.both,
  });

  final RawRmpRepository repository;

  /// Which record a new one is. A resumed record keeps its own.
  final RawRecordKind recordKind;

  /// The shared evidence store (photographs and signatures), keyed on the
  /// record's uuid with kind `rawrmp`.
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;
  final String? existingUuid;

  /// Set when this record is one of a grouped inspection: the facility
  /// fields arrive filled, and the signatures are taken once at the end of
  /// the group.
  final VisitPrefill? visit;

  @override
  State<RawRmpInspectionForm> createState() => _RawRmpInspectionFormState();
}

class _Reference {
  _Reference({
    required this.reasons,
    required this.locations,
    required this.storageTypes,
    required this.producers,
    required this.products,
    required this.laboratories,
    required this.sampleCategories,
    required this.restricted,
    required this.shared,
    required this.remarks,
    required this.checklist,
    required this.facilities,
  });

  final List<RawRmpRef> reasons;
  final List<RawRmpRef> locations;
  final List<RawRmpRef> storageTypes;
  final List<RawRmpRef> producers;
  final List<RawRmpRef> products;
  final List<RawRmpRef> laboratories;
  final List<RawRmpRef> sampleCategories;
  final List<RawRmpRef> restricted;
  final List<String> shared;
  final List<RawRmpRef> remarks;
  final List<RawRmpChecklistItemRef> checklist;
  final List<EggFacility> facilities;
}

class _RawRmpInspectionFormState extends State<RawRmpInspectionForm> {
  late Future<_Reference> _reference;
  final _formKey = GlobalKey<FormState>();

  late final String _clientUuid = widget.existingUuid ?? const Uuid().v4();

  int? _locationId;

  /// True when the door-side facility type settled [_locationId], so the
  /// form does not ask again.
  bool _locationFromVisit = false;
  int? _reasonId;

  /// True when the reason chosen at the door settled [_reasonId].
  bool _reasonFromVisit = false;
  int? _storageTypeId;
  int? _laboratoryId;

  /// Every testing category the sample goes for.
  final _sampleCategoryIds = <int>{};
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

  final _manuPackedDate = TextEditingController();

  /// Particulars typed in because the Agency's list did not have them.
  final _typedRestricted = <String>{};
  final _internalSampleNumber = TextEditingController();
  final _testSampleSize = TextEditingController();
  final _primarySampleSize = TextEditingController();

  /// The remarks added to the direction, in the order they were added.
  /// Stored as one per line on the record.
  final _addedRemarks = <String>[];
  final _correctByDate = TextEditingController();
  final _nonConformanceComments = TextEditingController();
  final _distanceTravelled = TextEditingController();
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientEmail2 = TextEditingController();
  final _generalComments = TextEditingController();

  /// SOP-APS-RAW-003 — the compositional requirements checklist: the site
  /// representative's position, nine deviation answers with their
  /// contribution in grams and remarks, and the comments/actions under them.
  final _representativePosition = TextEditingController();
  final _compositionComments = TextEditingController();
  List<CompositionAnswer> _composition = CompositionChecklist.blank();
  final _compositionGrams = List.generate(
      CompositionChecklist.items.length, (_) => TextEditingController());

  /// Total Meat Content: the meat and all the other ingredients, in
  /// grams. The percentage is worked out from them, not typed.
  final _meatGrams = TextEditingController();
  final _otherGrams = TextEditingController();
  final _compositionRemarks = List.generate(
      CompositionChecklist.items.length, (_) => TextEditingController());

  final _compliant = <int>{};

  /// Set when the inspector says the product name is not indicated at
  /// all, which makes the consignment a seizure rather than a deviation.
  bool _productNameAbsent = false;

  /// How many product photographs exist. The original will not open the
  /// checklist until the front and back shots are both taken.
  int _photoCount = 0;
  final _restricted = <int>{};

  bool _markingPresent = false;
  bool _scalePresent = false;
  bool _containersPresent = false;
  bool _fridgePresent = false;
  bool _noticePresent = false;
  bool _restrictedPresent = false;
  bool _labelPackComplete = false;
  bool _isSampled = false;
  late RawRecordKind _kind = widget.recordKind;
  bool _calciumTestRequired = false;
  bool _isCouriered = false;
  bool _labInfoComplete = false;
  bool _saving = false;

  /// Set once and restored on resume, so touching a draft does not move it
  /// between days and out from under the date filter that found it.
  late DateTime _inspectedAt = DateTime.now();
  String _waybill = '';
  DateTime? _correctBy;

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
    // The two extra recipients are asked once on the visit; the record still
    // carries them, because that is what the office emails from.
    fill(_clientEmail, visit.additionalEmail1);
    fill(_clientEmail2, visit.additionalEmail2);
  }

  static Set<int> _idSet(String csv) => {
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _restore(String uuid) async {
    final saved = await widget.repository.inspectionByUuid(uuid);
    if (saved == null || !mounted) return;
    setState(() {
      _inspectedAt = saved.inspectedAt;
      _waybill = saved.waybill;
      _locationId = saved.locationId;
      _reasonId = saved.reasonId;
      _storageTypeId = saved.storageTypeId;
      _laboratoryId = saved.laboratoryId;
      _sampleCategoryIds
        ..clear()
        ..addAll(saved.sampleCategoryIds.trim().isEmpty
            ? [if (saved.sampleCategoryId != null) saved.sampleCategoryId!]
            : _idSet(saved.sampleCategoryIds));
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
      _typedRestricted
        ..clear()
        ..addAll(TypedParticulars.unpack(saved.restrictedParticularsText));
      _internalSampleNumber.text = saved.internalSampleNumber;
      _testSampleSize.text = saved.testSampleSize;
      _primarySampleSize.text = saved.primarySampleSize;
      _addedRemarks
        ..clear()
        ..addAll(saved.directionRemarks
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty));
      _correctBy = saved.correctByDate;
      _correctByDate.text =
          saved.correctByDate == null ? '' : _dmy(saved.correctByDate!);
      _nonConformanceComments.text = saved.nonConformanceComments;
      _distanceTravelled.text = saved.distanceTravelledKm == null
          ? ''
          : saved.distanceTravelledKm.toString();
      _managerName.text = saved.managerName;
      _managerEmail.text = saved.managerEmail;
      _clientEmail.text = saved.clientEmail;
      _clientEmail2.text = saved.clientEmail2;
      _generalComments.text = saved.generalComments;
      _representativePosition.text = saved.representativePosition;
      _compositionComments.text = saved.compositionComments;
      _composition =
          CompositionChecklist.decode(saved.compositionChecklistJson);
      for (var i = 0; i < _composition.length; i++) {
        _compositionGrams[i].text = _composition[i].contributionGrams;
        _compositionRemarks[i].text = _composition[i].remarks;
      }
      {
        final total = _composition[CompositionChecklist.totalMeatIndex];
        _meatGrams.text = total.meatGrams;
        _otherGrams.text = total.otherGrams;
      }
      _markingPresent = saved.markingLabelsPresent;
      _scalePresent = saved.scaleLabelsPresent;
      _containersPresent = saved.containersPresent;
      _fridgePresent = saved.displayFridgePresent;
      _noticePresent = saved.noticeBoardsPresent;
      _restrictedPresent = saved.restrictedParticularsPresent;
      _labelPackComplete = saved.labelPackComplete;
      _isSampled = saved.isSampled;
      _kind = RawRecordKind.of(saved.recordKind);
      _calciumTestRequired = saved.calciumTestRequired;
      _isCouriered = saved.isCouriered;
      _labInfoComplete = saved.labInfoComplete;
      _productNameAbsent = saved.productNameAbsent;
      _seizureDecision = SeizureDecision.of(saved.seizureDecision);
      _seizureAsked = _seizureDecision != null;
      unawaited(_refreshPhotoCount());
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
  void _startCompliant(List<RawRmpChecklistItemRef> checklist) {
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
      laboratories: await repo.laboratories(),
      sampleCategories: await repo.sampleCategories(),
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
      _internalSampleNumber,
      _testSampleSize,
      _primarySampleSize,
      _correctByDate,
      _nonConformanceComments,
      _distanceTravelled,
      _managerName,
      _managerEmail,
      _clientEmail,
      _clientEmail2,
      _generalComments,
      _representativePosition,
      _compositionComments,
      ..._compositionGrams,
      ..._compositionRemarks,
      _meatGrams,
      _otherGrams,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Set<RawRmpSection> get _presentSections => {
        if (_markingPresent) RawRmpSection.marking,
        if (_scalePresent) RawRmpSection.scale,
        if (_containersPresent) RawRmpSection.container,
        if (_fridgePresent) RawRmpSection.fridge,
        if (_noticePresent) RawRmpSection.notice,
      };

  /// Writes the form silently, so evidence can persist a draft the moment a
  /// photograph or signature lands.
  /// The checklist as answered right now — the chips' answers with the
  /// percentages and remarks as typed.
  List<CompositionAnswer> _compositionSnapshot() => [
        for (var i = 0; i < CompositionChecklist.items.length; i++)
          CompositionAnswer(
            deviation: _composition[i].deviation,
            contributionGrams: i == CompositionChecklist.totalMeatIndex
                ? _totalMeatText
                : _compositionGrams[i].text.trim(),
            remarks: _compositionRemarks[i].text.trim(),
            meatGrams: i == CompositionChecklist.totalMeatIndex
                ? _meatGrams.text.trim()
                : '',
            otherGrams: i == CompositionChecklist.totalMeatIndex
                ? _otherGrams.text.trim()
                : '',
          ),
      ];

  /// FSA's Compositional Requirements Checklist (SOP-APS-RAW-003), answered
  /// on the inspection so the document can be generated from it. Optional:
  /// the regulation applies to certain raw processed meat products only, and
  /// an untouched checklist produces no document.
  List<Widget> _compositionFields() => [
        poultrySection('Compositional Requirements Checklist'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Not part of sampling — this is the compositional standard the '
            'product is sold against (Reg. 5 of R.2410, SOP-APS-RAW-003). '
            'Answer a row only where you are judging that requirement, and '
            'give the Contribution in grams where the row has a quantity to '
            'it. The Compositional Checklist document is written from what '
            'you put here. Leave the whole block untouched if you are not '
            'assessing composition — nothing is required and no document is '
            'produced.',
            style:
                TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
          ),
        ),
        poultryField(_representativePosition, 'Position of Representative'),
        for (var i = 0; i < CompositionChecklist.items.length; i++)
          ..._compositionRow(i),
        poultryField(_compositionComments, 'Comments/Actions', lines: 3),
      ];

  /// One requirement, in the form's own furniture: the same choice chips
  /// the Sampling question uses for Deviation Yes/No, then the percentage
  /// and remark as ordinary labelled fields.
  List<Widget> _compositionRow(int i) {
    final answer = _composition[i];
    void setDeviation(bool? value) {
      setState(() {
        _composition = [
          for (var j = 0; j < _composition.length; j++)
            j == i
                ? CompositionAnswer(
                    deviation: value,
                    contributionGrams: _composition[j].contributionGrams,
                    remarks: _composition[j].remarks,
                  )
                : _composition[j],
        ];
      });
      // A compositional deviation is one Annexure A seizes on.
      unawaited(_applySop());
    }
    return [
      // The same Compliant/Deviation slide every other checklist in the app
      // uses. This block asked the identical question through a different
      // control — two chips reading "Deviation - Yes" and "Deviation - No" —
      // so the answer looked different depending on which list you were on.
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${i + 1}. ${CompositionChecklist.items[i]}',
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 12),
            ComplianceSlider(
              // Unanswered reads as compliant here, as it does elsewhere;
              // the block is optional and an untouched row is not a finding.
              compliant: answer.deviation != true,
              onChanged: (isCompliant) => setDeviation(!isCompliant),
            ),
          ],
        ),
      ),
      if (i == CompositionChecklist.totalMeatIndex)
        ..._totalMeatFields()
      else
        poultryField(_compositionGrams[i], 'Contribution (g)',
            keyboard: const TextInputType.numberWithOptions(decimal: true)),
      poultryField(_compositionRemarks[i], 'Remarks'),
    ];
  }

  /// The worked-out total meat content, or empty until both amounts are in.
  String get _totalMeatText {
    final percent = CompositionChecklist.totalMeatPercent(
        _meatGrams.text, _otherGrams.text);
    return percent == null ? '' : CompositionChecklist.percentText(percent);
  }

  /// Total Meat Content is worked out rather than typed, the way inspectors
  /// did it by hand: meat ÷ (meat + all other ingredients) × 100.
  List<Widget> _totalMeatFields() {
    const grams = TextInputType.numberWithOptions(decimal: true);
    final result = _totalMeatText;
    return [
      poultryField(_meatGrams, 'Meat (g)',
          keyboard: grams, onChanged: (_) => setState(() {})),
      poultryField(_otherGrams, 'All other ingredients (g)',
          keyboard: grams, onChanged: (_) => setState(() {})),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Text(
          result.isEmpty
              ? 'Total meat content = meat ÷ (meat + all other ingredients) '
                  '× 100. Enter both amounts to work it out.'
              : 'Total meat content: $result',
          style: result.isEmpty
              ? TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35)
              : const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    ];
  }

  Future<void> _persist({required bool completed}) async {
    final signatures =
        await widget.captureRepository.signaturesFor(_clientUuid);
    final declined = signatures.any((s) => s.role == 'no_client' && s.declined);

    await widget.repository.saveInspection(
      RawRmpInspectionsCompanion.insert(
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
        recordKind: Value(_kind.stored),
        // A compositional record carries no labelling or sampling answers,
        // so nothing downstream reads it as a labelling inspection: no
        // labelling sheet, no sampling sheet, no findings, no rejection.
        markingLabelsPresent: Value(_labelling && _markingPresent),
        scaleLabelsPresent: Value(_labelling && _scalePresent),
        containersPresent: Value(_labelling && _containersPresent),
        displayFridgePresent: Value(_labelling && _fridgePresent),
        noticeBoardsPresent: Value(_labelling && _noticePresent),
        compliantItemIds: Value(_labelling ? _compliant.join(',') : ''),
        productNameAbsent: Value(_productNameAbsent),
        seizureDecision: Value(_seizureDecision?.stored ?? ''),
        restrictedParticularsPresent: Value(_labelling && _restrictedPresent),
        restrictedParticularIds: Value(_labelling ? _restricted.join(',') : ''),
        restrictedParticularsText:
            Value(_labelling ? TypedParticulars.pack(_typedRestricted) : ''),
        labelPackComplete: Value(_labelling && _labelPackComplete),
        isSampled: Value(_labelling && _isSampled),
        laboratoryId: Value(_laboratoryId),
        internalSampleNumber: Value(_internalSampleNumber.text.trim()),
        testSampleSize: Value(_testSampleSize.text.trim()),
        primarySampleSize: Value(_primarySampleSize.text.trim()),
        sampleCategoryId:
            Value(_sampleCategoryIds.isEmpty ? null : _sampleCategoryIds.first),
        sampleCategoryIds: Value(_sampleCategoryIds.join(',')),
        calciumTestRequired: Value(_calciumTestRequired),
        isCouriered: Value(_isCouriered),
        labInfoComplete: Value(_labInfoComplete),
        waybill: Value(_waybill),
        directionRemarkTypeId: Value(_remarkTypeId),
        directionRemarks: Value(_addedRemarks.join('\n')),
        correctByDate: Value(_correctBy),
        nonConformanceComments: Value(_nonConformanceComments.text.trim()),
        // From the visit where there is one, so the invoice and the office
        // record read the same kilometres however the visit was captured.
        distanceTravelledKm: Value(
          widget.visit?.distanceTravelledKm ??
              double.tryParse(_distanceTravelled.text.trim()),
        ),
        // Captured once, at the top of the form.
        managerName: Value(_contactPerson.text.trim()),
        managerEmail: Value(_contactEmail.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        clientEmail2: Value(_clientEmail2.text.trim()),
        noClientSignaturePresent: Value(declined),
        generalComments: Value(_generalComments.text.trim()),
        compositionChecklistJson:
            Value(CompositionChecklist.encode(_compositionSnapshot())),
        compositionComments: Value(_compositionComments.text.trim()),
        representativePosition: Value(_representativePosition.text.trim()),
      ),
    );
  }

  /// Steps back to the visit, keeping whatever has been captured so far.
  ///
  /// Nothing is validated on the way out — a half-filled record is exactly
  /// what a draft is for, and the visit offers it back as "continue".
  /// The chosen categories' names, one a line, or null while none is.
  String? _categoryNames(_Reference reference) {
    final names = [
      for (final c in reference.sampleCategories)
        if (_sampleCategoryIds.contains(c.id)) c.name,
    ];
    return names.isEmpty ? null : names.join('\n');
  }

  /// The original's category list, but ticked rather than picked: a sample
  /// can go for more than one category (Ethan, 2026-09-25). Cancel keeps
  /// what was ticked before.
  Future<void> _pickTestCategory(_Reference reference) async {
    final chosen = <int>{..._sampleCategoryIds};
    final picked = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Test Categories'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final category in reference.sampleCategories)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.brandPrimary,
                    value: chosen.contains(category.id),
                    onChanged: (on) => setDialogState(() {
                      if (on ?? false) {
                        chosen.add(category.id);
                      } else {
                        chosen.remove(category.id);
                      }
                    }),
                    title: Text(category.name,
                        style: const TextStyle(fontSize: 15, height: 1.35)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(chosen),
              child: const Text('DONE'),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _sampleCategoryIds
        ..clear()
        ..addAll(picked));
    }
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
  String? _sampleSizeIssue() {
    if (double.tryParse(_primarySampleSize.text.trim().replaceAll(',', '.')) ==
        null) {
      return 'Primary Sample Size (g) is required — a number of grams.';
    }
    if (_isSampled &&
        double.tryParse(_testSampleSize.text.trim().replaceAll(',', '.')) ==
            null) {
      return 'Lab Sample Size (g) is required — a number of grams.';
    }
    return null;
  }

  /// The remark chosen but not yet added, by name.
  String? _remarkName(_Reference reference) {
    for (final r in reference.remarks) {
      if (r.id == _remarkTypeId) return r.name;
    }
    return null;
  }

  /// The original's remark list: bullet-prefixed lines, Cancel to leave it.
  Future<void> _pickDirectionRemark(_Reference reference) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rejection Remark'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final remark in reference.remarks)
                InkWell(
                  onTap: () => Navigator.of(dialogContext).pop(remark.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('• ${remark.name}',
                        style: const TextStyle(fontSize: 15, height: 1.35)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _remarkTypeId = picked);
  }

  /// Adds the chosen remark to the direction. The same remark twice says
  /// nothing twice, so it is added once.
  void _addRemark(_Reference reference) {
    final name = _remarkName(reference);
    if (name == null || _addedRemarks.contains(name)) return;
    setState(() => _addedRemarks.add(name));
  }

  Future<void> _previous() async {
    setState(() => _saving = true);
    await _persist(completed: false);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(false);
  }

  Future<void> _save(_Reference reference, {required bool completed}) async {
    if (completed && !(_formKey.currentState?.validate() ?? false)) return;
    // Required on every commodity (Ethan, 2026-09-24) — on the labelling
    // inspection, where the batch is read off the pack.
    final batch = BatchNumber.missing(_batchNumber.text);
    final sizes = _sampleSizeIssue();
    final stop = completed && _labelling ? (batch ?? sizes) : null;
    if (stop != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(stop)));
      return;
    }
    // The front and back shots are the evidence the checklist is read
    // against, so a finished record cannot be without them. Refused here as
    // well as gated above: the checklist opens on the photographs, but an
    // inspection with nothing ticked would otherwise finish with none.
    if (completed && RawRmpRules.photographsOutstanding(_photoCount)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
            'Take the front and back product photographs before finishing '
            '— $_photoCount of $_requiredProductPhotos taken.',
          ),
        ));
      return;
    }
    setState(() => _saving = true);
    await _persist(completed: completed);
    if (!mounted) return;
    setState(() => _saving = false);

    final findings = _labelling
        ? RawRmpRules.findings(
            items: reference.checklist,
            present: _presentSections,
            compliantItemIds: _compliant,
          )
        : const <RawRmpChecklistItemRef>[];

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

  /// The original requires a front and a back product photograph.
  static const _requiredProductPhotos = RawRmpRules.requiredProductPhotos;

  bool get _photosAllowed => _storageTypeId != null;
  bool get _checklistUnlocked =>
      !RawRmpRules.photographsOutstanding(_photoCount);

  static bool _batchEntryValid(String text) => BatchNumber.valid(text);

  /// Leaving the box empty fills in N/A, as it does on the egg form.
  void _normaliseBatch() {
    if (_batchFocus.hasFocus) return;
    final tidied = BatchNumber.tidy(_batchNumber.text);
    if (tidied == _batchNumber.text) return;
    setState(() => _batchNumber.text = tidied);
  }

  Future<void> _refreshPhotoCount() async {
    final photos = await widget.captureRepository.photosFor(_clientUuid);
    if (!mounted) return;
    setState(() => _photoCount = photos.length);
  }

  void _toggle(int id) => setState(() {
        if (!_compliant.remove(id)) _compliant.add(id);
      });

  /// Unticking a row is the normal path; unticking the *product name* asks
  /// one further question, because the two answers have different legal
  /// consequences — a name shown but deficient is corrected by direction, a
  /// name not shown at all makes the consignment unidentifiable and it is
  /// seized.
  Future<void> _toggleChecklistItem(RawRmpChecklistItemRef item) async {
    final wasCompliant = _compliant.contains(item.id);
    if (wasCompliant && RawRmpRules.isProductNameRow(item)) {
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
    } else if (wasCompliant == false && RawRmpRules.isProductNameRow(item)) {
      // Ticked back as compliant: the earlier answer no longer applies.
      _productNameAbsent = false;
    }
    _toggle(item.id);
    unawaited(_applySop());
  }

  /// FSA-SOP-APS-001, Annexure A: the rectification period follows from
  /// the deviations ticked, and a deviation the annexure seizes on puts the
  /// seizure question — once, on the premises.
  Future<void> _applySop() async {
    final reference = await _reference;
    if (!mounted) return;
    final days = RawRmpRules.rectificationDays(
      items: reference.checklist,
      present: _labelling ? _presentSections : const {},
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
      compositionFailed: _compositionFailed,
    );
    setState(() {
      _correctBy =
          RawRmpRules.correctByDate(inspectedAt: _inspectedAt, days: days);
      _correctByDate.text = _correctBy == null ? '' : _dmy(_correctBy!);
    });
    await _askAboutSeizureIfNeeded();
  }

  /// Whether the compositional checklist, where this record holds one,
  /// carries a deviation.
  bool get _compositionFailed =>
      _kind.showsComposition &&
      RawRmpRules.compositionFails(_compositionSnapshot());

  /// What the correct-by field says under its date.
  String _periodHelper(_Reference reference) {
    final days = RawRmpRules.rectificationDays(
      items: reference.checklist,
      present: _labelling ? _presentSections : const {},
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
      compositionFailed: _compositionFailed,
    );
    if (days == null) {
      return 'Set by FSA-SOP-APS-001 Annexure A from the deviations ticked.';
    }
    return '${RawRmpRules.periodLabel(days)}, per FSA-SOP-APS-001 Annexure A, '
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
                'consignment (FSA-SOP-APS-001 Annexure A).'
            : 'Seizure declined on the premises; the rejection stands and is '
                'to be put right immediately.',
        style: TextStyle(color: colour, fontSize: 13, height: 1.4),
      ),
    );
  }

  /// Whether the question has been put on this visit to the form.
  bool _seizureAsked = false;
  SeizureDecision? _seizureDecision;

  /// Puts the seizure question, once, the moment the findings raise it.
  ///
  /// The page already showed a notice saying the consignment was to be
  /// seized, and then carried on into the rejection form as though it were
  /// an ordinary direction. FSA-SOP-APS-001 makes it a decision the
  /// inspector takes on the premises, so it is asked rather than announced.
  Future<void> _askAboutSeizureIfNeeded() async {
    if (_seizureAsked) return;
    final reference = await _reference;
    if (!mounted || !_seizureRequired(reference)) return;
    _seizureAsked = true;
    final answer =
        await askAboutSeizure(context, reason: _seizureReason(reference));
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
          recordKind: 'rawrmp',
          visitUuid: widget.visit?.uuid ?? '',
          inspectorUsername: widget.inspectorName,
          natureOfDeviation: _seizureReason(reference),
          regulation: 'R.2410 of 26 August 2022',
          clientName: _facilityName.text,
          clientAddress: _facilityAddress.text,
          clientTelephone: _facilityTelephone.text,
          clientEmail: _contactEmail.text,
          inspectionPoint: reference.locations
              .where((l) => l.id == _locationId)
              .map((l) => l.name)
              .firstWhere((_) => true, orElse: () => ''),
          productName: _newProductItem.text.trim().isNotEmpty
              ? _newProductItem.text
              : _productItem.text,
          productClass: reference.sampleCategories
              .where((c) => _sampleCategoryIds.contains(c.id))
              .map((c) => c.name)
              .join(', '),
          receiverName: _managerName.text,
        ),
      );
    }
  }

  /// Why this consignment is being seized, in the inspector's terms.
  String _seizureReason(_Reference reference) {
    final rows = RawRmpRules.seizureFindings(
      items: reference.checklist,
      present: _presentSections,
      compliantItemIds: _compliant,
      productNameAbsent: _productNameAbsent,
    );
    final reasons = <String>[
      if (rows.any(RawRmpRules.isBatchCodeRow))
        'the batch code is missing, so the consignment cannot be traced',
      if (rows.any(RawRmpRules.isProductNameRow))
        'the product name is not indicated at all',
      if (rows.any((r) => r.section == RawRmpSection.container))
        'the container does not comply with Regulation 6',
      if (_compositionFailed)
        'the product does not meet the compositional standard (Reg. 5)',
    ];
    return 'Seizure under FSA-SOP-APS-001 Annexure A: ${reasons.join('; ')}.';
  }

  /// Whether the findings force a seizure rather than an ordinary direction.
  bool _seizureRequired(_Reference reference) =>
      _compositionFailed ||
      (_labelling &&
          RawRmpRules.seizureRequired(
            items: reference.checklist,
            present: _presentSections,
            compliantItemIds: _compliant,
            productNameAbsent: _productNameAbsent,
          ));

  /// Whether the ticked checklist demands a direction — the original shows
  /// the Direction Form block only while a deviation stands.
  bool _directionPresent(_Reference reference) =>
      _compositionFailed ||
      (_labelling &&
          RawRmpRules.findings(
            items: reference.checklist,
            present: _presentSections,
            compliantItemIds: _compliant,
          ).isNotEmpty);

  /// Whether this record holds the labelling and sampling — every raw
  /// record but a compositional checklist on its own.
  bool get _labelling => _kind.showsInspection;

  /// Raises (or refreshes) the direction for this inspection, copying the
  /// client and product particulars onto the notice the way the original's
  /// SaveDirection does. Non-conformance ids are each deviated row's
  /// position within its own section — the original's bitmask arithmetic,
  /// cross-section aliasing quirks included. The original never captures a
  /// primary sample size for this commodity, so the notice carries none.
  Future<void> _spawnDirection(
    _Reference reference,
    List<RawRmpChecklistItemRef> findings,
  ) async {
    final existing =
        await widget.repository.directionForInspection(_clientUuid);
    final issuedAt = existing?.issuedAt ?? DateTime.now();
    // Numbered once, when it is first raised. A direction that is refreshed
    // — the inspector corrects a row and saves again — keeps the number the
    // client was served under, which is what the office quotes back.
    final referenceNumber =
        existing != null && existing.referenceNumber.isNotEmpty
            ? existing.referenceNumber
            : await widget.repository.nextDirectionReference(
                inspectorUsername: widget.inspectorName,
                clientName: _facilityName.text.trim(),
                at: issuedAt,
              );
    final bySection = <RawRmpSection, List<RawRmpChecklistItemRef>>{};
    for (final item in reference.checklist) {
      bySection.putIfAbsent(item.section, () => []).add(item);
    }
    final findingIds = {for (final f in findings) f.id};
    final positions = <int>[];
    for (final section in RawRmpSection.values) {
      final items = bySection[section] ?? const [];
      for (var i = 0; i < items.length; i++) {
        if (findingIds.contains(items[i].id)) positions.add(i + 1);
      }
    }
    await widget.repository.saveDirection(
      RawRmpDirectionsCompanion.insert(
        clientUuid: existing?.clientUuid ?? const Uuid().v4(),
        issuedAt: issuedAt,
        updatedAt: DateTime.now(),
        referenceNumber: Value(referenceNumber),
        // The deadline the client is served with, off the inspection that
        // raised it.
        correctByDate: Value(_correctBy),
        inspectorUsername: Value(widget.inspectorName),
        status: const Value('completed'),
        sourceInspectionUuid: Value(_clientUuid),
        facilityName: Value(_facilityName.text.trim()),
        clientName: Value(_contactPerson.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        remarkTypeId: Value(_remarkTypeId),
        remarks: Value(_addedRemarks.join('\n')),
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

  List<PoultryDesignationRef> _asRefs(List<RawRmpRef> items) =>
      [for (final i in items) PoultryDesignationRef(id: i.id, name: i.name)];

  @override
  Widget build(BuildContext context) {
    // The back arrow and the phone's own back gesture keep the work too:
    // an inspector who steps out mid-record finds it waiting as a draft.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        await _previous();
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        // The regulation's full name is long; scaled to fit rather than cut
        // off mid-phrase ("Certain Raw Processed Meat Product ...").
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _kind.title,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
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

  /// One gated section: the switch, and its rows only while it is on.
  /// One block of the Mark/Label Checklist.
  ///
  /// Same shape as the egg form's labelling checklists — an uppercase
  /// heading and plain tick rows, the regulation and lettering standard as
  /// the row's second line — carrying what the original's grid says: the
  /// block's own title, its regulation and Std (mm) columns, and that a
  /// tick means No Deviation.
  ///
  /// The rows stay on screen with the section switched off, greyed and not
  /// tickable, because that is what the original shows: an inspector can
  /// read what the block asks before deciding whether it applies.
  Widget _gatedChecklist({
    required String switchLabel,
    required String blockTitle,
    required bool present,
    required ValueChanged<bool> onChanged,
    required List<RawRmpChecklistItemRef> items,
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
                  // marks the ones the product fails, as the egg form
                  // works and as the paper checklist is filled in — a tick
                  // per conforming line would be sixty ticks for a product
                  // with nothing wrong with it (FSA, 2026-09-08).
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
            'Labelling requirement  ·  Regulation  ·  Std (mm)  —  tick for '
            'No Deviation',
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
                            if (_rowNote(item) != null) _rowNote(item)!,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ComplianceSlider(
                        compliant: _compliant.contains(item.id),
                        enabled: present,
                        onChanged: (_) => _toggleChecklistItem(item),
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

  /// The row's second line: the regulation, and the lettering standard
  /// written as the original's Std (mm) column writes it.
  Widget? _rowNote(RawRmpChecklistItemRef item) {
    final parts = [
      if (item.regulationReference.isNotEmpty) item.regulationReference,
      if (item.minLetteringHeight.trim().isNotEmpty)
        'Std (mm) ≥ ${item.minLetteringHeight}',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join('  ·  '),
      style: const TextStyle(fontSize: 11.5),
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
      // Kept in step with the picker rather than shown as a second box.
      _newFacilityName.text = values['name']!;
      _tradingName.text = values['tradingName'] ?? '';
      _facilityAddress.text = values['address'] ?? '';
      _facilityTelephone.text = values['telephone'] ?? '';
    });
  }

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
        // The record still carries the name as "new producer details", which
        // is what the office's reports read; the directory is a convenience
        // on top of that, not a replacement for it.
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
        title: 'New raw meat product',
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
    List<RawRmpChecklistItemRef> of(RawRmpSection section) => [
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
          // Inside a grouped inspection the door has already asked both, so
          // they are not asked again here (Ethan, 2026-09-24).
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
            // "New Facility Name" is gone: the picker above already holds
            // the name, and adding a facility filled both boxes with the
            // same text, which is what inspectors were reporting as
            // capturing the facility twice. The column still travels with
            // the record, set from the picker.
            poultryField(
              _tradingName,
              'Trading Name',
              helper: 'Only if the facility trades under a different name.',
            ),
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
          ],

          poultrySection('Producer and Product'),
          // Named once on the visit (Ethan, 2026-09-25); asked here only
          // when the visit did not name one.
          if (!_producerFromVisit)
            SearchPickerField<RawRmpRef>(
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
          SearchPickerField<RawRmpRef>(
            label: 'Certain Raw Processed Meat Product',
            controller: _productItem,
            options: reference.products,
            optionLabel: (p) => p.name,
            minQueryLength: 1,
            onSelected: (p) => setState(() => _productItem.text = p.name),
            emptyHint: 'No product directory on this device yet.',
            addNewLabel: 'Add new product',
            onAddNew: _addProduct,
          ),
          // A product not on the list is added through the picker's own
          // "Add new product" offer, which asks for the name, size and
          // barcode in one sheet and fills the new-item columns behind the
          // scenes — one input, as on the other commodities. The separate
          // "New Raw Meat Product Item" / "New PMP Item Size" / "New PMP Item
          // Barcode" boxes (the original's copy-pasted PMP wording) are gone.
          poultryField(
            _batchNumber,
            'Batch Number',
            required: true,
            focusNode: _batchFocus,
            helper: _batchEntryValid(_batchNumber.text)
                ? 'The number off the pack, or N/A if it has none.'
                : 'A number, or N/A — nothing else counts as a batch.',
            onChanged: (_) => setState(() {}),
          ),
          // The same calendar as every other date on the forms. Stored as
          // the dd/MM/yyyy text the record has always kept, so nothing
          // already captured changes shape.
          DateField(
            label: 'Manufactured/Packed Date',
            // Made or packed already — never a date still to come
            // (Ethan, 2026-09-24).
            lastDate: DateTime.now(),
            value: DateField.parseDmy(_manuPackedDate.text),
            onChanged: (d) => setState(
                () => _manuPackedDate.text = d == null ? '' : DateField.dmy(d)),
          ),
          poultryField(_primarySampleSize, 'Primary Sample Size (g)',
              required: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              helper: 'Sample size / quantity looked at, in grams.'),
          poultryDropdown(
            label: 'Storage Method',
            value: _storageTypeId,
            items: _asRefs(reference.storageTypes),
            onChanged: (v) => setState(() => _storageTypeId = v),
          ),

          // "Follow Up Rejection Particulars" is no longer asked
          // (Ethan, 2026-09-24); a draft that held one keeps it.

          // The original enables its "Take Product Photos" button from the
          // storage-method picker, and opens the checklist only once the
          // front and back shots exist.
          PoultryEvidenceSection(
            repository: widget.captureRepository,
            recordUuid: _clientUuid,
            kind: 'rawrmp',
            photosTitle: 'Product Photos',
            captureLabel: 'Take Product Photos',
            guidance: 'Two views of the product: the front of the pack with '
                'the product name legible, and the back with the '
                'ingredients, the manufacturer and the batch code. A third '
                'is optional.',
            showSignatures: false,
            // The original stops before each of the first two shots and
            // says which view it wants; a third is allowed and optional.
            maxPhotos: 3,
            minPhotos: _requiredProductPhotos,
            captureNotes: const [
              (
                title: 'Front Photo Note',
                message: 'Please take a FRONT view photo of the product.'
                    '\nOnly 1 photo is required.',
              ),
              (
                title: 'Rear Photo Note',
                message: 'Please take a REAR view photo of the product.'
                    '\nOnly 1 photo is required.',
              ),
            ],
            enabled: _photosAllowed,
            disabledHint: 'Choose the Storage Method above before taking the '
                'product photographs.',
            onChanged: () {
              unawaited(_persist(completed: false));
              unawaited(_refreshPhotoCount());
            },
          ),

          if (_labelling) ...[
            poultrySection('Mark/Label Checklist'),
            if (!_checklistUnlocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _photosAllowed
                      ? 'Take the front and back product photographs above to '
                          'open the checklist — $_photoCount of '
                          '$_requiredProductPhotos taken.'
                      : 'Choose the Storage Method, then take the front and back '
                          'product photographs, to open the checklist.',
                  style: TextStyle(color: AppColors.muted, height: 1.35),
                ),
              ),
            IgnorePointer(
              ignoring: !_checklistUnlocked,
              child: Opacity(
                opacity: _checklistUnlocked ? 1 : 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _gatedChecklist(
                      switchLabel: 'Marking Label Present',
                      blockTitle: 'Label Marking',
                      present: _markingPresent,
                      onChanged: (v) => _markingPresent = v,
                      items: of(RawRmpSection.marking),
                    ),
                    _gatedChecklist(
                      switchLabel: 'Scale Label Present',
                      blockTitle: 'Scale Label',
                      present: _scalePresent,
                      onChanged: (v) => _scalePresent = v,
                      items: of(RawRmpSection.scale),
                    ),
                    _gatedChecklist(
                      switchLabel: 'Container/Outer Container Present',
                      blockTitle: 'Container and Outer-Container',
                      present: _containersPresent,
                      onChanged: (v) => _containersPresent = v,
                      items: of(RawRmpSection.container),
                    ),
                    _gatedChecklist(
                      switchLabel: 'Display Fridge Present',
                      blockTitle: 'Display Fridge',
                      present: _fridgePresent,
                      onChanged: (v) => _fridgePresent = v,
                      items: of(RawRmpSection.fridge),
                    ),
                    _gatedChecklist(
                      switchLabel: 'Notice Boards, Signage, etc. Present',
                      blockTitle: 'Notice Boards, Signage, etc.',
                      present: _noticePresent,
                      onChanged: (v) => _noticePresent = v,
                      items: of(RawRmpSection.notice),
                    ),
                  ],
                ),
              ),
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
          ],

          if (_kind.showsComposition) ..._compositionFields(),

          if (_labelling) ...[
            poultrySection('Sample Details'),
            poultryChoice(
              label: 'Sampling',
              options: const ['Is Sampled', 'Not Sampled'],
              selectedIndex: _isSampled ? 0 : 1,
              onChanged: (i) {
                setState(() => _isSampled = i == 0);
                if (_isSampled) unawaited(_numberTheSample());
              },
            ),
            if (_isSampled) ...[
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
              poultryField(_testSampleSize, 'Lab Sample Size (g)',
                  required: true,
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true)),
              // The original opens a "Select Test Category" list rather than
              // a dropdown, each line bullet-prefixed, with Cancel to leave it
              // unset. Same list, same way out.
              LabelledField(
                label: 'Laboratory Testing Category',
                child: InkWell(
                  onTap: () => _pickTestCategory(reference),
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      _categoryNames(reference) ?? 'Select Test Categories',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: _sampleCategoryIds.isEmpty
                            ? AppColors.muted
                            : AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              poultrySwitch(
                // The original's caption, typo and all.
                label: 'Request Calcuim Content Test (for MRM only)',
                value: _calciumTestRequired,
                onChanged: (v) => setState(() => _calciumTestRequired = v),
              ),
              // The original names both states under one caption rather than
              // asking a single "Hand Delivered" question: the sample either
              // goes by hand or by courier, and the Pending Courier screen
              // filters on the answer.
              poultryChoice(
                label: 'Delivery Method - Toggle the option below',
                options: const ['Hand Delivered', 'Couriered'],
                selectedIndex: _isCouriered ? 1 : 0,
                onChanged: (i) => setState(() => _isCouriered = i == 1),
              ),
              poultrySwitch(
                label: 'Lab info is complete',
                value: _labInfoComplete,
                onChanged: (v) => setState(() => _labInfoComplete = v),
              ),
            ],
          ],

          if (widget.visit == null)
            PoultryEvidenceSection(
              repository: widget.captureRepository,
              recordUuid: _clientUuid,
              kind: 'rawrmp',
              // The photographs sit up with the product details, where the
              // original takes them.
              showPhotos: false,
              onChanged: () => unawaited(_persist(completed: false)),
            )
          else
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

          if (_directionPresent(reference)) ...[
            poultrySection('Rejection Form'),
            if (_seizureRequired(reference))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.noticeBackground,
                    border: Border.all(color: AppColors.noticeBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.gavel,
                          size: 18, color: AppColors.noticeForeground),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _seizureReason(reference),
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.noticeForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Remarks are chosen from the Agency's own list and added, not
            // typed: the original opens a "Direction Remark" dialog, adds
            // the chosen line to the direction, and offers Clear Remarks to
            // start the list again.
            LabelledField(
              label: 'Label/Pack Rejection Remarks',
              child: InkWell(
                onTap: () => _pickDirectionRemark(reference),
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(
                    _remarkName(reference) ?? 'Select a rejection remark',
                    style: TextStyle(
                      fontSize: 14,
                      color: _remarkTypeId == null
                          ? AppColors.muted
                          : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            LabelledField(
              label: 'List of Added Remarks',
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _addedRemarks.isEmpty
                    ? Text(
                        'None added yet.',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final remark in _addedRemarks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $remark',
                                  style: const TextStyle(
                                      fontSize: 13.5, height: 1.35)),
                            ),
                        ],
                      ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _remarkTypeId == null
                        ? null
                        : () => _addRemark(reference),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('ADD REMARK', maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _addedRemarks.isEmpty
                        ? null
                        : () => setState(_addedRemarks.clear),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('CLEAR REMARKS', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // The period is the annexure's, never a free date
            // (FSA-SOP-APS-001 §8.1).
            poultryField(_correctByDate, 'Correct by/on Date',
                readOnly: true, helper: _periodHelper(reference)),
            if (_seizureDecision != null) _seizureNotice(),
            poultryField(
              _nonConformanceComments,
              'Non-Conformance Comments',
              lines: 3,
            ),
          ],

          // The original calls this block "Signatures Control", but the
          // signatures are taken once at the end of the visit now and the
          // recipients are captured with the facility — so what is left of
          // it is the distance, and it is named for what it holds.
          //
          // One journey to one facility: inside a visit it is asked at the
          // door, not again here. Two raw inspections in a visit used to ask
          // for it twice, and the invoice kept whichever it read first.
          if (widget.visit == null) ...[
            poultrySection('Travel'),
            poultryField(
              _distanceTravelled,
              'Distance Travelled (km)',
              keyboard: TextInputType.number,
              helper: 'What the invoice is billed on, at R6.50 per kilometre.',
            ),
          ],

          const SizedBox(height: 20),
          // Previous and Next, not a save button: the record is written on
          // the way out either way, so leaving half-done and coming back
          // resumes where the inspector stopped. There is nothing to
          // remember to press.
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _previous,
                    child: const Text('PREVIOUS'),
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
                    child: Text(_saving ? 'Saving…' : 'NEXT'),
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
