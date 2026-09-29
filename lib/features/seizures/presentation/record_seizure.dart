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
  final answer = await askSeizureParticulars(
    context,
    editing: true,
    initial: SeizureParticulars(
      productName: seizure.productName,
      productClass: seizure.productClass,
      quantity: seizure.quantity,
      remarks: seizure.remarks,
      receiverName: seizure.receiverName,
      receiverIdNumber: seizure.receiverIdNumber,
      receiverDesignation: seizure.receiverDesignation,
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

/// Puts the seizure particulars to the inspector and writes the seizure.
///
/// Called the moment "Proceed with seizure" is chosen, on the premises:
/// FSA-SOP-APS-001 wants every immediate seizure on the Annexure E sheet,
/// and the sheet needs what only the inspector standing at the shelf can
/// give — how much was seized and who took receipt of it.
///
/// Returns true when a seizure was recorded.
Future<bool> recordSeizure(
  BuildContext context, {
  required LocalDatabase database,
  required SeizureDraft draft,
}) async {
  final particulars = await askSeizureParticulars(
    context,
    initial: SeizureParticulars(
      productName: draft.productName,
      productClass: draft.productClass,
      quantity: '',
      remarks: '',
      receiverName: draft.receiverName,
      receiverIdNumber: '',
      receiverDesignation: '',
    ),
  );
  if (particulars == null) return false;
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
    productName: Value(particulars.productName.trim()),
    productClass: Value(particulars.productClass.trim()),
    quantity: Value(particulars.quantity.trim()),
    regulation: Value(draft.regulation),
    natureOfDeviation: Value(draft.natureOfDeviation),
    remarks: Value(particulars.remarks.trim()),
    receiverName: Value(particulars.receiverName.trim()),
    receiverIdNumber: Value(particulars.receiverIdNumber.trim()),
    receiverDesignation: Value(particulars.receiverDesignation.trim()),
  ));
  return true;
}
