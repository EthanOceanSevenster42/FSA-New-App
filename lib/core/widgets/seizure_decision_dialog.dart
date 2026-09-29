import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What the inspector decided when the findings turned out to require a
/// seizure.
enum SeizureDecision {
  /// Seize the consignment under section 8 of the APS Act.
  seize('seize'),

  /// Leave it for now and carry on inspecting.
  inspect('inspect');

  const SeizureDecision(this.stored);

  /// How the answer is written to the record.
  final String stored;

  static SeizureDecision? of(String stored) {
    for (final value in SeizureDecision.values) {
      if (value.stored == stored) return value;
    }
    return null;
  }
}

/// Puts the seizure question to the inspector, once, on the premises.
///
/// FSA-SOP-APS-001 makes a seizure its own outcome rather than a severer
/// rejection: an omitted product name, grade designation or batch code is
/// seized under section 8 rather than given a rectification period, and the
/// assignee needs no prior authorisation to do it. Nothing on the handset
/// asked the question — the findings simply carried on into a rejection, and
/// the decision the SOP puts to the inspector was never put.
///
/// It is a question, not an instruction: an inspector may have reason to
/// finish the round and come back to it, so the other answer carries on with
/// the inspection rather than cancelling anything.
///
/// Returns null if it is dismissed without an answer.
Future<SeizureDecision?> askAboutSeizure(
  BuildContext context, {
  required String reason,
}) =>
    showDialog<SeizureDecision>(
      context: context,
      // The answer is recorded against the record, so it is made rather than
      // tapped past.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.gavel, size: 32, color: AppColors.brandRed),
        title: const Text('This consignment must be seized'),
        content: Text(
          '$reason\n\n'
          'A seizure is served under section 8 of the APS Act and needs no '
          'authorisation beforehand. Proceed with it now, or carry on with '
          'the inspection and decide before you sign off.',
          style: const TextStyle(height: 1.4),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(SeizureDecision.inspect),
            child: const Text('Carry on inspecting'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            onPressed: () =>
                Navigator.of(dialogContext).pop(SeizureDecision.seize),
            child: const Text('Proceed with seizure'),
          ),
        ],
      ),
    );

/// What the seizure sheet needs that only the inspector on the premises
/// can supply: what exactly was seized, how much, and who took receipt.
class SeizureParticulars {
  const SeizureParticulars({
    required this.productName,
    required this.productClass,
    required this.quantity,
    required this.remarks,
    required this.receiverName,
    required this.receiverIdNumber,
    required this.receiverDesignation,
  });

  final String productName;
  final String productClass;
  final String quantity;
  final String remarks;
  final String receiverName;
  final String receiverIdNumber;
  final String receiverDesignation;
}

/// Asks for the seizure's particulars once "Proceed with seizure" has been
/// chosen, prefilled with what the form already knows.
///
/// The quantity is the one answer the sheet cannot do without — "5 packs
/// (2.106 kg)" is what the office and the client both hold the seizure to —
/// so it is required; the rest may be filled in from the record.
///
/// Returns null only if the route is torn down under the dialog.
Future<SeizureParticulars?> askSeizureParticulars(
  BuildContext context, {
  required SeizureParticulars initial,
  bool editing = false,
}) =>
    showDialog<SeizureParticulars>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _SeizureParticularsDialog(initial: initial, editing: editing),
    );

class _SeizureParticularsDialog extends StatefulWidget {
  const _SeizureParticularsDialog({required this.initial, this.editing = false});

  final SeizureParticulars initial;

  /// Correcting a seizure already recorded: it can be left as it was.
  final bool editing;

  @override
  State<_SeizureParticularsDialog> createState() =>
      _SeizureParticularsDialogState();
}

class _SeizureParticularsDialogState extends State<_SeizureParticularsDialog> {
  late final _product = TextEditingController(text: widget.initial.productName);
  late final _productClass =
      TextEditingController(text: widget.initial.productClass);
  late final _quantity = TextEditingController(text: widget.initial.quantity);
  late final _remarks = TextEditingController(text: widget.initial.remarks);
  late final _receiver =
      TextEditingController(text: widget.initial.receiverName);
  late final _receiverId =
      TextEditingController(text: widget.initial.receiverIdNumber);
  late final _receiverDesignation =
      TextEditingController(text: widget.initial.receiverDesignation);
  String? _quantityError;

  @override
  void dispose() {
    for (final c in [
      _product,
      _productClass,
      _quantity,
      _remarks,
      _receiver,
      _receiverId,
      _receiverDesignation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _record() {
    if (_quantity.text.trim().isEmpty) {
      setState(() => _quantityError =
          'Say how much is seized — packs, kilograms or units.');
      return;
    }
    Navigator.of(context).pop(SeizureParticulars(
      productName: _product.text,
      productClass: _productClass.text,
      quantity: _quantity.text,
      remarks: _remarks.text,
      receiverName: _receiver.text,
      receiverIdNumber: _receiverId.text,
      receiverDesignation: _receiverDesignation.text,
    ));
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required String key,
    String? hint,
    String? error,
    int lines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: Key(key),
          controller: controller,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: error,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.editing ? 'Edit seizure particulars' : 'Seizure particulars'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'These go onto the seizure document (FSA-SOP-APS-001 '
                    'Annexure E) served on the client.',
                    style: TextStyle(height: 1.4),
                  ),
                ),
                _field(_product, 'Product name', key: 'seizure-product'),
                _field(_productClass, 'Product class',
                    key: 'seizure-class', hint: 'e.g. Boerewors, Grade A'),
                _field(_quantity, 'Quantity seized',
                    key: 'seizure-quantity',
                    hint: 'e.g. 5 packs (2.106 kg)',
                    error: _quantityError),
                _field(_remarks, 'Remarks / comments',
                    key: 'seizure-remarks', lines: 2),
                _field(_receiver, 'Received by (name)',
                    key: 'seizure-receiver'),
                _field(_receiverId, 'Receiver ID number',
                    key: 'seizure-receiver-id'),
                _field(_receiverDesignation, 'Receiver designation',
                    key: 'seizure-receiver-designation',
                    hint: 'e.g. Butchery Manager'),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.editing)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            onPressed: _record,
            child: Text(widget.editing ? 'Save' : 'Record seizure'),
          ),
        ],
      );
}
