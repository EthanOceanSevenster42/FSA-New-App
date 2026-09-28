import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/services/in_app_camera.dart';
import '../../sync/auto_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/required_label.dart';
import '../../../core/widgets/search_picker.dart';
import '../domain/facility_type_match.dart';
import '../domain/inspection_reason_match.dart';
import '../../eggs/data/eggs_repository.dart';
import '../../eggs/data/eggs_sync_service.dart';
import '../../eggs/presentation/egg_inspection_form.dart';
import '../../eggs/presentation/new_directory_entry_sheet.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../../poultry/data/poultry_repository.dart';
import '../../poultry/presentation/poultry_inspection_form.dart';
import '../../poultry/presentation/poultry_quid_continue_page.dart';
import '../../poultry/presentation/poultry_quid_setup_form.dart';
import '../../poultry/presentation/poultry_label_checklist_form.dart';
import '../../poultry/presentation/signature_pad.dart';
import '../../rawrmp/data/rawrmp_repository.dart';
import '../../rawrmp/presentation/rawrmp_inspection_form.dart';
import '../../rawrmp/domain/raw_record_kind.dart';
import '../../pmp/data/pmp_repository.dart';
import '../../pmp/presentation/pmp_inspection_form.dart';
import '../data/visit_repository.dart';
import '../../../core/widgets/picker_menu_field.dart';

/// What a signed-off visit page hands back, so the list page above it
/// closes too and the inspector lands on the home screen.
const _signedOffResult = 'signed-off';

/// The four commodities a visit is planned in, in the order the flow walks
/// them.
///
/// The Label/Container Checklist is not one of them: in the original it is a
/// second kind of poultry inspection, sitting on the Poultry menu beside
/// "New Grading and Classification Checklist" — so it belongs inside a
/// poultry inspection, not as a fifth thing to count at the door.
/// Named for the commodity and what is being done — an inspection — rather
/// than for the checklist inside it. "Poultry Grading" told an inspector
/// which form they were opening, not which job they were doing.
/// The commodities a visit can hold. [label] heads the plan row, which
/// counts them ("2 of 2 done"); [single] names the one about to be opened,
/// because "START ... INSPECTIONS" reads wrong for a single inspection.
/// [short] is the everyday word for it — what the order line uses, because
/// "Certain Raw Processed Meat Product Inspection, then Egg Inspection" is
/// not a sentence anyone reads standing in a doorway.
const _kinds = <({String kind, String label, String single, String short})>[
  (
    kind: 'egg',
    label: 'Egg Inspections',
    single: 'Egg Inspection',
    short: 'Eggs',
  ),
  (
    kind: 'poultry',
    label: 'Poultry Inspections',
    single: 'Poultry Inspection',
    short: 'Poultry',
  ),
  (
    kind: 'rawrmp',
    label: 'Certain Raw Processed Meat Product Inspections',
    single: 'Certain Raw Processed Meat Product Inspection',
    short: 'Raw',
  ),
  (
    kind: 'pmp',
    label: 'Processed Meat Product Inspections',
    single: 'Processed Meat Product Inspection',
    short: 'Processed Meat',
  ),
];

/// Open grouped inspections, and the way into a new one.
class StoreVisitListPage extends StatefulWidget {
  const StoreVisitListPage({
    super.key,
    required this.visits,
    required this.eggs,
    required this.eggsSync,
    required this.poultry,
    required this.poultryCapture,
    required this.rawRmp,
    required this.pmp,
    required this.inspectorName,
    required this.canRemoveRecords,
  });

  final VisitRepository visits;
  final EggsRepository eggs;
  final EggsSyncService? eggsSync;
  final PoultryRepository poultry;
  final PoultryCaptureRepository poultryCapture;
  final RawRmpRepository rawRmp;
  final PmpRepository pmp;
  final String inspectorName;

  /// Whether this user may take work off the device. An inspector may not.
  final bool canRemoveRecords;

  @override
  State<StoreVisitListPage> createState() => _StoreVisitListPageState();
}

class _StoreVisitListPageState extends State<StoreVisitListPage> {
  List<StoreVisit> _open = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final open = await widget.visits.openVisits();
    if (mounted) {
      setState(() {
        _open = open;
        _loading = false;
      });
    }
  }

  Future<void> _openVisit(String uuid) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => StoreVisitPage(
          visitUuid: uuid,
          visits: widget.visits,
          eggs: widget.eggs,
          eggsSync: widget.eggsSync,
          poultry: widget.poultry,
          poultryCapture: widget.poultryCapture,
          rawRmp: widget.rawRmp,
          pmp: widget.pmp,
          inspectorName: widget.inspectorName,
          canRemoveRecords: widget.canRemoveRecords,
        ),
      ),
    );
    if (!mounted) return;
    // Signed off — the facility is finished, so this list closes too and
    // the inspector lands back on the home screen.
    if (result == _signedOffResult) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(_refresh());
  }

  /// Discarding removes the group and its shared details. Inspections
  /// already captured under it are their own records and stay saved.
  Future<void> _discard(StoreVisit visit) async {
    final members = await widget.visits.members(visit.uuid);
    if (!mounted) return;
    // An inspector may put away their own unsigned visit, inspections and
    // all. This screen lists only visits that have not been signed off, so
    // nothing here has reached the office — it is the inspector's own work
    // until the final sign-off sends it. Removing work the office already
    // holds stays the office's call, and Inspection Management, where the
    // signed-off visits live, offers no delete at all.
    if (visit.completedAt != null && !widget.canRemoveRecords) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            const SnackBar(content: Text(SessionUser.removalRefused)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this inspection?'),
        content: Text(
          members.isEmpty
              ? 'The facility details and plan for '
                  '"${visit.facilityName.isEmpty ? 'this inspection' : visit.facilityName}" '
                  'will be removed.'
              : 'This discards the visit and the '
                  '${members.length} inspection${members.length == 1 ? '' : 's'} '
                  'captured under it — every reading, deviation, photograph '
                  'and signature. None of it has been signed off or sent to '
                  'the office, so it cannot be brought back from here.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: members.isEmpty
                    ? AppColors.brandPrimary
                    : AppColors.brandRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // The inspections go with the visit: left behind they were orphans,
    // counted by nothing and reachable from nowhere.
    await widget.visits.discardWithMembers(visit.uuid);
    unawaited(_refresh());
  }

  Future<void> _start() async {
    final uuid = const Uuid().v4();
    await widget.visits.create(uuid, widget.inspectorName);
    if (!mounted) return;
    await _openVisit(uuid);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0,
          shape: Border(bottom: BorderSide(color: AppColors.border)),
          title: const Text(
            'Inspection',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
        ),
        body: ContentWidth(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      18,
                      16,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Text(
                        'Capture the store once, plan how many inspections of '
                        'each commodity it needs, work through them, and sign '
                        'once at the end — the signatures apply to all of them.',
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('NEW INSPECTION'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_open.isNotEmpty) ...[
                        Text(
                          'IN PROGRESS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final visit in _open)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const Icon(Icons.storefront_outlined,
                                  color: AppColors.brandTeal),
                              title: Text(
                                visit.facilityName.isEmpty
                                    ? 'Unnamed facility'
                                    : visit.facilityName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'Started '
                                '${visit.startedAt.day.toString().padLeft(2, '0')}/'
                                '${visit.startedAt.month.toString().padLeft(2, '0')} '
                                'at ${visit.startedAt.hour.toString().padLeft(2, '0')}:'
                                '${visit.startedAt.minute.toString().padLeft(2, '0')}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Discard',
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.brandPrimary),
                                onPressed: () => _discard(visit),
                              ),
                              onTap: () => _openVisit(visit.uuid),
                            ),
                          ),
                      ],
                    ],
                  )),
      );
}

/// One grouped inspection: the store captured once, the plan, the walk
/// through it, and the closing signatures.
class StoreVisitPage extends StatefulWidget {
  const StoreVisitPage({
    super.key,
    required this.visitUuid,
    required this.visits,
    required this.eggs,
    required this.eggsSync,
    required this.poultry,
    required this.poultryCapture,
    required this.rawRmp,
    required this.pmp,
    required this.inspectorName,
    required this.canRemoveRecords,
    this.detailsOnly = false,
  });

  final String visitUuid;
  final VisitRepository visits;
  final EggsRepository eggs;
  final EggsSyncService? eggsSync;
  final PoultryRepository poultry;
  final PoultryCaptureRepository poultryCapture;
  final RawRmpRepository rawRmp;
  final PmpRepository pmp;
  final String inspectorName;

  /// Whether this user may take work off the device. An inspector may not.
  final bool canRemoveRecords;

  /// Opened from Inspection Management to correct a visit that is already
  /// signed off, rather than to capture one.
  ///
  /// What kind of visit it is was settled at the door and the office has
  /// filed it that way, so the question is not asked again: an answer
  /// changed here would turn a filed inspection into an occurrence report,
  /// or the other way about.
  final bool detailsOnly;

  @override
  State<StoreVisitPage> createState() => _StoreVisitPageState();
}

class _StoreVisitPageState extends State<StoreVisitPage> {
  final _facilityName = TextEditingController();

  /// Where the cursor goes when the inspector says the details have changed.
  final _facilityAddressFocus = FocusNode();
  final _facilityAddress = TextEditingController();
  final _facilityPhone = TextEditingController();
  final _producer = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _additionalEmail1 = TextEditingController();
  final _additionalEmail2 = TextEditingController();
  final _additionalEmail3 = TextEditingController();

  /// One journey to one facility, billed once. It used to be asked on every
  /// raw inspection, so a visit with two of them asked twice and the invoice
  /// kept whichever it read first.
  final _distanceTravelled = TextEditingController();

  List<EggFacility> _directory = const [];
  List<VisitMember> _members = const [];
  final _planned = <String, int>{
    for (final k in _kinds) k.kind: 0,
  };

  /// The commodities in the order they were planned, first raised first.
  ///
  /// The flow walks this rather than [_kinds], so a plan set raw-then-egg
  /// opens the raw inspection first and the egg one after it.
  final _planOrder = <String>[];
  bool _loading = true;
  bool _completing = false;
  bool _completed = false;
  bool _isOccurrence = false;
  String _facilityType = '';
  String _occurrenceTime = '';
  final _occurrenceRegistration = TextEditingController();
  final _occurrenceDescription = TextEditingController();
  List<VisitOccurrencePhoto> _occurrencePhotos = const [];

  /// The Occurrence Document carries two photographs at most.
  static const _maxOccurrencePhotos = 2;
  bool _capturingOccurrence = false;
  List<String> _facilityTypeOptions = const [];
  String _inspectionReason = '';
  List<String> _inspectionReasonOptions = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _occurrenceRegistration.dispose();
    _occurrenceDescription.dispose();
    _facilityName.dispose();
    _facilityAddress.dispose();
    _facilityAddressFocus.dispose();
    _facilityPhone.dispose();
    _producer.dispose();
    _contactPerson.dispose();
    _contactEmail.dispose();
    _additionalEmail1.dispose();
    _additionalEmail2.dispose();
    _additionalEmail3.dispose();
    _distanceTravelled.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final visit = await widget.visits.byUuid(widget.visitUuid);
    final members = await widget.visits.members(widget.visitUuid);
    // The same premises directory the egg form searches: picking the store
    // from it fills the fields, rather than typing them again.
    final directory = await widget.eggs.facilities();
    final occurrencePhotos =
        await widget.visits.occurrencePhotos(widget.visitUuid);
    // One list for the door: every commodity's facility types, each kind
    // once. The forms map the answer back onto their own rows.
    final typeOptions = FacilityTypeMatch.union([
      (await widget.eggs.facilityTypes()).map((t) => t.name),
      (await widget.poultry.inspectionLocations()).map((t) => t.name),
      (await widget.rawRmp.locations()).map((t) => t.name),
      (await widget.pmp.locations()).map((t) => t.name),
    ]);
    // Why the inspector is here: Inspection or Follow Up, and nothing else.
    // Each commodity matches its own row for the answer.
    const reasonOptions = InspectionReasonMatch.offered;
    if (!mounted || visit == null) return;
    setState(() {
      _facilityName.text = visit.facilityName;
      _facilityAddress.text = visit.facilityAddress;
      _facilityPhone.text = visit.facilityPhone;
      _producer.text = visit.producerName;
      _contactPerson.text = visit.contactPerson;
      _contactEmail.text = visit.contactEmail;
      _additionalEmail1.text = visit.additionalEmail1;
      _additionalEmail2.text = visit.additionalEmail2;
      _additionalEmail3.text = visit.additionalEmail3;
      _distanceTravelled.text = visit.distanceTravelledKm == null
          ? ''
          : '${visit.distanceTravelledKm}';
      _planned['egg'] = visit.plannedEggs;
      _planned['poultry'] = visit.plannedPoultry;
      _planned['rawrmp'] = visit.plannedRaw;
      _planned['pmp'] = visit.plannedPmp;
      // A visit saved before the order was recorded, or one whose counters
      // were changed elsewhere, still has to be walkable: keep what was
      // saved and put anything it does not name after it, in the plan's
      // own listed order.
      _planOrder
        ..clear()
        ..addAll(visit.planOrder
            .split(',')
            .map((s) => s.trim())
            .where((s) => _kinds.any((k) => k.kind == s)));
      for (final k in _kinds) {
        if (_planOrder.contains(k.kind)) continue;
        if ((_planned[k.kind] ?? 0) > 0 || _membersOf(k.kind).isNotEmpty) {
          _planOrder.add(k.kind);
        }
      }
      _isOccurrence = visit.isOccurrenceReport;
      _facilityType = visit.facilityType;
      _inspectionReason = visit.inspectionReason;
      _occurrenceTime = visit.occurrenceTimeOfVisit;
      _occurrenceRegistration.text = visit.occurrenceRegistrationCode;
      _occurrenceDescription.text = visit.occurrenceDescription;
      _occurrencePhotos = occurrencePhotos;
      _facilityTypeOptions = typeOptions;
      _inspectionReasonOptions = reasonOptions;
      _members = members;
      _directory = directory;
      _completed = visit.completedAt != null;
      _loading = false;
    });
  }

  /// The fields are the record; every keystroke lands in the row so nothing
  /// depends on a save button being remembered.
  /// Registers a premises the directory does not have, and picks it.
  ///
  /// The same entry the egg form makes — it goes to the server when there is
  /// signal and is kept locally either way, so the visit can carry on
  /// without one.
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
        const DirectoryField(label: 'Physical address', key: 'address'),
        const DirectoryField(
            label: 'Telephone / cellphone',
            key: 'telephone',
            keyboardType: TextInputType.phone),
      ],
    );
    if (values == null || !mounted) return;

    try {
      final facility = await widget.eggs.addFacility(
        name: values['name'] ?? typedName,
        physicalAddress: values['address'] ?? '',
        telephone: values['telephone'] ?? '',
      );
      if (!mounted) return;
      setState(() {
        _directory = [..._directory, facility];
        _facilityName.text = facility.name;
        if (facility.physicalAddress.trim().isNotEmpty) {
          _facilityAddress.text = facility.physicalAddress;
        }
        if (facility.telephone.trim().isNotEmpty) {
          _facilityPhone.text = facility.telephone;
        }
      });
      await _persist();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Premises added.')));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text('Could not add the premises. $e')));
    }
  }

  /// The occurrence report itself, as APS's own form takes it: when the
  /// inspector was there, the premises' registration code, a description of
  /// events, and photographs — bound into the Occurrence Document on upload.
  /// A stored 24-hour `HH:mm` shown the way it is said: `9:03 AM`.
  static String _timeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) return hhmm;
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $period';
  }

  Widget _occurrenceSection() {
    final palette = AppColors.of(context);
    return IgnorePointer(
      ignoring: _completed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              'OCCURRENCE REPORT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: palette.muted,
              ),
            ),
          ),
          LabelledField(
            label: 'Time of visit',
            isRequired: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final parts = _occurrenceTime.split(':');
                final initial = parts.length == 2
                    ? TimeOfDay(
                        hour: int.tryParse(parts[0]) ?? TimeOfDay.now().hour,
                        minute: int.tryParse(parts[1]) ?? 0)
                    : TimeOfDay.now();
                // Typed as hours and minutes with an AM/PM choice, no clock
                // dial: the way people say the time of day, and it looks
                // like the rest of the form. Stored as 24-hour HH:mm.
                final picked = await showTimePicker(
                  context: context,
                  initialTime: initial,
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  helpText: 'WHAT TIME OF DAY WAS THE VISIT?',
                  hourLabelText: 'Hour',
                  minuteLabelText: 'Minute',
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: false),
                    child: child!,
                  ),
                );
                if (picked == null || !mounted) return;
                setState(() => _occurrenceTime =
                    '${picked.hour.toString().padLeft(2, '0')}:'
                        '${picked.minute.toString().padLeft(2, '0')}');
                unawaited(_persist());
              },
              child: InputDecorator(
                isEmpty: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.schedule, size: 20),
                ),
                child: Text(
                  _occurrenceTime.isEmpty
                      ? 'Tap to choose the time of day'
                      : _timeOfDay(_occurrenceTime),
                  style: TextStyle(
                    fontSize: 15.5,
                    color:
                        _occurrenceTime.isEmpty ? palette.muted : palette.ink,
                  ),
                ),
              ),
            ),
          ),
          _field('Registration code (optional — if the premises has one)',
              _occurrenceRegistration),
          LabelledField(
            label: 'Description of events',
            isRequired: true,
            child: TextField(
              controller: _occurrenceDescription,
              maxLines: 7,
              minLines: 4,
              style: const TextStyle(fontSize: 15.5, height: 1.35),
              decoration: const InputDecoration(
                hintText: 'Describe in detail what was found during the '
                    'visit, including any non-conformances, observations, '
                    'and corrective actions discussed...',
              ),
              onChanged: (_) => unawaited(_persist()),
            ),
          ),
          // Photographs, laid out the way every inspection's evidence section
          // lays them out: the count, the thumbnails, and the same "Take
          // photograph" button — capped at two, what the one-page Occurrence
          // Document carries.
          // At least one, so the report shows what was found
          // (Ethan, 2026-09-24).
          LabelledField(
            label: 'Photographs',
            isRequired: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _occurrencePhotos.length >= _maxOccurrencePhotos
                        ? 'All $_maxOccurrencePhotos taken. Delete one to '
                            'take another.'
                        : '${_occurrencePhotos.length} of '
                            '$_maxOccurrencePhotos taken — at least 1, '
                            '$_maxOccurrencePhotos at most.',
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
                if (_occurrencePhotos.isNotEmpty)
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _occurrencePhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) =>
                          _occurrencePhotoTile(_occurrencePhotos[i]),
                    ),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: (_capturingOccurrence ||
                              _completed ||
                              _occurrencePhotos.length >= _maxOccurrencePhotos)
                          ? null
                          : _captureOccurrencePhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(
                          _capturingOccurrence ? 'Saving…' : 'Take photograph'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Bound into the Occurrence Document with this report and sent '
              'to APS.',
              style:
                  TextStyle(fontSize: 12.5, color: palette.muted, height: 1.35),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _occurrencePhotoTile(VisitOccurrencePhoto photo) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(photo.filePath),
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            // A file that has been cleared by Android is a missing photo,
            // not a crash.
            errorBuilder: (_, __, ___) => Container(
              width: 96,
              height: 96,
              color: AppColors.surfaceAlt,
              child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: InkWell(
            onTap: _completed
                ? null
                : () async {
                    await widget.visits.removeOccurrencePhoto(photo.id);
                    final rows =
                        await widget.visits.occurrencePhotos(widget.visitUuid);
                    if (mounted) setState(() => _occurrencePhotos = rows);
                  },
            child: Container(
              padding: const EdgeInsets.all(3),
              // Red: this throws the photograph away.
              decoration: BoxDecoration(
                color: AppColors.brandRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close, size: 15, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _captureOccurrencePhoto() async {
    // The cap holds even if the tile were tapped twice in flight.
    if (_occurrencePhotos.length >= _maxOccurrencePhotos) return;
    // Let go of the description first, or the keyboard springs back up the
    // moment the camera closes.
    FocusManager.instance.primaryFocus?.unfocus();
    final String? shot;
    try {
      shot = await capturePhoto(context, title: 'Occurrence photo');
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text('The camera could not be opened. $e')));
      }
      return;
    }
    if (shot == null || !mounted) return;
    setState(() => _capturingOccurrence = true);
    try {
      final storage = await PhotoStorage.instance();
      final path = await storage.adopt(
        File(shot),
        name: 'visit_${widget.visitUuid}_occurrence_'
            '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await widget.visits.addOccurrencePhoto(widget.visitUuid, path);
      final rows = await widget.visits.occurrencePhotos(widget.visitUuid);
      if (mounted) setState(() => _occurrencePhotos = rows);
    } finally {
      if (mounted) setState(() => _capturingOccurrence = false);
    }
  }

  /// Takes the premises the inspector picked, asking first whether the
  /// details the office holds are still right.
  ///
  /// The directory is only as good as the last visit: a store moves, changes
  /// its telephone, gets a new manager, and the documents then go to an
  /// address nobody reads. The inspector is standing there and can see, so
  /// they are asked once — and asked plainly, because "no change" must be
  /// as quick to answer as it is common.
  Future<void> _facilityChosen(EggFacility facility) async {
    final address = facility.physicalAddress.trim();
    final phone = facility.telephone.trim();

    setState(() {
      _facilityName.text = facility.name;
      if (address.isNotEmpty) _facilityAddress.text = address;
      if (phone.isNotEmpty) _facilityPhone.text = phone;
    });
    await _persist();
    if (!mounted || (address.isEmpty && phone.isEmpty)) return;

    final update = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Client details check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These are the details the office holds for '
              '${facility.name}. Are they still right?',
              style: const TextStyle(fontSize: 14.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (address.isNotEmpty)
              Text(address, style: const TextStyle(fontSize: 14)),
            if (phone.isNotEmpty)
              Text(phone, style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('NO CHANGE'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
    if (update != true || !mounted) return;

    // Correcting them means correcting them here: the fields are already on
    // screen, and what is typed travels to the office with the visit.
    FocusScope.of(context).requestFocus(_facilityAddressFocus);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text(
            'Correct the address, telephone / cellphone and contact below. '
            'They go to the office with this visit.'),
        duration: Duration(seconds: 6),
      ));
  }

  Future<void> _persist() => widget.visits.updateDetails(
        widget.visitUuid,
        StoreVisitsCompanion(
          facilityName: Value(_facilityName.text.trim()),
          facilityAddress: Value(_facilityAddress.text.trim()),
          facilityPhone: Value(_facilityPhone.text.trim()),
          producerName: Value(_producer.text.trim()),
          contactPerson: Value(_contactPerson.text.trim()),
          contactEmail: Value(_contactEmail.text.trim()),
          // The person in charge is the representative and the authorised
          // manager on the record, and their address is the manager
          // address: one answer, written to every column that wants it.
          representative: Value(_contactPerson.text.trim()),
          managerName: Value(_contactPerson.text.trim()),
          managerEmail: Value(_contactEmail.text.trim()),
          additionalEmail1: Value(_additionalEmail1.text.trim()),
          additionalEmail2: Value(_additionalEmail2.text.trim()),
          additionalEmail3: Value(_additionalEmail3.text.trim()),
          distanceTravelledKm:
              Value(double.tryParse(_distanceTravelled.text.trim())),
          plannedEggs: Value(_planned['egg'] ?? 0),
          plannedPoultry: Value(_planned['poultry'] ?? 0),
          plannedLabels: const Value(0),
          plannedRaw: Value(_planned['rawrmp'] ?? 0),
          plannedPmp: Value(_planned['pmp'] ?? 0),
          planOrder: Value(_planOrder.join(',')),
          isOccurrenceReport: Value(_isOccurrence),
          facilityType: Value(_facilityType),
          inspectionReason: Value(_inspectionReason),
          occurrenceTimeOfVisit: Value(_occurrenceTime),
          occurrenceRegistrationCode:
              Value(_occurrenceRegistration.text.trim()),
          occurrenceDescription: Value(_occurrenceDescription.text.trim()),
        ),
      );

  /// The records a plan row covers.
  ///
  /// Poultry covers both of its records: the grading and classification
  /// inspection and the labelling and container checklist. Which one a
  /// given slot becomes is answered on the way in, so the plan counts them
  /// together rather than asking for each separately at the door.
  static const _poultryKinds = {'poultry', 'poultry_label', 'quid'};

  /// The commodities that name a producer / supplier. Poultry and QUID do
  /// not, so a visit of those alone is not asked for one.
  static const _producerKinds = {'egg', 'rawrmp', 'pmp'};

  bool get _producerApplies => _producerKinds
      .any((kind) => (_planned[kind] ?? 0) > 0 || _membersOf(kind).isNotEmpty);

  List<VisitMember> _membersOf(String kind) => _members
      .where((m) =>
          kind == 'poultry' ? _poultryKinds.contains(m.kind) : m.kind == kind)
      .toList();

  int _captured(String kind) => _membersOf(kind).length;

  int _completedOf(String kind) =>
      _membersOf(kind).where((m) => m.completed).length;

  /// The next step, walking the commodities in order — all of one commodity
  /// before the next. An unfinished inspection is the next step of its
  /// commodity: it gets finished before a new one opens, so a draft can
  /// never be silently left behind by "start the next".
  ({
    String kind,
    String label,
    String single,
    int number,
    int of,
    VisitMember? resume
  })? get _nextSlot {
    for (final k in _plannedKinds) {
      // With the plan put away for an occurrence report, only an inspection
      // already begun still counts as a next step.
      final planned = _isOccurrence ? 0 : (_planned[k.kind] ?? 0);
      final members = _membersOf(k.kind);
      final unfinished = members.where((m) => !m.completed).toList();
      if (unfinished.isNotEmpty) {
        return (
          kind: k.kind,
          label: k.label,
          single: k.single,
          number: _completedOf(k.kind) + 1,
          of: planned > members.length ? planned : members.length,
          resume: unfinished.first,
        );
      }
      if (members.length < planned) {
        return (
          kind: k.kind,
          label: k.label,
          single: k.single,
          number: members.length + 1,
          of: planned,
          resume: null,
        );
      }
    }
    return null;
  }

  /// The commodities to walk, in the order they were planned.
  ///
  /// Anything the order does not name trails behind in the plan's listed
  /// order, so a commodity can never be dropped from the walk.
  List<({String kind, String label, String single, String short})>
      get _plannedKinds {
    final ordered =
        <({String kind, String label, String single, String short})>[];
    for (final kind in _planOrder) {
      final match = _kinds.where((k) => k.kind == kind);
      if (match.isNotEmpty) ordered.add(match.first);
    }
    for (final k in _kinds) {
      if (!ordered.any((o) => o.kind == k.kind)) ordered.add(k);
    }
    return ordered;
  }

  /// Remembers that this commodity was planned, and when.
  ///
  /// Raising it from nothing always puts it at the back of the queue, even
  /// if the order still carries it from earlier in the visit's life — a
  /// counter left at nought by a previous session, or a plan inherited from
  /// a build that did not record the order and was filled in from this
  /// list. Without that, a commodity the inspector has not touched today
  /// could still be named as the one they start with, which is the opposite
  /// of what the line under the plan promises.
  void _notePlanned(String kind, {required bool wasOnThePlan}) {
    if (!wasOnThePlan) _planOrder.remove(kind);
    if (!_planOrder.contains(kind)) _planOrder.add(kind);
  }

  /// Forgets a commodity taken back off the plan, so planning it again puts
  /// it at the back of the queue rather than where it first sat.
  void _forgetPlanned(String kind) {
    if ((_planned[kind] ?? 0) > 0 || _membersOf(kind).isNotEmpty) return;
    _planOrder.remove(kind);
  }

  /// Which poultry record the inspector is about to capture.
  ///
  /// Null when they back out, which leaves the slot untouched.
  Future<String?> _askPoultryKind() => showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Which poultry inspection?'),
          // Capped, because on a tablet an AlertDialog takes the width it is
          // given: three buttons in a row put the answer at one edge of the
          // screen and the question at the other.
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Poultry is inspected in two ways. Pick the one you '
                    'are doing now — the other can be done after it.',
                    style: TextStyle(height: 1.4, color: AppColors.inkSoft),
                  ),
                ),
                // Each answer says what it covers, so the choice can be made
                // without knowing what the forms are called.
                // Grading is not a door of its own: it follows the label
                // checklist when the inspector says so, on that form.
                _kindOption<String>(
                  dialogContext,
                  value: 'poultry_label',
                  icon: Icons.label_outline,
                  title: 'Labelling and grading',
                  detail: 'The label and container checklist first — what '
                      'is printed on the pack and the container it is in. '
                      'Grading and classification of the bird can follow; '
                      'the form asks.',
                ),
                const SizedBox(height: 10),
                _kindOption<String>(
                  dialogContext,
                  value: 'quid',
                  icon: Icons.water_drop_outlined,
                  title: 'QUID verification',
                  detail: 'Weighing for absorbed moisture — water chilling '
                      'or brine injection — against the declared '
                      'percentage.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

  /// Which raw record the inspector is about to capture — the raw
  /// inspection, or the compositional checklist on its own. Asked the way
  /// poultry is (Ethan, 2026-09-24). Null when they back out.
  Future<RawRecordKind?> _askRawKind() => showDialog<RawRecordKind>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Which raw inspection?'),
          // Capped like the poultry chooser, and built from the same parts.
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Raw is inspected in two ways. Pick the one you are '
                    'doing now — the other can be done after it.',
                    style: TextStyle(height: 1.4, color: AppColors.inkSoft),
                  ),
                ),
                _kindOption<RawRecordKind>(
                  dialogContext,
                  value: RawRecordKind.inspection,
                  icon: Icons.assignment_outlined,
                  title: 'Raw inspection',
                  detail: 'Labels, containers, sampling and the laboratory.',
                ),
                const SizedBox(height: 10),
                _kindOption<RawRecordKind>(
                  dialogContext,
                  value: RawRecordKind.composition,
                  icon: Icons.science_outlined,
                  title: 'Compositional checklist',
                  detail: 'The Regulation 5 compositional requirements '
                      '(SOP-APS-RAW-003) — the Compositional Checklist '
                      'document.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

  /// One answer on a "which inspection?" chooser: what it is, and what it
  /// covers. Poultry and raw share it, so the two popups look the same.
  Widget _kindOption<T>(
    BuildContext dialogContext, {
    required T value,
    required IconData icon,
    required String title,
    required String detail,
  }) =>
      Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(dialogContext).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: AppColors.brandPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.muted),
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

  /// Done means submitted — a draft holds its slot but does not meet it.
  bool get _planMet =>
      // An occurrence report stands on its own: it may be signed off with no
      // inspections planned at all, as APS files it as its own record.
      (_members.isNotEmpty || _isOccurrence) &&
      _members.every((m) => m.completed) &&
      (_isOccurrence ||
          _kinds.every((k) => _completedOf(k.kind) >= (_planned[k.kind] ?? 0)));

  /// What the door still has to say before an inspection may start or the
  /// visit be signed off (Ethan, 2026-09-24). Every record carries the
  /// facility's name and address; the documents go to the contact email;
  /// the invoice is billed on the distance. The person in charge is asked
  /// for at sign-off, because an occurrence report may have found nobody.
  List<String> _detailsMissing({required bool signingOff}) => [
        if (_facilityName.text.trim().isEmpty) 'the facility name',
        // Marked mandatory and now held to it (Ethan, 2026-09-24): every
        // inspection in the visit takes both from here.
        if (!_isOccurrence && _facilityType.trim().isEmpty)
          'the inspection facility type',
        if (!_isOccurrence && _inspectionReason.trim().isEmpty)
          'the reason for inspection',
        // The forms no longer ask for it (Ethan, 2026-09-25).
        if (_producerApplies && _producer.text.trim().isEmpty)
          'the producer / supplier',
        if (_facilityAddress.text.trim().isEmpty) 'the facility address',
        if (signingOff && !_isOccurrence && _contactPerson.text.trim().isEmpty)
          'the person in charge / representative at store',
        if (!_isOccurrence && _contactEmail.text.trim().isEmpty)
          'the contact email',
        if (double.tryParse(_distanceTravelled.text.trim()) == null)
          'the distance travelled (km)',
      ];

  /// "a, b and c" — a sentence, not a list.
  static String _listed(List<String> items) => switch (items.length) {
        0 => '',
        1 => items.single,
        _ => '${items.sublist(0, items.length - 1).join(', ')} and '
            '${items.last}',
      };

  /// Says what is missing and returns true when something is.
  bool _stoppedByMissingDetails({required bool signingOff}) {
    final missing = _detailsMissing(signingOff: signingOff);
    if (missing.isEmpty) return false;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          'Fill in ${_listed(missing)} before '
          '${signingOff ? 'signing off' : 'starting an inspection'}.',
        ),
      ));
    return true;
  }

  Future<void> _startNext() async {
    final slot = _nextSlot;
    if (slot == null) return;
    if (_stoppedByMissingDetails(signingOff: false)) return;
    await _persist();
    final visitRow = await widget.visits.byUuid(widget.visitUuid);
    if (visitRow == null || !mounted) return;
    final prefill = widget.visits.prefillOf(visitRow);

    // An unfinished inspection reopens where it stood; only a clean slot
    // starts a fresh form.
    final resumeUuid = slot.resume?.uuid;

    // Poultry is two inspections, and which one this is is answered here
    // rather than at the door: the inspector knows what is in front of them
    // once they are standing at it. Resuming keeps whatever the record
    // already is.
    var kind = slot.kind;
    if (kind == 'poultry') {
      if (slot.resume != null) {
        kind = slot.resume!.kind;
      } else {
        final chosen = await _askPoultryKind();
        if (chosen == null || !mounted) return;
        kind = chosen;
      }
    }
    // A QUID determination already set up carries on at the weighing
    // screen, against its own record. The set-up form only ever starts
    // one, and reopening it blank read as the set-up having been lost.
    if (kind == 'quid' && slot.resume != null) {
      await _continueMember(slot.resume!);
      return;
    }
    // Raw likewise: the inspection, or the compositional checklist.
    var rawKind = RawRecordKind.both;
    if (kind == 'rawrmp' && slot.resume == null) {
      final chosen = await _askRawKind();
      if (chosen == null || !mounted) return;
      rawKind = chosen;
    }

    final Widget form = switch (kind) {
      'egg' => EggInspectionForm(
          repository: widget.eggs,
          inspectorName: widget.inspectorName,
          syncService: widget.eggsSync,
          resumeUuid: resumeUuid,
          visit: prefill,
        ),
      'poultry' => PoultryInspectionForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: resumeUuid,
          visit: prefill,
        ),
      'rawrmp' => RawRmpInspectionForm(
          repository: widget.rawRmp,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: resumeUuid,
          visit: prefill,
          recordKind: rawKind,
        ),
      'pmp' => PmpInspectionForm(
          repository: widget.pmp,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: resumeUuid,
          visit: prefill,
        ),
      'quid' => PoultryQuidSetupForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          visit: prefill,
        ),
      _ => PoultryLabelChecklistForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: resumeUuid,
          visit: prefill,
        ),
    };

    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => form));
    unawaited(_load());
  }

  /// An unfinished row is work the inspector should be able to select and
  /// continue. It keeps that row's UUID, so its samples, photographs and
  /// details are never replaced with a new inspection.
  Future<void> _continueMember(VisitMember member) async {
    if (member.completed) return;
    await _persist();
    final visit = await widget.visits.byUuid(widget.visitUuid);
    if (visit == null || !mounted) return;
    final prefill = widget.visits.prefillOf(visit);
    // QUID is continued against its own record rather than rebuilt from the
    // visit, so the set-up's injectors and the carcasses already weighed
    // come back with it.
    if (member.kind == 'quid') {
      final quid =
          await widget.poultryCapture.quidInspectionByUuid(member.uuid);
      if (quid == null || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PoultryQuidWeighingForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspection: quid,
        ),
      ));
      if (mounted) await _load();
      return;
    }
    final Widget? form = switch (member.kind) {
      'egg' => EggInspectionForm(
          repository: widget.eggs,
          inspectorName: widget.inspectorName,
          syncService: widget.eggsSync,
          resumeUuid: member.uuid,
          visit: prefill),
      'poultry' => PoultryInspectionForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: member.uuid,
          visit: prefill),
      'rawrmp' => RawRmpInspectionForm(
          repository: widget.rawRmp,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: member.uuid,
          visit: prefill),
      'pmp' => PmpInspectionForm(
          repository: widget.pmp,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: member.uuid,
          visit: prefill),
      // 'poultry_label', and anything added later that has no case of its
      // own: opening the wrong form against this uuid would write one kind
      // of record over another, so the kinds are named.
      'poultry_label' => PoultryLabelChecklistForm(
          repository: widget.poultry,
          captureRepository: widget.poultryCapture,
          inspectorName: widget.inspectorName,
          existingUuid: member.uuid,
          visit: prefill),
      _ => null,
    };
    if (form == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('${member.label} cannot be continued here.'),
          ));
      }
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => form));
    if (mounted) await _load();
  }

  Future<void> _complete() async {
    if (_members.isEmpty && !_isOccurrence) return;
    if (_isOccurrence && _occurrenceDescription.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Describe the events of the occurrence before '
              'signing off.'),
        ));
      return;
    }
    if (_isOccurrence && _occurrencePhotos.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Take at least one photograph before signing off '
              'the occurrence report.'),
        ));
      return;
    }
    // Someone has to be named as having been there for an inspection: the
    // documents are addressed to them, at the contact email. An occurrence
    // report may have found nobody in charge, and says so by leaving the
    // name blank — but it was still a trip to an address.
    if (_stoppedByMissingDetails(signingOff: true)) return;
    // Addresses are taken as typed: the server keeps a malformed one
    // rather than refusing the record, so a typo cannot hold a signed-off
    // visit on the handset.
    await _persist();
    if (!mounted) return;

    final storage = await PhotoStorage.instance();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (!mounted) return;

    // The client's signature is theirs to give: if they will not or cannot
    // sign, "No client signature" records that and the sign-off goes on to
    // the inspector, whose signature is never optional.
    final managerPath = await captureSignature(
      context,
      title: 'Store / Client Signature',
      caption: _isOccurrence && _members.isEmpty
          ? 'To be signed by the store owner, manager or client, if they '
              'will sign. This signature goes on the occurrence report.'
          : 'To be signed by the store owner, manager or client, if they '
              'will sign. This signature is applied to every inspection in '
              'this grouped inspection.',
      declineLabel: 'No client signature',
      outputPath:
          storage.pathFor('visit_${widget.visitUuid}_manager_$stamp.png'),
    );
    if (managerPath == null || !mounted) return;

    final inspectorPath = await captureSignature(
      context,
      title: 'Inspector Signature',
      caption: 'To be signed by the inspector. This signature is applied to '
          'every inspection in this grouped inspection.',
      outputPath:
          storage.pathFor('visit_${widget.visitUuid}_inspector_$stamp.png'),
    );
    if (inspectorPath == null || !mounted) return;

    setState(() => _completing = true);
    try {
      // GPS is collected as background evidence only after both signatures.
      final location = await _captureLocationAfterSignatures();
      await widget.visits.complete(
        visitUuid: widget.visitUuid,
        managerSignaturePath: managerPath,
        inspectorSignaturePath: inspectorPath,
        managerName: _contactPerson.text.trim(),
        inspectorName: widget.inspectorName,
        latitude: location?.latitude,
        longitude: location?.longitude,
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
    if (!mounted) return;
    setState(() => _completed = true);
    // Everything just became submitted — push it to the server right now
    // rather than waiting for someone to remember Server Sync.
    unawaited(AutoSync.instance.kick());
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(_isOccurrence
            ? (_members.isEmpty
                ? 'Signed off — occurrence report submitted. This facility '
                    'is done.'
                : 'Signed off — occurrence report and ${_members.length} '
                    'inspection(s) submitted. This facility is done.')
            : 'Signed off — ${_members.length} inspection(s) submitted. '
                'This facility is done.'),
      ));
    // The facility is done — back to the home page. Popped one page at a
    // time rather than with popUntil(isFirst): the sign-in page is the
    // first route and home sits on top of it, so popping to the root would
    // look like being signed out mid-job. The list page closes itself when
    // it sees this result.
    Navigator.of(context).pop(_signedOffResult);
  }

  Future<Position?> _captureLocationAfterSignatures() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } on Object {
      return null;
    }
  }

  /// [revealing] fields redraw the page as they are typed, because what is
  /// on it depends on them — the next recipient box only exists once the
  /// one above it is filled.
  Widget _field(String label, TextEditingController controller,
          {bool required = false, bool revealing = false, FocusNode? focus}) =>
      LabelledField(
        label: label,
        isRequired: required,
        child: TextField(
          controller: controller,
          focusNode: focus,
          enabled: !_completed,
          onChanged: (_) {
            if (revealing) setState(() {});
            unawaited(_persist());
          },
          style: const TextStyle(fontSize: 15.5),
        ),
      );

  /// Takes one off the plan, and the draft with it if there is one.
  Future<void> _reducePlan(
      ({String kind, String label, String single, String short}) k) async {
    final planned = _planned[k.kind] ?? 0;
    final captured = _captured(k.kind);
    // A plan already at nought can still have records under it — one left
    // behind by an earlier build, or a commodity reduced while a record was
    // still being captured. The minus has to be able to clear those too, or
    // the inspection sits under "captured so far" with nothing able to
    // reach it and the visit will not sign off.
    if (planned <= 0 && captured == 0) return;
    // What the plan will ask for afterwards. Never below nought, so a plan
    // already there does not offer to take it "down to -1".
    final next = planned > 0 ? planned - 1 : 0;
    final members = _membersOf(k.kind);
    final drafts = members.where((m) => !m.completed).length;

    // Reducing past what has been captured would leave an inspection
    // nothing asks for, which the visit would then refuse to sign off on —
    // so the inspection goes with it.
    //
    // A finished one goes too, while the group is still unsigned. It used
    // to be kept on the grounds that captured work is the office's to
    // remove, but before sign-off the office has none of it: an inspector
    // who captured an egg inspection against the wrong product was left
    // with a plan they could not reduce and a visit they could not sign
    // off. The warning below is what stands between the two.
    if (next < captured && members.isNotEmpty) {
      final losingCaptured = drafts == 0;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(losingCaptured
              ? 'Discard this entire inspection?'
              : 'Discard the unfinished inspection?'),
          content: Text(
            losingCaptured
                ? 'Taking ${k.label.toLowerCase()} down to $next '
                    'discards the whole inspection you have just completed — '
                    'every reading, deviation, photograph and signature on '
                    'it. It has not been signed off or sent to the office, '
                    'so it cannot be brought back from here.'
                : 'Taking ${k.label.toLowerCase()} down to $next '
                    'also discards the one that was started and not '
                    'finished. Anything captured on it is lost.',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: losingCaptured
                      ? AppColors.brandRed
                      : AppColors.brandPrimary),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.visits.discardDraftMember(
        widget.visitUuid,
        k.kind,
        includeCaptured: losingCaptured,
      );
    }

    if (!mounted) return;
    setState(() {
      // Never below nought: reducing a plan that is already there is about
      // the records under it, not the count.
      _planned[k.kind] = next;
      _forgetPlanned(k.kind);
    });
    await _persist();
    await _load();
  }

  /// Says which commodity the visit will open first, and why it is that one.
  ///
  /// The plan is walked in the order the counters were raised, not in the
  /// order this list happens to print — so an inspector who wants to do the
  /// raw counter before the eggs simply adds raw first. That rule was
  /// invisible: nothing on the page said the order mattered, and the only
  /// way to find out was to tap START and be given the wrong form.
  ///
  /// Shown only once something is on the plan, because until then there is
  /// no first.
  Widget _planOrderNote() {
    final planned =
        _plannedKinds.where((k) => (_planned[k.kind] ?? 0) > 0).toList();
    if (planned.isEmpty) return const SizedBox.shrink();
    // Spelled out rather than stated as a rule: the queue itself is the
    // clearest way to say what the order is.
    final queue = planned.map((k) => k.short).join(', then ');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              planned.length == 1
                  ? "You'll start with $queue."
                  : 'The first one you pick is the first one you do: $queue.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planRow(
      ({String kind, String label, String single, String short}) k) {
    final planned = _planned[k.kind] ?? 0;
    final captured = _captured(k.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (planned > 0 || captured > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                // Done means submitted; a draft in progress is not done.
                '${_completedOf(k.kind)} of $planned done',
                style: TextStyle(
                  fontSize: 12.5,
                  color: _completedOf(k.kind) >= planned && planned > 0
                      ? AppColors.brandTeal
                      : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            // The plan comes down as far as zero until the visit is signed
            // off, a finished inspection included.
            //
            // It used to stop at whatever had been captured, on the grounds
            // that a captured inspection is a record. Before sign-off the
            // office has none of it, and an inspector who captured an
            // inspection against the wrong product was left holding a plan
            // that would not come down and a visit that would not go up.
            // _reducePlan warns before a finished one goes.
            onPressed: _completed ? null : () => unawaited(_reducePlan(k)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '$planned',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _completed
                ? null
                : () => setState(() {
                      _planned[k.kind] = planned + 1;
                      _notePlanned(k.kind, wasOnThePlan: planned > 0);
                      unawaited(_persist());
                    }),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body:
              ContentWidth(child: Center(child: CircularProgressIndicator())));
    }
    final next = _nextSlot;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: const Text(
          'Inspection',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      body: ContentWidth(
          child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (_completed)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.brandTeal.withValues(alpha: 0.08),
                border: Border.all(
                    color: AppColors.brandTeal.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'This inspection is signed off. Its details are read-only.',
                style: TextStyle(height: 1.35),
              ),
            ),
          Text(
            'FACILITY — CAPTURED ONCE, USED BY EVERY INSPECTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          // Picking a premises from the directory fills the address and
          // telephone, exactly as the egg form's facility box does. A store
          // that is not on the list can still be typed in.
          IgnorePointer(
            ignoring: _completed,
            child: SearchPickerField<EggFacility>(
              label: 'Facility name',
              controller: _facilityName,
              options: _directory,
              optionLabel: (f) => f.name,
              optionSubtitle: (f) => f.physicalAddress,
              onSelected: (facility) => unawaited(_facilityChosen(facility)),
              isRequired: true,
              // A store that is not on the list is registered from here
              // rather than typed loose: the next inspector at the same
              // premises finds it on the list instead of naming it again,
              // differently.
              addNewLabel: 'Add new',
              onAddNew: _addFacility,
              emptyHint: 'No premises on this device yet. Sync from the Eggs '
                  'menu to download the directory.',
            ),
          ),
          // Asked once here for the whole group instead of on every
          // inspection inside it; each form finds its own row for the
          // answer and only asks again if its list has nothing like it.
          IgnorePointer(
            ignoring: _completed,
            child: PickerMenuField<String>(
              label: 'Inspection facility type',
              isRequired: true,
              value: _facilityTypeOptions.contains(_facilityType)
                  ? _facilityType
                  : null,
              options: [
                for (final name in _facilityTypeOptions)
                  (value: name, text: name),
              ],
              onChanged: (v) {
                setState(() => _facilityType = v ?? '');
                unawaited(_persist());
              },
            ),
          ),
          // Likewise the reason: one answer for the errand, not one per
          // inspection captured during it.
          IgnorePointer(
            ignoring: _completed,
            child: PickerMenuField<String>(
              label: 'Reason for inspection',
              isRequired: true,
              value: _inspectionReasonOptions.contains(_inspectionReason)
                  ? _inspectionReason
                  : null,
              options: [
                for (final name in _inspectionReasonOptions)
                  (value: name, text: name),
              ],
              onChanged: (v) {
                setState(() => _inspectionReason = v ?? '');
                unawaited(_persist());
              },
            ),
          ),
          _field('Facility address', _facilityAddress,
              required: true, focus: _facilityAddressFocus),
          _field('Facility telephone / cellphone', _facilityPhone),
          // Asked once for the whole visit (Ethan, 2026-09-24): every raw,
          // processed meat and egg inspection under it starts with this
          // producer filled in. Only those commodities have a producer, so
          // the question is only asked when one of them is on the plan.
          if (_producerApplies) ...[
            _field('Producer / supplier', _producer, required: true),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                'Filled in on every raw, processed meat and egg inspection '
                'in this visit. A product from a different producer can '
                'still be changed on its own form.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          ],
          // One person, asked once. The visit used to ask for a contact, a
          // representative and an authorised manager, which at a store is
          // the same person answering the same question three times — and
          // the address it is asked for is the one the documents go to.
          // Named for an inspection — the documents are addressed to them.
          // An occurrence report may have found nobody in charge to name.
          _field('Person in charge / Representative at store', _contactPerson,
              required: !_isOccurrence),
          _field('Contact email', _contactEmail, required: !_isOccurrence),
          // The original asks for these two on every commodity form. A visit
          // is one errand to one site, so they are asked once, here, and
          // carried onto every record captured under it.
          _field('Additional email #1 (optional)', _additionalEmail1,
              revealing: true),
          // The second appears once the first is used, the third once both
          // are — a visit with no extra recipients shows one empty box, not
          // three.
          if (_additionalEmail1.text.trim().isNotEmpty ||
              _additionalEmail2.text.trim().isNotEmpty)
            _field('Additional email #2 (optional)', _additionalEmail2,
                revealing: true),
          if (_additionalEmail1.text.trim().isNotEmpty &&
              _additionalEmail2.text.trim().isNotEmpty)
            _field('Additional email #3 (optional)', _additionalEmail3),
          // The trip, not the product: one journey to one facility, whatever
          // was inspected there.
          _field('Distance travelled (km)', _distanceTravelled, required: true),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'What the invoice is billed on, at R6.50 per kilometre.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 10),
          // The plan belongs to inspections. An occurrence report is not one,
          // so once the visit is marked as such the plan is put away and the
          // report is written in its place.
          if (!_isOccurrence) ...[
            Text(
              'PLAN — HOW MANY OF EACH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            for (final k in _kinds) _planRow(k),
            _planOrderNote(),
          ],
          const SizedBox(height: 14),
          // After the plan, as its own question: APS files an occurrence
          // report under its own badge, and the report is written right here.
          // Not asked when a filed visit is only being corrected.
          if (!widget.detailsOnly)
            IgnorePointer(
              ignoring: _completed,
              child: _OccurrenceQuestion(
                value: _isOccurrence,
                onChanged: (v) {
                  setState(() => _isOccurrence = v);
                  unawaited(_persist());
                },
              ),
            ),
          if (_isOccurrence) _occurrenceSection(),
          const SizedBox(height: 14),
          if (!_completed) ...[
            if (next != null) ...[
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _startNext,
                  // Scales the label down rather than wrapping it — the
                  // longest commodity names stay on one line.
                  // No counter on the button — CAPTURED SO FAR below
                  // already keeps the score.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      // The one about to be opened, so singular: "START
                      // CERTAIN RAW PROCESSED MEAT PRODUCT INSPECTION".
                      next.resume != null
                          ? 'CONTINUE ${next.single.toUpperCase()}'
                          : 'START ${next.single.toUpperCase()}',
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The flow walks the plan one commodity at a time; each form '
                'opens with the facility above already filled in.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.muted, height: 1.35),
              ),
            ] else if (_members.isEmpty && !_isOccurrence)
              Text(
                'Set the plan above — for example 2 poultry and 2 raw — and '
                'the flow will walk you through them.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
            if (_planMet && next == null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _completing ? null : _complete,
                  // An occurrence report signs off in its own colour, so the
                  // inspector can see at the last step which kind of record
                  // they are about to file.
                  style: _isOccurrence && _members.isEmpty
                      ? ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandOrange,
                          foregroundColor: Colors.white,
                        )
                      : null,
                  child: _completing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _isOccurrence && _members.isEmpty
                                ? 'SIGN & SUBMIT OCCURRENCE REPORT'
                                : 'SIGN & SUBMIT ALL INSPECTIONS',
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 13, letterSpacing: 0.4),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isOccurrence && _members.isEmpty
                    ? 'Your signature, and the client\'s if they will sign, '
                        'on the occurrence report. Only then is it '
                        'submitted; until this, nothing has been sent.'
                    : 'Your signature, and the client\'s if they will sign, '
                        'stamped onto every inspection captured above. Only '
                        'then is everything submitted; until this, nothing '
                        'has been sent.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.muted, height: 1.35),
              ),
            ],
          ],
          const SizedBox(height: 14),
          if (_members.isNotEmpty) ...[
            Text(
              'CAPTURED SO FAR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            for (final member in _members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  member.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color:
                      member.completed ? AppColors.brandTeal : AppColors.muted,
                ),
                title: Text(member.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(member.completed
                    ? (_completed
                        ? 'Submitted'
                        : 'Captured — submits at the final sign-off')
                    : 'Still in progress'),
                trailing: member.completed
                    ? null
                    : const Icon(Icons.play_arrow, color: AppColors.brandTeal),
                onTap: member.completed ? null : () => _continueMember(member),
              ),
          ],
        ],
      )),
    );
  }
}

/// "Is this an occurrence report?" — a plain yes or no.
///
/// The report itself (findings, description, signatures) is written on the
/// APS system; the handset only records the answer so APS files the visit
/// as an occurrence report from the start.
class _OccurrenceQuestion extends StatelessWidget {
  const _OccurrenceQuestion({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Is this an occurrence report?',
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(height: 8),
          // Orange, not the brand teal: an occurrence report is its own
          // kind of record and APS badges it in orange throughout, so the
          // switch that turns a visit into one says so in the same colour
          // (FSA, 2026-09-08).
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('No')),
              ButtonSegment(value: true, label: Text('Yes')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.brandOrange
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : palette.ink,
              ),
              side: WidgetStateProperty.all(
                BorderSide(
                    color: value ? AppColors.brandOrange : palette.border),
              ),
            ),
          ),
          if (value)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No inspections are planned for an occurrence report. Write '
                'the report below and sign it off; APS files this visit as '
                'an occurrence.',
                style: TextStyle(
                    fontSize: 12.5, color: palette.muted, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}
