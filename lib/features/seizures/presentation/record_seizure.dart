import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/widgets/seizure_decision_dialog.dart';
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
