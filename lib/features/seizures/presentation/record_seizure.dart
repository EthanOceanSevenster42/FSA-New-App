import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
import '../../visits/data/visit_repository.dart';
import '../data/seizure_repository.dart';

/// What a form already knows about the consignment when the inspector
/// chooses to seize it: the client's particulars from the header, the
/// product from the record, the deviation in the annexure's words.
class SeizureDraft {
  const SeizureDraft({
    required this.recordUuid,
    required this.recordKind,
    required this.inspectorUsername,
    required this.natureOfDeviation,
    required this.regulation,
    this.visitUuid = '',
    this.clientName = '',
    this.clientAddress = '',
    this.clientTelephone = '',
    this.clientEmail = '',
    this.inspectionPoint = '',
    this.productName = '',
    this.productClass = '',
    this.receiverName = '',
  });

  final String recordUuid;
  final String recordKind;
  final String inspectorUsername;
  final String natureOfDeviation;
  final String regulation;
  final String visitUuid;
  final String clientName;
  final String clientAddress;
  final String clientTelephone;
  final String clientEmail;
  final String inspectionPoint;
  final String productName;
  final String productClass;
  final String receiverName;
}

/// Reopens the particulars of a seizure already recorded, saves any change,
/// and marks its visit for sending again so the office receives the
/// corrected sheet. Returns true when something was saved.
Future<bool> editSeizureParticulars(
  BuildContext context, {
  required LocalDatabase database,
  required Seizure seizure,
}) async {
  // Opened on what the sheet prints now — filled from the inspection where
  // the inspector has not given it — rather than on blanks.
  final shown =
      await SeizureRepository(database: database).current(seizure);
  if (!context.mounted) return false;
  final answer = await askSeizureParticulars(
    context,
    editing: true,
    initial: SeizureParticulars(
      productName: shown.productName,
      productClass: shown.productClass,
      quantity: shown.quantity,
      remarks: shown.remarks,
      receiverName: shown.receiverName,
      receiverIdNumber: shown.receiverIdNumber,
      receiverDesignation: shown.receiverDesignation,
    ),
  );
  if (answer == null) return false;
  await SeizureRepository(database: database).updateParticulars(
    seizure,
    productName: answer.productName,
    productClass: answer.productClass,
    quantity: answer.quantity,
    remarks: answer.remarks,
    receiverName: answer.receiverName,
    receiverIdNumber: answer.receiverIdNumber,
    receiverDesignation: answer.receiverDesignation,
  );
  if (seizure.visitUuid.isNotEmpty) {
    await VisitRepository(database).markChanged(seizure.visitUuid);
  }
  return true;
}

/// Writes the seizure the moment "Proceed with seizure" is chosen.
///
/// FSA-SOP-APS-001 wants every immediate seizure on the Annexure E sheet.
/// Its particulars used to be asked for there and then, in a form that
/// stopped the inspection halfway (Ethan, 2026-09-29). The sheet now fills
/// itself from the inspection as it stands at the end — the receiver from
/// the person who signs — see [SeizureRepository.current]. Anything still
/// missing is added with "Edit seizure particulars" in Inspection
/// Management.
///
/// The quantity is the exception, and is asked here: it is counted off the
/// shelf and stops being knowable once the inspector leaves, and the client
/// signs the Acknowledgement of receipt on the same page, so it must be on
/// the page before they sign. Only eggs and QUID record one anywhere else,
/// which is why every seizure sheet the Agency has issued had the column
/// empty (Cinga, 2026-10-26).
///
/// Returns true when a seizure was recorded.
Future<bool> recordSeizure(
  BuildContext context, {
  required LocalDatabase database,
  required SeizureDraft draft,
}) async {
  final quantity =
      await askSeizedQuantity(context, productName: draft.productName);
  // Backed out of the question: nothing is seized, so the inspection is
  // left as it was rather than a sheet raised with no amount on it.
  if (quantity == null) return false;
  final now = DateTime.now();
  await SeizureRepository(database: database).record(SeizuresCompanion.insert(
    clientUuid: const Uuid().v4(),
    recordUuid: draft.recordUuid,
    recordKind: draft.recordKind,
    visitUuid: Value(draft.visitUuid),
    inspectorUsername: Value(draft.inspectorUsername),
    issuedAt: now,
    updatedAt: now,
    clientName: Value(draft.clientName.trim()),
    clientAddress: Value(draft.clientAddress.trim()),
    clientTelephone: Value(draft.clientTelephone.trim()),
    clientEmail: Value(draft.clientEmail.trim()),
    inspectionPoint: Value(draft.inspectionPoint.trim()),
    productName: Value(draft.productName.trim()),
    productClass: Value(draft.productClass.trim()),
    regulation: Value(draft.regulation),
    natureOfDeviation: Value(draft.natureOfDeviation),
    quantity: Value(quantity),
    // The receiver is left for the end of the inspection to fill: it is the
    // person who signs, and who that is is not known yet.
  ));
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Seizure recorded. The seizure document is filled in '
            'from this inspection when it is finished.'),
      ));
  }
  return true;
}
