import 'dart:io';

import '../../../core/data/local_database.dart';
import '../../../core/platform/downloads.dart';
import '../../eggs/data/eggs_repository.dart';
import '../../pmp/data/pmp_repository.dart';
import '../../poultry/data/poultry_repository.dart';
import '../../rawrmp/data/rawrmp_repository.dart';
import '../../rawrmp/domain/composition_checklist.dart';
import '../../seizures/data/seizure_repository.dart';

/// One document an inspection produced: what it is called, what it is, the
/// name it takes when saved, and how to build it.
///
/// Built on demand rather than kept on disk — the record is the source, so a
/// document built now says what the record says now.
typedef RecordDocument = ({
  String title,
  String note,
  String downloadName,
  Future<File?> Function() build,
});

/// The documents one inspection produces, in the order the office files them.
///
/// The same builders the handset uses when it sends the inspection up, so
/// what an inspector reads on the handset is what the office receives. Each
/// is offered only once the section behind it is finished: an untouched
/// checklist has nothing to show.
Future<List<RecordDocument>> documentsForRecord(
  LocalDatabase database,
  String kind,
  String uuid,
) async {
  final documents = await _commodityDocuments(database, kind, uuid);
  // The seizure, when the consignment was seized: the same Annexure E
  // sheet whatever the commodity, so it is added here once rather than in
  // every case below.
  final seizures = SeizureRepository(database: database);
  final seizure = await seizures.forRecord(uuid);
  if (seizure == null) return documents;
  return [
    ...documents,
    (
      title: 'Seizure',
      note: 'FSA-SOP-APS-001 Annexure E — the seizure served on the client '
          'under section 8 of the Act: the product, the quantity and who '
          'took receipt of it.',
      downloadName: Downloads.documentName(
          seizure.clientName, 'Seizure', seizure.issuedAt),
      build: () => seizures.buildDocument(uuid),
    ),
  ];
}

Future<List<RecordDocument>> _commodityDocuments(
  LocalDatabase database,
  String kind,
  String uuid,
) async {
  switch (kind) {
    case 'rawrmp':
      final r = await (database.select(database.rawRmpInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();
      if (r == null) return const [];
      final composed = CompositionChecklist.isAnswered(
              CompositionChecklist.decode(r.compositionChecklistJson)) ||
          r.compositionComments.trim().isNotEmpty;
      final repository = RawRmpRepository(database: database, baseUrl: '');
      // A direction is raised by the save when the checklist leaves a
      // deviation standing, so the notice exists whenever that record does.
      final directed = await repository.directionForInspection(uuid) != null;
      String named(String slug) =>
          Downloads.documentName(r.facilityName, slug, r.inspectedAt);
      return [
        if (r.labelPackComplete)
          (
            title: 'Labelling Verification Checklist',
            note: 'SOP-APS-RAW-001 — the marking, scale, container and notice '
                'board requirements, as ticked on this inspection.',
            downloadName: named('Labelling-Verification-Checklist'),
            build: () => repository.buildLabellingChecklist(uuid),
          ),
        if (r.isSampled)
          (
            title: 'Sampling Checklist',
            note: 'SOP-APS-RAW-002 — the sheet that travels with the sample '
                'to the laboratory.',
            downloadName: named('Sampling-Checklist'),
            build: () => repository.buildSamplingChecklist(uuid),
          ),
        if (composed)
          (
            title: 'Compositional Checklist',
            note: 'SOP-APS-RAW-003 — the Regulation 5 compositional '
                'requirements checklist, filled in from this inspection.',
            downloadName: named('Compositional-Checklist'),
            build: () => repository.buildCompositionChecklist(uuid),
          ),
        if (directed)
          (
            title: 'Rejection',
            note: 'SOP-APS-001 — the notice served on the client, citing the '
                'deviations found and the date they must be corrected by.',
            downloadName: named('Rejection'),
            build: () => repository.buildDirection(uuid),
          ),
      ];
    case 'pmp':
      final r = await (database.select(database.pmpInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();
      if (r == null) return const [];
      final repository = PmpRepository(database: database, baseUrl: '');
      String named(String slug) =>
          Downloads.documentName(r.facilityName, slug, r.inspectedAt);
      return [
        if (r.labelPackComplete)
          (
            title: 'Labelling Verification Checklist',
            note: 'SOP-APS-PMP-001 — the marking, scale, container and notice '
                'board requirements, as ticked on this inspection.',
            downloadName: named('Labelling-Verification-Checklist'),
            build: () => repository.buildLabellingChecklist(uuid),
          ),
        if (r.isSampled)
          (
            title: 'Sampling Checklist',
            note: 'SOP-APS-PMP-002 — the sheet that travels with the sample '
                'to the laboratory.',
            downloadName: named('Sampling-Checklist'),
            build: () => repository.buildSamplingChecklist(uuid),
          ),
        if (await repository.directionForInspection(uuid) != null)
          (
            title: 'Rejection',
            note: 'SOP-APS-001 — the notice served on the client, citing the '
                'deviations found and the date they must be corrected by.',
            downloadName: named('Rejection'),
            build: () => repository.buildDirection(uuid),
          ),
      ];
    case 'poultry':
    case 'poultry_label':
      // One member can stand behind both records — the grading inspection
      // and the label one — so both sheets are offered for either.
      final repository = PoultryRepository(database: database, baseUrl: '');
      final grading = await (database.select(database.poultryInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();
      final label = await (database.select(database.poultryLabelInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();
      String named(String slug) => Downloads.documentName(
            grading?.facilityName ?? label?.facilityName ?? '',
            slug,
            grading?.inspectedAt ?? label?.inspectedAt ?? DateTime.now(),
          );
      // The poultry direction is keyed on the record it was raised off, so
      // it is found by the same uuid the checklists are.
      final directed = await (database.select(database.poultryDirections)
                ..where((t) => t.clientUuid.equals(uuid)))
              .getSingleOrNull() !=
          null;
      return [
        if (grading != null)
          (
            title: 'Poultry Grading Checklist',
            note: 'SOP-APS-PM-003 — the carcass and portion quality '
                'standards, as ticked on this inspection.',
            downloadName: named('Poultry-Grading-Checklist'),
            build: () => repository.buildGradingChecklist(uuid),
          ),
        if (label != null)
          (
            title: 'Poultry Labelling Checklist',
            note: 'SOP-APS-PM-002 — the marking, container and packing '
                'requirements, as ticked on this inspection.',
            downloadName: named('Poultry-Labelling-Checklist'),
            build: () => repository.buildPoultryLabellingChecklist(uuid),
          ),
        if (directed)
          (
            title: 'Rejection',
            note: 'SOP-APS-001 — the notice served on the client, citing the '
                'deviations found on this record.',
            downloadName: named('Rejection'),
            build: () => repository.buildDirection(uuid),
          ),
      ];
    case 'quid':
      final repository = PoultryRepository(database: database, baseUrl: '');
      final q = await (database.select(database.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();
      if (q == null) return const [];
      return [
        (
          title: 'QUID Determination Checklist',
          note: 'SOP-APS-PM-001 — the declared chilling method, what it '
              'permits, and the pick up the weighed carcasses actually show.',
          downloadName: Downloads.documentName(
              q.facilityName, 'Poultry-QUID-Checklist', q.inspectedAt),
          // Null until carcasses have been weighed, so an untouched
          // determination offers nothing.
          build: () => repository.buildQuidChecklist(uuid),
        ),
        (
          title: 'QUID Rejection',
          note: 'The rejection the determination ended in — the injector '
              'over its limit, the remarks served, the date to correct by '
              'and the batch removed. Null while there is none.',
          downloadName: Downloads.documentName(
              q.facilityName, 'Poultry-QUID-Rejection', q.inspectedAt),
          build: () => repository.buildQuidRejection(uuid),
        ),
      ];
    case 'egg':
      // Both egg sheets were already built and sent with the inspection, so
      // the office had them — but this list had no egg case at all, and an
      // inspector opening an egg record saw nothing where every other
      // commodity shows its documents.
      final repository = EggsRepository(database: database, baseUrl: '');
      final r = await repository.inspectionByUuid(uuid);
      if (r == null) return const [];
      final samples = await repository.samplesFor(uuid);
      final failed = r.failedRequirementIds
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toSet();
      // The same conditions the builders themselves apply, so a document is
      // only offered when there is one to build.
      final labelled =
          samples.isNotEmpty || failed.isNotEmpty || r.outerLabellingAvailable;
      String named(String slug) =>
          Downloads.documentName(r.facilityName, slug, r.inspectedAt);
      return [
        if (labelled)
          (
            title: 'Labelling Checklist',
            note: 'The marking, outer container and packing requirements, as '
                'worked on this inspection.',
            downloadName: named('Labelling-Checklist'),
            build: () => repository.buildLabellingChecklist(uuid),
          ),
        if (samples.isNotEmpty)
          (
            title: 'Weighing Checklist',
            note: 'The egg-by-egg weighing and its size and grade findings.',
            downloadName: named('Weighing-Checklist'),
            build: () => repository.buildWeighingChecklist(uuid),
          ),
        if (await repository.directionForInspection(uuid) != null)
          (
            title: 'Rejection',
            note: 'SOP-APS-001 — the notice served on the client: the '
                'deviations found, and the date each part must be put right '
                'by.',
            downloadName: named('Rejection'),
            build: () => repository.buildDirection(uuid),
          ),
      ];
    default:
      return const [];
  }
}
