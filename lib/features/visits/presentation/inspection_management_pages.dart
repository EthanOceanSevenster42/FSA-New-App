import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/platform/downloads.dart';
import '../../../core/theme/app_theme.dart';
import 'package:printing/printing.dart';

import '../../eggs/data/eggs_repository.dart';
import '../../invoicing/data/invoice_repository.dart';
import '../../sync/auto_sync.dart';
import '../data/visit_repository.dart';
import '../../../core/documents/pdf_merge.dart';
import '../../eggs/presentation/egg_inspection_form.dart';
import '../../pmp/data/pmp_repository.dart';
import '../../pmp/presentation/pmp_inspection_form.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../../poultry/data/poultry_repository.dart';
import '../../poultry/presentation/poultry_inspection_form.dart';
import '../../poultry/presentation/poultry_quid_continue_page.dart';
import '../../rawrmp/data/rawrmp_repository.dart';
import '../../rawrmp/presentation/rawrmp_inspection_form.dart';
import '../../seizures/data/seizure_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import '../data/record_documents.dart';
import 'commodity_inspection_view.dart';
import 'store_visit_pages.dart';

/// "1 inspection", "3 inspections" — the bracketed plural read as unfinished
/// on a screen the office and the client both see.
String _countOf(int howMany) => '$howMany inspection${howMany == 1 ? '' : 's'}';

/// Every grouped inspection on the device — one card per facility visit;
/// open a card to see the individual inspections captured inside it.
/// Standalone capture is retired: all work goes through grouped
/// inspections, so that is all this screen lists.
class InspectionManagementPage extends StatefulWidget {
  const InspectionManagementPage({
    super.key,
    required this.visits,
    required this.eggs,
    required this.invoices,
    required this.database,
  });

  final VisitRepository visits;
  final EggsRepository eggs;
  final InvoiceRepository invoices;
  final LocalDatabase database;

  @override
  State<InspectionManagementPage> createState() =>
      _InspectionManagementPageState();
}

class _InspectionManagementPageState extends State<InspectionManagementPage> {
  List<StoreVisit> _visits = const [];
  Map<String, List<VisitMember>> _membersByVisit = const {};

  /// How many of each visit's inspections ended in a seizure — FSA-SOP-
  /// APS-001 Annexure E, marked on the card so a seizure is seen from the
  /// list and not only from inside the visit.
  Map<String, int> _seizuresByVisit = const {};

  /// Visits brought down from the server rather than captured here.
  Set<String> _fromServer = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // A finished pass may have flipped records to uploaded, so reload once
    // the sync running behind this screen settles.
    AutoSync.instance.completedPasses.addListener(_load);
    // Anything waiting goes up as soon as this screen is opened, without a
    // button to press (Ethan, 2026-09-24).
    unawaited(AutoSync.instance.kick());
  }

  @override
  void dispose() {
    AutoSync.instance.completedPasses.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // Only finished work belongs here: this screen is for reviewing what has
    // been signed off and checking it reached the server. An inspection
    // still being captured lives under the Inspection tile, where it can be
    // carried on with.
    await widget.visits.purgeUploadedVisits();
    final visits = (await widget.visits.allVisits())
        .where((v) => v.completedAt != null)
        .toList();
    final membersByVisit = <String, List<VisitMember>>{};
    final seizuresByVisit = <String, int>{};
    final fromServer = <String>{};
    final seizures = SeizureRepository(database: widget.database);
    for (final visit in visits) {
      final members = await widget.visits.members(visit.uuid);
      membersByVisit[visit.uuid] = members;
      seizuresByVisit[visit.uuid] =
          (await seizures.seizedAmong(members.map((m) => m.uuid))).length;
      if (await widget.visits.isFromServer(visit.uuid)) {
        fromServer.add(visit.uuid);
      }
    }
    if (!mounted) return;
    setState(() {
      _visits = visits;
      _membersByVisit = membersByVisit;
      _seizuresByVisit = seizuresByVisit;
      _fromServer = fromServer;
      _loading = false;
    });
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection Management')),
      body: ContentWidth(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Signed-off inspections and whether they have reached '
                        'the server. Inspections still being captured are under '
                        'the Inspection tile.',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                            height: 1.4),
                      ),
                    ),
                    // Why the last sync did not get everything up — said on
                    // screen, not swallowed.
                    ValueListenableBuilder<List<String>>(
                      valueListenable: AutoSync.instance.lastFailures,
                      builder: (context, failures, _) => failures.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.brandRed.withValues(alpha: 0.08),
                                border: Border.all(
                                    color: AppColors.brandRed
                                        .withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Last sync did not get everything up',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.brandRed),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final f in failures)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(f,
                                          style: const TextStyle(
                                              fontSize: 12.5, height: 1.35)),
                                    ),
                                ],
                              ),
                            ),
                    ),
                    if (_visits.isEmpty)
                      Text(
                        'Nothing signed off yet. Once a grouped inspection is '
                        'signed off it appears here.',
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                    for (final visit in _visits) _visitCard(visit),
                  ],
                )),
    );
  }

  Widget _visitCard(StoreVisit visit) {
    final members = _membersByVisit[visit.uuid] ?? const <VisitMember>[];
    final signedOff = visit.completedAt != null;
    final uploaded = members.where((m) => m.isUploaded).length;
    // An occurrence report with no inspections is one record — the visit
    // itself — so its state is the visit's own upload, not "0 of 0 sent".
    final occurrenceOnly = visit.isOccurrenceReport && members.isEmpty;
    // Occurrence reports are marked in orange so they stand apart from
    // ordinary inspections in the list.
    // One orange for occurrence work, wherever it shows.
    const occurrenceOrange = AppColors.brandOrange;
    // A visit with nothing captured under it is still a visit, and it does
    // go up on its own. Reading the members alone left it stuck at
    // "Pending upload (0 of 0 sent)" for ever — the office had the group,
    // the inspector was told it had not been sent, and no amount of Server
    // Sync could clear it. With no members, the visit's own flag is the
    // whole answer, exactly as it is for an occurrence report.
    final (String state, Color colour) = !signedOff
        ? ('Still open', AppColors.brandRed)
        : occurrenceOnly
            ? (visit.isUploaded
                ? ('Occurrence report synced', occurrenceOrange)
                : ('Occurrence report not synced', occurrenceOrange))
            : members.isEmpty
                ? (visit.isUploaded
                    ? ('Synced', AppColors.brandTeal)
                    : ('Not synced', AppColors.noticeForeground))
                : uploaded >= members.length
                    ? ('Synced', AppColors.brandTeal)
                    : (
                        'Not synced ($uploaded of ${members.length} sent)',
                        AppColors.noticeForeground
                      );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Icon(
          visit.isOccurrenceReport
              ? Icons.report_problem_outlined
              : signedOff
                  ? Icons.storefront
                  : Icons.storefront_outlined,
          color: visit.isOccurrenceReport ? occurrenceOrange : colour,
        ),
        title: Text(
          visit.facilityName.isEmpty
              ? 'Facility not named yet'
              : visit.facilityName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visit.isOccurrenceReport
                  ? '${_dmy(visit.startedAt)} · 1 occurrence'
                      '${members.isEmpty ? '' : ' · ${_countOf(members.length)}'}'
                  : '${_dmy(visit.startedAt)} · ${_countOf(members.length)}',
              style: TextStyle(
                fontSize: 12.5,
                color: visit.isOccurrenceReport ? occurrenceOrange : null,
                fontWeight: visit.isOccurrenceReport ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 2),
            // While a pass is in flight the pending line says so, so nothing
            // that is actually being sent looks stuck.
            ValueListenableBuilder<bool>(
              valueListenable: AutoSync.instance.isSyncing,
              builder: (context, syncing, _) {
                final pending = signedOff && uploaded < members.length;
                if (syncing && pending) {
                  return ValueListenableBuilder<({int done, int total})?>(
                    valueListenable: AutoSync.instance.progress,
                    builder: (context, sent, _) => Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brandTeal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sent == null
                              ? 'Uploading…'
                              : 'Uploading ${sent.done} of ${sent.total} '
                                  'inspections',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandTeal,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Text(
                  state,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                );
              },
            ),
            // Approved or not, beside synced or not (Ethan, 2026-09-24).
            if (signedOff) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    visit.approvedAt != null
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 14,
                    color: visit.approvedAt != null
                        ? const Color(0xFF2E7D32)
                        : AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    visit.approvedAt != null ? 'Approved' : 'Not approved',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: visit.approvedAt != null
                          ? const Color(0xFF2E7D32)
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
            // Held on the server, not captured on this tablet.
            if (_fromServer.contains(visit.uuid)) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.cloud_download_outlined,
                      size: 14, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    'From the server',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
            // A consignment seized on this visit, in the rejection red.
            if ((_seizuresByVisit[visit.uuid] ?? 0) > 0) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.gavel, size: 14, color: AppColors.brandRed),
                  const SizedBox(width: 6),
                  Text(
                    _seizuresByVisit[visit.uuid] == 1
                        ? 'Seizure served'
                        : '${_seizuresByVisit[visit.uuid]} seizures served',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandRed,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupedInspectionViewPage(
                visit: visit,
                members: members,
                eggs: widget.eggs,
                invoices: widget.invoices,
                database: widget.database,
                fromServer: _fromServer.contains(visit.uuid),
              ),
            ),
          );
          // The visit page approves, un-approves and corrects; the card
          // was still drawn from the row read when this list opened, so an
          // approval taken back kept showing as given (Ethan, 2026-09-26).
          if (mounted) await _load();
        },
      ),
    );
  }
}

/// One grouped inspection opened up: the facility details and every
/// individual inspection captured inside it. Egg inspections open into
/// their full detail — particulars, results, photographs and signatures.
class GroupedInspectionViewPage extends StatelessWidget {
  const GroupedInspectionViewPage({
    super.key,
    required this.visit,
    required this.members,
    required this.eggs,
    required this.invoices,
    required this.database,
    this.fromServer = false,
  });

  final StoreVisit visit;
  final List<VisitMember> members;
  final EggsRepository eggs;
  final InvoiceRepository invoices;
  final LocalDatabase database;

  /// Brought down from the server: shown as the office holds it, never
  /// edited here, since this tablet holds only the outline of the record.
  final bool fromServer;

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final signedOff = visit.completedAt != null;

    // "2 × Egg inspection · 2 × Raw Processed Meat" — what this group holds.
    final countsByLabel = <String, int>{};
    for (final m in members) {
      countsByLabel[m.label] = (countsByLabel[m.label] ?? 0) + 1;
    }
    final contents = [
      for (final e in countsByLabel.entries) '${e.value} × ${e.key}',
    ].join('  ·  ');

    Widget info(IconData icon, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                        fontSize: 13, height: 1.3, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Grouped Inspection')),
      body: ContentWidth(
          child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        visit.facilityName.isEmpty
                            ? 'Facility not named'
                            : visit.facilityName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: AutoSync.instance.isSyncing,
                      builder: (context, syncing, _) {
                        final uploaded =
                            members.where((m) => m.isUploaded).length;
                        if (!signedOff) {
                          return _pill('STILL OPEN', AppColors.brandRed);
                        }
                        // An occurrence report with no inspections is judged
                        // by the visit's own upload, in the occurrence orange.
                        if (visit.isOccurrenceReport && members.isEmpty) {
                          return visit.isUploaded
                              ? _pill('OCCURRENCE UPLOADED',
                                  const Color(0xFFF57C00))
                              : _pill('OCCURRENCE PENDING',
                                  const Color(0xFFF57C00));
                        }
                        if (uploaded >= members.length && members.isNotEmpty) {
                          return _pill('UPLOADED', AppColors.brandTeal);
                        }
                        return syncing
                            ? _pill('UPLOADING…', AppColors.brandTeal)
                            : _pill(
                                'PENDING UPLOAD', AppColors.noticeForeground);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                info(
                    Icons.event_outlined,
                    'Started ${_dmy(visit.startedAt)}'
                    '${signedOff ? '  ·  Signed off & submitted '
                        '${_dmy(visit.completedAt!)}' : ''}'),
                info(Icons.location_on_outlined, visit.facilityAddress),
                info(Icons.call_outlined, visit.facilityPhone),
                info(Icons.person_outline, visit.contactPerson),
                // Said at the top of the visit, before the member cards.
                FutureBuilder<Set<String>>(
                  future: SeizureRepository(database: database)
                      .seizedAmong(members.map((m) => m.uuid)),
                  builder: (context, snap) {
                    final seized = snap.data?.length ?? 0;
                    if (seized == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.gavel,
                              size: 16, color: AppColors.brandRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              seized == 1
                                  ? 'A consignment was seized on this visit '
                                      '(FSA-SOP-APS-001 Annexure E).'
                                  : '$seized consignments were seized on '
                                      'this visit (FSA-SOP-APS-001 '
                                      'Annexure E).',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                info(
                    Icons.badge_outlined,
                    visit.managerName.isEmpty
                        ? ''
                        : 'Manager: ${visit.managerName}'),
                info(
                    Icons.assignment_ind_outlined,
                    visit.inspectorUsername.isEmpty
                        ? ''
                        : 'Inspector: ${visit.inspectorUsername}'),
                info(
                    Icons.fact_check_outlined,
                    visit.isOccurrenceReport && members.isEmpty
                        ? '1 occurrence report'
                        : '${_countOf(members.length)}  —  $contents'),
                if (visit.isOccurrenceReport) ...[
                  info(
                      Icons.schedule_outlined,
                      visit.occurrenceTimeOfVisit.isEmpty
                          ? ''
                          : 'Time of visit: ${visit.occurrenceTimeOfVisit}'),
                  info(
                      Icons.tag,
                      visit.occurrenceRegistrationCode.isEmpty
                          ? ''
                          : 'Registration code: '
                              '${visit.occurrenceRegistrationCode}'),
                  info(
                      Icons.notes_outlined,
                      visit.occurrenceDescription.isEmpty
                          ? ''
                          : 'Description of events: '
                              '${visit.occurrenceDescription}'),
                ],
                if (signedOff)
                  info(
                    Icons.cloud_upload_outlined,
                    visit.isOccurrenceReport && members.isEmpty
                        ? (visit.isUploaded
                            ? 'Occurrence report uploaded to the server'
                            : 'Occurrence report pending upload — run Server '
                                'Sync to send it.')
                        // Nothing captured under the visit: the visit's own
                        // flag is the whole answer. Counting members left it
                        // reading "0 of 0 sent" long after the office had it.
                        : members.isEmpty
                            ? (visit.isUploaded
                                ? 'Uploaded to the server'
                                : 'Upload pending — run Server Sync to send '
                                    'it.')
                            : members.every((m) => m.isUploaded)
                                ? 'All inspections uploaded to the server'
                                : 'Upload pending — '
                                    '${members.where((m) => m.isUploaded).length} '
                                    'of ${members.length} sent. Run Server Sync '
                                    'to send the rest.',
                  ),
              ],
            ),
          ),
          if (visit.isOccurrenceReport) ...[
            const SizedBox(height: 16),
            const Text(
              'OCCURRENCE DOCUMENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.brandOrange,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The Occurrence Document (SOP-APS-009) for this visit, filled in '
              'from the report and its photographs.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      // An occurrence report is its own kind of record, and
                      // says so.
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandOrange,
                        side: BorderSide(
                            color:
                                AppColors.brandOrange.withValues(alpha: 0.5)),
                      ),
                      onPressed: () =>
                          _openOccurrence(context, download: false),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('VIEW OCCURRENCE',
                            maxLines: 1, style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandOrange,
                      ),
                      onPressed: () => _openOccurrence(context, download: true),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('DOWNLOAD OCCURRENCE',
                            maxLines: 1, style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // An occurrence report is not billed; the RFI belongs to the
          // inspections, so it is only offered when there are some.
          if (fromServer) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_download_outlined,
                    size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Brought down from the server. The full checklists and '
                    'the Request for Invoice are held there; this tablet '
                    'shows what was inspected and served, and cannot edit '
                    'it.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.muted, height: 1.35),
                  ),
                ),
              ],
            ),
            _VisitDocumentDownloads(
              database: database,
              visit: visit,
              members: members,
            ),
            if (signedOff) ...[
              const SizedBox(height: 14),
              _VisitApproval(visit: visit, database: database, eggs: eggs),
            ],
            const SizedBox(height: 18),
            Text(
              'INSPECTIONS IN THIS GROUP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            ..._numberedMemberCards(context),
          ] else if (!visit.isOccurrenceReport || members.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _editVisitDetails(context),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('EDIT VISIT DETAILS'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The facility, its address and contacts, the e-mail addresses '
              'the documents go to, and the kilometres billed. These belong '
              'to the whole visit, so a change here reaches every inspection '
              'in it.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 18),
            Text(
              'DOCUMENTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Everything this visit produced. The compliance checklists come '
              'down as one file, in the order the office files them.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => _openInvoice(context, download: false),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('VIEW RFI',
                            maxLines: 1, style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => _openInvoice(context, download: true),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('DOWNLOAD RFI',
                            maxLines: 1, style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _VisitDocumentDownloads(
              database: database,
              visit: visit,
              members: members,
            ),
            // Approved once the documents above have been looked over.
            if (signedOff) ...[
              const SizedBox(height: 14),
              _VisitApproval(visit: visit, database: database, eggs: eggs),
            ],
            const SizedBox(height: 18),
            Text(
              'INSPECTIONS IN THIS GROUP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            ..._numberedMemberCards(context),
            if (members.isEmpty)
              Text(
                'Nothing captured under this group yet.',
                style: TextStyle(color: AppColors.muted),
              ),
          ],
        ],
      )),
    );
  }

  /// Reopens the visit itself — the facility, its contacts, the addresses
  /// the documents are sent to and the kilometres billed.
  ///
  /// These sit on the visit rather than on any one inspection, so the office
  /// record for every commodity in the group carries them. The same screen
  /// the visit was captured on is used, so there is one place these fields
  /// are worded and validated.
  Future<void> _editVisitDetails(BuildContext context) async {
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => StoreVisitPage(
        visitUuid: visit.uuid,
        visits: VisitRepository(database),
        eggs: eggs,
        eggsSync: null,
        poultry: PoultryRepository(database: database, baseUrl: ''),
        poultryCapture:
            PoultryCaptureRepository(database: database, baseUrl: ''),
        rawRmp: RawRmpRepository(database: database, baseUrl: ''),
        pmp: PmpRepository(database: database, baseUrl: ''),
        inspectorName: visit.inspectorUsername,
        // A signed-off visit is being corrected, not re-planned: its
        // inspections stay where they are, and what kind of visit it is was
        // settled at the door.
        canRemoveRecords: false,
        detailsOnly: true,
      ),
    ));
    await VisitRepository(database).markChanged(visit.uuid);
  }

  /// Reopens a record in its own commodity form so the inspector can
  /// correct it, and marks the visit for re-sending if anything was saved.
  ///
  /// The forms already know how to load an existing record — this is the
  /// same route the commodity's own list uses — so a correction is made on
  /// the screen the inspection was captured on, not on a second one written
  /// to look like it.
  Future<bool> _editMember(BuildContext context, VisitMember member) async {
    final inspector = visit.inspectorUsername;
    // Taken before the record is read off disk: the context cannot be used
    // once this has waited on anything.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final capture = PoultryCaptureRepository(database: database, baseUrl: '');
    // The same shape the visit flow hands its forms.
    final prefill = VisitRepository(database).prefillOf(visit);
    // QUID is corrected on its own weighing screen, reopened against its
    // own record: the set-up's injectors and the carcasses already weighed
    // belong to it, not to the visit.
    final quid = member.kind == 'quid'
        ? await capture.quidInspectionByUuid(member.uuid)
        : null;
    // The visit goes with it. The forms write the group they belong to on
    // every save, so a record corrected without it is detached from its
    // group — the office loses the product line and the handset stops
    // listing the inspection under the visit at all.
    final form = switch (member.kind) {
      'rawrmp' => RawRmpInspectionForm(
          repository: RawRmpRepository(database: database, baseUrl: ''),
          captureRepository: capture,
          inspectorName: inspector,
          existingUuid: member.uuid,
          visit: prefill,
        ),
      'pmp' => PmpInspectionForm(
          repository: PmpRepository(database: database, baseUrl: ''),
          captureRepository: capture,
          inspectorName: inspector,
          existingUuid: member.uuid,
          visit: prefill,
        ),
      // The egg form reopens a record by the same uuid; it calls the
      // argument resumeUuid rather than existingUuid.
      'egg' => EggInspectionForm(
          repository: eggs,
          inspectorName: inspector,
          resumeUuid: member.uuid,
          visit: prefill,
        ),
      'poultry' => PoultryInspectionForm(
          repository: PoultryRepository(database: database, baseUrl: ''),
          captureRepository: capture,
          inspectorName: inspector,
          existingUuid: member.uuid,
          visit: prefill,
        ),
      'quid' when quid != null => PoultryQuidWeighingForm(
          repository: PoultryRepository(database: database, baseUrl: ''),
          captureRepository: capture,
          inspection: quid,
        ),
      _ => null,
    };
    if (form == null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('This kind of inspection cannot be corrected on the '
              'handset yet.'),
        ));
      return false;
    }

    await navigator.push(MaterialPageRoute<void>(builder: (_) => form));
    final visits = VisitRepository(database);
    // A record corrected after sign-off is still submitted. The capture
    // forms leave it as `ready`, which showed a signed-off inspection as
    // awaiting sign-off again.
    if (visit.completedAt != null) await visits.restoreSubmitted(member);
    // The forms save as they go, so a visit is marked changed whenever one
    // has been opened for correction: telling the office again costs a
    // sync, and not telling them costs the record.
    await visits.markChanged(visit.uuid);
    return true;
  }

  /// The Occurrence Document, built from the report on this visit the way
  /// the upload builds it, shown or saved to Downloads.
  Future<void> _openOccurrence(BuildContext context,
      {required bool download}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final file =
          await VisitRepository(database).buildOccurrenceDocument(visit);
      if (file == null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
              content: Text('Nothing has been written on this occurrence '
                  'report yet.')));
        return;
      }
      final bytes = await file.readAsBytes();
      if (download) {
        final saved = await Downloads.save(
          Downloads.documentName(
            visit.facilityName,
            'Occurrence-Report',
            visit.completedAt ?? visit.startedAt,
          ),
          bytes,
        );
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Saved to ${saved.where}'),
              duration: const Duration(seconds: 6),
              action: saved.uri.isEmpty
                  ? null
                  : SnackBarAction(
                      label: 'OPEN',
                      onPressed: () => Downloads.open(saved),
                    ),
            ),
          );
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Occurrence Document')),
            body: ContentWidth(
                child: PdfPreview(
              build: (_) => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: file.path.split(RegExp(r'[\\/]')).last,
            )),
          ),
        ),
      );
    } on Object catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
              content: Text('The occurrence document could not be built. $e')),
        );
    }
  }

  /// Builds the form from this inspection and either shows it or hands it
  /// to Android to save or send. Rendered on demand rather than kept: the
  /// record is the truth, the PDF is a printout of it.
  Future<void> _openInvoice(BuildContext context,
      {required bool download}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final form = await invoices.formFor(visit);
      final file = await invoices.renderPdf(form);
      final bytes = await file.readAsBytes();
      if (download) {
        // A download lands in the phone's own Downloads folder, where the
        // inspector can open it, attach it or hand it over — not in a share
        // sheet, and not in the app's private folder no file manager shows.
        // It is saved under the same name the office sees on the record.
        final saved = await Downloads.save(
          Downloads.documentName(
            visit.facilityName,
            'RFI',
            visit.completedAt ?? visit.startedAt,
          ),
          bytes,
        );
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Saved to ${saved.where}'),
              duration: const Duration(seconds: 6),
              action: saved.uri.isEmpty
                  ? null
                  : SnackBarAction(
                      label: 'OPEN',
                      onPressed: () => Downloads.open(saved),
                    ),
            ),
          );
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Request for Invoice')),
            body: ContentWidth(
                child: PdfPreview(
              build: (_) => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: file.path.split(RegExp(r'[\\/]')).last,
            )),
          ),
        ),
      );
    } on Object catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('The invoice form could not be built. $e')),
        );
    }
  }

  static Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
      );

  /// The member cards, numbered within their own kind — "Egg Inspection 1",
  /// "Egg Inspection 2", "Raw Processed Meat 1" …
  List<Widget> _numberedMemberCards(BuildContext context) {
    final seen = <String, int>{};
    final cards = <Widget>[];
    for (final member in members) {
      final n = (seen[member.kind] ?? 0) + 1;
      seen[member.kind] = n;
      cards.add(_memberCard(context, member, n));
    }
    return cards;
  }

  /// Whether this inspection raised a direction. Each commodity keeps its
  /// own directions table, and only the meat ones record which inspection
  /// they came from — the others are keyed on the record itself.
  Future<bool> _raisedDirection(VisitMember member) async {
    switch (member.kind) {
      case 'egg':
        return await eggs.directionForInspection(member.uuid) != null;
      case 'rawrmp':
        return await (database.select(database.rawRmpDirections)
                  ..where((t) => t.sourceInspectionUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
      case 'pmp':
        return await (database.select(database.pmpDirections)
                  ..where((t) => t.sourceInspectionUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
      default:
        return await (database.select(database.poultryDirections)
                  ..where((t) => t.clientUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
    }
  }

  Widget _memberCard(BuildContext context, VisitMember member, int number) {
    final state = _state(member);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => member.kind == 'egg'
                ? EggInspectionViewPage(
                    eggs: eggs,
                    uuid: member.uuid,
                    onEdit:
                        fromServer ? null : () => _editMember(context, member),
                  )
                : CommodityInspectionViewPage(
                    database: database,
                    kind: member.kind,
                    uuid: member.uuid,
                    title: '${member.label} $number',
                    uploaded: member.isUploaded,
                    status: member.status,
                    onEdit:
                        fromServer ? null : () => _editMember(context, member),
                  ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: state.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  switch (member.kind) {
                    'egg' => Icons.egg_outlined,
                    'poultry' => Icons.food_bank_outlined,
                    'quid' => Icons.water_drop_outlined,
                    'rawrmp' => Icons.kebab_dining_outlined,
                    'pmp' => Icons.lunch_dining_outlined,
                    _ => Icons.checklist_outlined,
                  },
                  size: 22,
                  color: state.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${member.label} $number',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      member.inspectedAt == null
                          ? state.detail
                          : '${_dmy(member.inspectedAt!)}  ·  '
                              '${state.detail}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    // A record being sent right now says so rather than
                    // sitting on "SUBMITTED" as though nothing is happening.
                    ValueListenableBuilder<bool>(
                      valueListenable: AutoSync.instance.isSyncing,
                      builder: (context, syncing, _) =>
                          syncing && state.chip == 'SUBMITTED'
                              ? _pill('UPLOADING…', AppColors.brandTeal)
                              : _pill(state.chip, state.color),
                    ),
                    // An inspection that raised a direction says so here,
                    // so a group can be read for what was served without
                    // opening every record in it.
                    FutureBuilder<bool>(
                      future: _raisedDirection(member),
                      builder: (context, snap) => snap.data == true
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child:
                                  _pill('REJECTION SERVED', AppColors.brandRed),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // And a seizure, when the consignment was seized.
                    FutureBuilder<Seizure?>(
                      future: SeizureRepository(database: database)
                          .forRecord(member.uuid),
                      builder: (context, snap) => snap.data != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child:
                                  _pill('SEIZURE SERVED', AppColors.brandRed),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  static ({String chip, String detail, Color color}) _state(
      VisitMember member) {
    if (member.status == 'draft') {
      return (
        chip: 'DRAFT',
        detail: 'Still in progress',
        color: AppColors.muted,
      );
    }
    if (member.status == 'ready') {
      return (
        chip: 'AWAITING SIGN-OFF',
        detail: 'Captured — submits at the final sign-off',
        color: AppColors.noticeForeground,
      );
    }
    return member.isUploaded
        ? (
            chip: 'UPLOADED',
            detail: 'Submitted & uploaded to the server',
            color: AppColors.brandTeal,
          )
        : (
            chip: 'SUBMITTED',
            detail: 'Waiting to upload',
            color: AppColors.brandTeal,
          );
  }
}

/// A captured egg inspection, read-only: the particulars, the sample
/// results, the deviations found, the photographs and the signatures.
class EggInspectionViewPage extends StatefulWidget {
  const EggInspectionViewPage({
    super.key,
    required this.eggs,
    required this.uuid,
    this.onEdit,
  });

  final EggsRepository eggs;
  final String uuid;

  /// Reopens this record for correction. Absent where a record is only read.
  final Future<bool> Function()? onEdit;

  @override
  State<EggInspectionViewPage> createState() => _EggInspectionViewPageState();
}

class _EggInspectionViewPageState extends State<EggInspectionViewPage> {
  EggInspection? _inspection;
  List<EggSample> _samples = const [];
  List<EggPhoto> _photos = const [];
  List<EggSignature> _signatures = const [];
  Map<int, String> _sizeNames = const {};
  Map<int, String> _gradeNames = const {};
  Map<int, String> _deviationNames = const {};

  /// The direction this inspection raised, if it raised one, and the
  /// remarks that were served with it.
  EggDirection? _direction;
  List<String> _directionRemarks = const [];

  /// The seizure served off this inspection, when there was one.
  Seizure? _seizure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// True while the form is opening, so it cannot be opened twice.
  bool _editing = false;

  Future<void> _edit() async {
    final open = widget.onEdit;
    if (open == null || _editing) return;
    setState(() => _editing = true);
    try {
      final saved = await open();
      if (!mounted) return;
      await _load();
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Correction saved. Run Server Sync to send it to '
              'the office.'),
          duration: Duration(seconds: 6),
        ));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _load() async {
    final eggs = widget.eggs;
    final inspection = await eggs.inspectionByUuid(widget.uuid);
    final samples = await eggs.samplesFor(widget.uuid);
    final photos = await eggs.photosFor(widget.uuid);
    final signatures = await eggs.signaturesFor(widget.uuid);
    final sizes = await eggs.sizeBands();
    final grades = await eggs.gradeRefs();
    final categories = await eggs.deviationCategories();
    final deviations = await eggs.deviationRefs();
    final categoryNames = {for (final c in categories) c.id: c.name};
    final direction = await eggs.directionForInspection(widget.uuid);
    final directionRemarks = direction == null
        ? const <String>[]
        : await eggs.directionRemarkNames(direction.remarkIds);
    final seizure =
        await SeizureRepository(database: eggs.database)
            .currentForRecord(widget.uuid);
    if (!mounted) return;
    setState(() {
      _seizure = seizure;
      _inspection = inspection;
      _samples = samples;
      _photos = photos;
      _signatures = signatures;
      _sizeNames = {for (final s in sizes) s.id: s.name};
      _gradeNames = {for (final g in grades) g.id: g.name};
      _deviationNames = {
        for (final d in deviations)
          d.id: '${categoryNames[d.categoryId] ?? ''} - ${d.description}',
      };
      _direction = direction;
      _directionRemarks = directionRemarks;
      _loading = false;
    });
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static const _photoKindLabels = {
    'label': 'Label/Container photo',
    'numbering': 'Egg numbering photo',
    'egg': 'Egg photo (rejection)',
    'deviation': 'Label photo (rejection)',
  };

  @override
  Widget build(BuildContext context) {
    final i = _inspection;
    return Scaffold(
      appBar: AppBar(title: const Text('Egg Inspection Details')),
      body: ContentWidth(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : i == null
                  ? const Center(child: Text('This record no longer exists.'))
                  : _body(i)),
    );
  }

  Widget _body(EggInspection i) {
    final weighed = _samples.where((s) => (s.massG ?? 0) > 0).length;
    final haugh = _samples.where((s) => (s.haughUnit ?? 0) > 0).length;

    final deviationCounts = <int, int>{};
    for (final s in _samples) {
      for (final part in s.deviationIds.split(',')) {
        final id = int.tryParse(part.trim());
        if (id != null) {
          deviationCounts[id] = (deviationCounts[id] ?? 0) + 1;
        }
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (widget.onEdit != null) ...[
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _editing ? null : _edit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(_editing ? 'OPENING…' : 'EDIT THIS INSPECTION'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            i.isUploaded
                ? 'The office has this record. A correction is sent to them '
                    'again on the next Server Sync, and replaces what they '
                    'hold — it does not make a second inspection.'
                : 'This record has not been sent yet; a correction simply '
                    'goes with it.',
            style:
                TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
        ],
        _section('FACILITY'),
        _row('Facility', i.facilityName),
        _row('Address', i.facilityAddress),
        _row('Client', i.clientName),
        _row('Inspected', _dmy(i.inspectedAt)),
        _row(
          'Status',
          i.status == 'completed'
              ? (i.isUploaded ? 'Submitted & uploaded' : 'Submitted')
              : i.status == 'ready'
                  ? 'Captured — awaiting sign-off'
                  : 'Draft',
        ),
        _section('PRODUCT'),
        _row('Producer/Supplier', i.producerSupplier),
        _row('Batch number', i.batchNumber),
        _row('Best before', i.bestBefore == null ? '' : _dmy(i.bestBefore!)),
        _row('Sold as size', _sizeNames[i.declaredSizeId] ?? ''),
        _row('Sold as grade', _gradeNames[i.declaredGradeId] ?? ''),
        _section('SAMPLE RESULTS'),
        _row('Eggs weighed', '$weighed'),
        _row('Haugh readings', '$haugh'),
        _row(
          'Determined grade',
          (_gradeNames[i.determinedGradeId] ?? '') +
              (i.gradeOverridden ? ' (overridden)' : ''),
        ),
        if (i.overrideReason.isNotEmpty)
          _row('Override reason', i.overrideReason),
        _section('DEVIATIONS FOUND'),
        if (deviationCounts.isEmpty)
          Text(
            'No deviations recorded.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        for (final entry in deviationCounts.entries)
          _row('${entry.value} egg(s)',
              _deviationNames[entry.key] ?? 'Deviation ${entry.key}'),
        ..._directionSection(),
        ..._seizureSection(),
        _section('PHOTOS'),
        if (_photos.isEmpty)
          Text(
            'No photographs on this record.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        for (final photo in _photos) _photoCard(photo),
        _section('SIGNATURES'),
        if (_signatures.isEmpty)
          Text(
            'No signatures on this record.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        for (final signature in _signatures) _signatureCard(signature),
      ],
    );
  }

  /// A titled list that uses the whole width: a heading, then one line per
  /// entry.
  Widget _list(String title, List<String> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('•',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        )),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The seizure served off this inspection, as the Annexure E sheet
  /// carries it.
  List<Widget> _seizureSection() {
    final s = _seizure;
    if (s == null) return const [];
    return [
      _section('SEIZURE SERVED'),
      for (final (label, value) in SeizureRepository.rowsFor(s))
        if (value.trim().isNotEmpty) _row(label, value),
      if (widget.onEdit != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _editSeizure,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('EDIT SEIZURE PARTICULARS'),
            ),
          ),
        ),
    ];
  }

  /// Corrects the seizure's particulars and reads the record back.
  Future<void> _editSeizure() async {
    final database = widget.eggs.database;
    final seizure =
        await SeizureRepository(database: database).forRecord(widget.uuid);
    if (seizure == null || !mounted) return;
    final saved = await editSeizureParticulars(context,
        database: database, seizure: seizure);
    if (!saved || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Seizure updated. The corrected sheet goes to the '
            'office on the next sync.'),
      ));
  }

  /// What was served on the client off the back of this inspection.
  List<Widget> _directionSection() {
    final d = _direction;
    if (d == null) return const [];
    final parts = [
      if (d.labellingPart) 'Labelling',
      if (d.qualityPart) 'Quality',
    ];
    return [
      _section('REJECTION SERVED'),
      _row('Issued', _dmy(d.issuedAt)),
      _row('Rejection number', d.directionNumber),
      _row(
          'Status', d.status == 'completed' ? 'Issued to the client' : 'Draft'),
      _row('Parts', parts.join(' and ')),
      if (d.labelCorrectBy != null)
        _row('Labelling correct by', _dmy(d.labelCorrectBy!)),
      if (d.qualityCorrectBy != null)
        _row('Quality correct by', _dmy(d.qualityCorrectBy!)),
      if (d.quantityRemoved != null)
        _row('Quantity removed', '${d.quantityRemoved}'),
      // A list runs the width of the page rather than wrapping in the
      // narrow value column beside a label.
      _list('Remarks served', _directionRemarks),
      if (d.additionalRemarks.trim().isNotEmpty)
        _row('Additional remarks', d.additionalRemarks.trim()),
    ];
  }

  Widget _photoCard(EggPhoto photo) {
    final file = File(photo.filePath);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _photoKindLabels[photo.kind] ?? photo.kind,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: file.existsSync()
                ? Image.file(file, height: 180, fit: BoxFit.cover)
                : Container(
                    height: 80,
                    color: AppColors.surfaceAlt,
                    alignment: Alignment.center,
                    child: Text(
                      'Photo file missing',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _signatureCard(EggSignature signature) {
    final file = File(signature.filePath);
    final role = signature.role == 'manager'
        ? 'Store / Client'
        : signature.role == 'inspector'
            ? 'Inspector'
            : signature.role;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            signature.signedName.isEmpty
                ? role
                : '$role — ${signature.signedName}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (file.existsSync())
            Container(
              // Full width, as on the commodity pages: a signature is
              // something to read, not a thumbnail.
              width: double.infinity,
              height: 150,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(file, fit: BoxFit.contain),
              ),
            )
          else
            Text(
              'Signature image missing',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// The visit's own documents, offered as whole downloads rather than one
/// checklist at a time.
///
/// An inspector at the counter is asked for "the compliance documents", so
/// every compliance checklist in the group — each commodity's — comes down
/// as a single file. The Compositional Checklist stays on its own: it is a
/// different form, filed separately by the office.
class _VisitDocumentDownloads extends StatefulWidget {
  const _VisitDocumentDownloads({
    required this.database,
    required this.visit,
    required this.members,
  });

  final LocalDatabase database;
  final StoreVisit visit;
  final List<VisitMember> members;

  @override
  State<_VisitDocumentDownloads> createState() =>
      _VisitDocumentDownloadsState();
}

class _VisitDocumentDownloadsState extends State<_VisitDocumentDownloads> {
  List<RecordDocument> _composition = const [];
  List<RecordDocument> _compliance = const [];

  /// The rejections served in this visit, offered on their own like the RFI
  /// (Ethan, 2026-09-24), not folded into the compliance documents.
  List<RecordDocument> _rejections = const [];

  /// The seizures served in this visit — FSA-SOP-APS-001 Annexure E, on
  /// their own like the rejections.
  List<RecordDocument> _seizures = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final composition = <RecordDocument>[];
    final compliance = <RecordDocument>[];
    final rejections = <RecordDocument>[];
    final seizures = <RecordDocument>[];
    for (final member in widget.members) {
      for (final document in await documentsForRecord(
          widget.database, member.kind, member.uuid)) {
        // The composition form is its own document; everything else is a
        // compliance checklist as far as the office is concerned.
        if (document.title.startsWith('Compositional')) {
          composition.add(document);
        } else if (document.title == 'Rejection') {
          rejections.add(document);
        } else if (document.title == 'Seizure') {
          seizures.add(document);
        } else {
          compliance.add(document);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _composition = composition;
      _compliance = compliance;
      _rejections = rejections;
      _seizures = seizures;
    });
  }

  String _named(String slug) => Downloads.documentName(
        widget.visit.facilityName,
        slug,
        widget.visit.completedAt ?? widget.visit.startedAt,
      );

  /// Builds every document in [documents] and shows them, or saves them, as
  /// one file.
  Future<void> _open(List<RecordDocument> documents, String slug, String title,
      {required bool download}) async {
    if (_busy || documents.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final files = <File>[];
      for (final document in documents) {
        final file = await document.build();
        if (file != null) files.add(file);
      }
      if (files.isEmpty) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
              const SnackBar(content: Text('There is nothing to show yet.')));
        return;
      }
      // One document needs no merging, and keeps its own text rather than a
      // rendering of it.
      final bytes = files.length == 1
          ? await files.first.readAsBytes()
          : await mergeDocuments(files);
      final name = _named(slug);
      if (!download) {
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ContentWidth(
              child: PdfPreview(
                build: (_) => bytes,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                pdfFileName: name,
              ),
            ),
          ),
        ));
        return;
      }
      final saved = await Downloads.save(name, bytes);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Saved to ${saved.where}'),
          duration: const Duration(seconds: 6),
          action: saved.uri.isEmpty
              ? null
              : SnackBarAction(
                  label: 'OPEN', onPressed: () => Downloads.open(saved)),
        ));
    } on Object catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text('$title could not be built. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A view/download pair on one row, the same shape as the RFI's.
  Widget _pair({
    required String label,
    required String title,
    required String slug,
    required List<RecordDocument> documents,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _open(documents, slug, title, download: false),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('VIEW $label',
                        maxLines: 1, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _open(documents, slug, title, download: true),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('DOWNLOAD $label',
                        maxLines: 1, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_composition.isNotEmpty)
          _pair(
            label: 'COMPOSITION',
            title: 'Compositional Checklist',
            slug: 'Compositional-Checklist',
            documents: _composition,
          ),
        if (_compliance.isNotEmpty)
          _pair(
            label: _compliance.length == 1
                ? 'COMPLIANCE DOCUMENT'
                : 'COMPLIANCE DOCUMENTS',
            title: 'Compliance Documents',
            slug: 'Compliance-Documents',
            documents: _compliance,
          ),
        if (_rejections.isNotEmpty)
          _pair(
            label: _rejections.length == 1 ? 'REJECTION' : 'REJECTIONS',
            title: _rejections.length == 1 ? 'Rejection' : 'Rejections',
            slug: 'Rejection',
            documents: _rejections,
          ),
        if (_seizures.isNotEmpty)
          _pair(
            label: _seizures.length == 1 ? 'SEIZURE' : 'SEIZURES',
            title: _seizures.length == 1 ? 'Seizure' : 'Seizures',
            slug: 'Seizure',
            documents: _seizures,
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// The inspector's approval of a visit that has reached the server
/// (Ethan, 2026-09-24): look over the documents above, press Approve, and
/// the approval goes to the server, where the visit shows as approved.
class _VisitApproval extends StatefulWidget {
  const _VisitApproval({
    required this.visit,
    required this.database,
    required this.eggs,
  });

  final StoreVisit visit;
  final LocalDatabase database;
  final EggsRepository eggs;

  @override
  State<_VisitApproval> createState() => _VisitApprovalState();
}

class _VisitApprovalState extends State<_VisitApproval> {
  late StoreVisit _visit = widget.visit;
  bool _busy = false;

  static const _green = Color(0xFF2E7D32);

  late final _repository =
      VisitRepository(widget.database, baseUrl: widget.eggs.baseUrl);

  Future<void> _reload() async {
    final row = await _repository.byUuid(_visit.uuid);
    if (row != null && mounted) setState(() => _visit = row);
  }

  Future<void> _approve() => _decide(approve: true);

  Future<void> _unapprove() => _decide(approve: false);

  /// Records the answer on the device, then tells the server if the visit
  /// is already there; otherwise it goes up with the next sync. Taking an
  /// approval back works the same way (Ethan, 2026-09-24).
  Future<void> _decide({required bool approve}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            approve ? 'Approve this inspection?' : 'Take the approval back?'),
        content: Text(
          approve
              ? 'Approve it once you have looked over its documents. The '
                  'approval is sent to the server, where the inspection '
                  'shows as approved.'
              : 'The inspection goes back to not approved, on this device '
                  'and on the server.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: approve
                ? null
                : FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve' : 'Unapprove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    if (approve) {
      await _repository.approve(_visit.uuid);
    } else {
      await _repository.unapprove(_visit.uuid);
    }
    await _reload();
    var sent = false;
    if (_visit.isUploaded) {
      try {
        final token = await widget.eggs.storedToken();
        if (token != null) {
          sent = await _repository.sendApproval(_visit, token: token);
        }
      } on Object {
        sent = false;
      }
    }
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    final word = approve ? 'Approved' : 'Approval taken back';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(sent
            ? '$word. The server has it.'
            : '$word on this device. It goes to the server with the next '
                'sync.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final approvedAt = _visit.approvedAt;
    if (approvedAt != null) {
      final d = approvedAt.toLocal();
      final when = '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.08),
          border: Border.all(color: _green.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: _green, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('APPROVED',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _green,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(
                    _visit.approvalSent
                        ? 'On $when — the server has it.'
                        : 'On $when — goes to the server with the next sync.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _unapprove,
              child: const Text('UNAPPROVE'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: _busy ? null : _approve,
            icon: const Icon(Icons.check, size: 20),
            label: Text(_busy ? 'APPROVING…' : 'APPROVE'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _visit.isUploaded
              ? 'Look over the documents above, then approve the inspection.'
              : 'Look over the documents above, then approve the inspection. '
                  'It goes to the server with the next sync.',
          style:
              TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
        ),
      ],
    );
  }
}
