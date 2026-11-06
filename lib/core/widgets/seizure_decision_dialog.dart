import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'compliance_slider.dart';

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
/// Where the annexure reads "Immediate seizure / rectify immediately" — egg
/// size and grade standards, for one — [orRectifyNow] puts that choice
/// instead: seize, or have it put right before the inspector leaves. The
/// other answer is still [SeizureDecision.inspect]; the rejection it leads
/// to carries no period.
///
/// Returns null if it is dismissed without an answer.
Future<SeizureDecision?> askAboutSeizure(
  BuildContext context, {
  required String reason,
  bool orRectifyNow = false,
}) =>
    showDialog<SeizureDecision>(
      context: context,
      // The answer is recorded against the record, so it is made rather than
      // tapped past.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.gavel, size: 32, color: AppColors.brandRed),
        title: Text(orRectifyNow
            ? 'Seize, or have it put right now'
            : 'This consignment must be seized'),
        content: Text(
          orRectifyNow
              ? '$reason\n\n'
                  'FSA-SOP-APS-001 gives no rectification period for this: '
                  'the consignment is seized under section 8 of the APS Act, '
                  'which needs no authorisation beforehand, or it is put '
                  'right immediately, before you leave the premises.'
              : '$reason\n\n'
                  'A seizure is served under section 8 of the APS Act and '
                  'needs no authorisation beforehand. Proceed with it now, or '
                  'carry on with the inspection and decide before you sign '
                  'off.',
          style: const TextStyle(height: 1.4),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(SeizureDecision.inspect),
            child: Text(
                orRectifyNow ? 'Rectify immediately' : 'Carry on inspecting'),
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
                _field(_remarks, 'Remarks/comments',
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

/// Said as a seized inspection closes (Ethan, 2026-09-30): the product is
/// taken, so nothing more is asked of the inspection but its photographs.
void announceSeizureDone(BuildContext context) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Seizure recorded — this inspection is done.'),
      ));

/// What a seized inspection still needs before it closes: [photos], as
/// "the 2 label photographs — 1 of 2 taken".
String seizurePhotosOwed(String photos) =>
    'Seizure recorded. Take $photos to finish the inspection.';

/// How much was taken, asked the moment the seizure is raised.
///
/// This is the one particular that stops being knowable once the inspector
/// leaves: it is a count off the shelf or the cold room. Everything else on
/// the sheet can be filled from the inspection at the end, but the quantity
/// cannot, and the client signs the Acknowledgement of receipt on the same
/// page — so it has to be on it before they sign. Raw, processed meat and
/// poultry capture it nowhere else, and every seizure sheet the Agency has
/// issued went out with the column empty (Cinga, 2026-10-26).
///
/// Returns the quantity, or null if the inspector backed out.
Future<String?> askSeizedQuantity(
  BuildContext context, {
  required String productName,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SeizedQuantityDialog(productName: productName),
    );

class _SeizedQuantityDialog extends StatefulWidget {
  const _SeizedQuantityDialog({required this.productName});

  final String productName;

  @override
  State<_SeizedQuantityDialog> createState() => _SeizedQuantityDialogState();
}



class _SeizedQuantityDialogState extends State<_SeizedQuantityDialog> {
  final _amount = TextEditingController();

  /// Counted by the unit, or weighed. A consignment comes off a shelf in
  /// packs or out of a cold room on a scale, so the inspector says which
  /// and gives one number.
  bool _byCount = true;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// How the amount reads on the sheet.
  static String compose({required String amount, required bool byCount}) {
    final a = amount.trim();
    if (a.isEmpty) return '';
    if (!byCount) return '$a kg';
    return '$a ${a == '1' ? 'product' : 'products'}';
  }

  void _done() {
    final value = compose(amount: _amount.text, byCount: _byCount);
    if (value.isEmpty) {
      setState(() => _error = _byCount
          ? 'How many products were removed?'
          : 'What weight was removed, in kg?');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('How much was seized?'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Count what is being removed now, before the client '
                    'signs for it.'
                    '${widget.productName.trim().isEmpty ? '' : '\n\n${widget.productName.trim()}'}',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Measured by',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    TwoWaySlider(
                      key: const Key('seizure-measure'),
                      leftLabel: 'PRODUCTS',
                      rightLabel: 'WEIGHT (KG)',
                      leftOn: _byCount,
                      // Neither is a finding, so neither is red.
                      rightColor: AppColors.brandPrimary,
                      onChanged: (byCount) => setState(() {
                        _byCount = byCount;
                        _error = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('seizure-amount'),
                  controller: _amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _done(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    labelText: _byCount
                        ? 'Number of products removed'
                        : 'Weight removed (kg)',
                    hintText: _byCount ? 'e.g. 12' : 'e.g. 2.106',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            onPressed: _done,
            child: const Text('Record seizure'),
          ),
        ],
      );
}
