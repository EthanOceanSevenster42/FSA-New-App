import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../domain/poultry_rules.dart';
import 'poultry_form_widgets.dart';

/// Setup QUID Checklist.
///
/// QUID is the declared quantity of added water in injected poultry. This
/// screen records what is being sampled and how; the weighing happens later on
/// "Continue with QUID Checklist", against the same record.
///
/// Deliberately short. The original's set-up screen is 17 fields, and padding
/// it out with the weighing fields would invite an inspector to fill them in
/// at a desk rather than at the line.
class PoultryQuidSetupForm extends StatefulWidget {
  const PoultryQuidSetupForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;

  @override
  State<PoultryQuidSetupForm> createState() => _PoultryQuidSetupFormState();
}

class _SetupReference {
  _SetupReference({required this.reasons, required this.locations});
  final List<PoultryDesignationRef> reasons;
  final List<PoultryDesignationRef> locations;
}

class _PoultryQuidSetupFormState extends State<PoultryQuidSetupForm> {
  late Future<_SetupReference> _reference;
  final _formKey = GlobalKey<FormState>();

  int? _locationId;
  int? _reasonId;

  final _facilityName = TextEditingController();
  final _tradingName = TextEditingController();
  final _facilityAddress = TextEditingController();
  final _facilityTelephone = TextEditingController();
  final _companyReg = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactEmail = TextEditingController();
  final _productDetails = TextEditingController();
  final _injectorName = TextEditingController();
  final _dispensation = TextEditingController();

  bool _isWaterChilled = false;
  bool _isWholeCarcass = false;
  bool _isRegulatedStandard = false;
  bool _setupComplete = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reference = _load();
  }

  Future<_SetupReference> _load() async => _SetupReference(
        reasons: await widget.repository.inspectionReasons(),
        locations: await widget.repository.inspectionLocations(),
      );

  @override
  void dispose() {
    for (final c in [
      _facilityName,
      _tradingName,
      _facilityAddress,
      _facilityTelephone,
      _companyReg,
      _contactPerson,
      _contactEmail,
      _productDetails,
      _injectorName,
      _dispensation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final uuid = const Uuid().v4();
    await widget.captureRepository.saveQuidInspection(
      PoultryQuidInspectionsCompanion.insert(
        clientUuid: uuid,
        inspectedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        // Always a draft on leaving this screen. The checklist is not finished
        // until the weighing is done, and marking it complete here would put
        // an unweighed QUID record in the register.
        status: const Value('draft'),
        locationId: Value(_locationId),
        reasonId: Value(_reasonId),
        facilityName: Value(_facilityName.text.trim()),
        producerTradingName: Value(_tradingName.text.trim()),
        facilityAddress: Value(_facilityAddress.text.trim()),
        facilityTelephone: Value(_facilityTelephone.text.trim()),
        companyRegNumber: Value(_companyReg.text.trim()),
        contactPerson: Value(_contactPerson.text.trim()),
        contactPersonEmail: Value(_contactEmail.text.trim()),
        productDetails: Value(_productDetails.text.trim()),
        isWaterChilled: Value(_isWaterChilled),
        isWholeCarcass: Value(_isWholeCarcass),
        injectorName: Value(_injectorName.text.trim()),
        isRegulatedStandard: Value(_isRegulatedStandard),
        dispensationQuidPercent: Value(_dispensation.text.trim()),
        setupComplete: Value(_setupComplete),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QUID checklist set up'),
        content: const Text(
          'Weigh the carcasses from "Continue with QUID Checklist" when you '
          'are at the line.',
          style: TextStyle(height: 1.4),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Setup QUID Checklist',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<_SetupReference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null) return const PoultryNoRules();

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                poultrySection('Inspection Details'),
                poultryDropdown(
                  label: 'Reason for Inspection',
                  value: _reasonId,
                  items: reference.reasons,
                  onChanged: (v) => setState(() => _reasonId = v),
                ),
                poultryDropdown(
                  label: 'Inspection Facility Type',
                  value: _locationId,
                  items: reference.locations,
                  onChanged: (v) => setState(() => _locationId = v),
                ),
                poultryField(_facilityName, 'New Facility Name',
                    required: true),
                poultryField(
                    _tradingName, 'Name or Trading Name of New Facility'),
                poultryField(_facilityAddress, 'Facility Address', lines: 2),
                poultryField(
                  _facilityTelephone,
                  'Facility Primary Contact Telephone Number',
                  keyboard: TextInputType.phone,
                ),
                poultryField(_companyReg, 'Company Registration Number'),
                poultryField(
                    _contactPerson, 'Representative Name / Person in Charge'),
                poultryField(
                  _contactEmail,
                  'Representative Name Email Address',
                  keyboard: TextInputType.emailAddress,
                ),
                poultryField(_productDetails, 'Product Details'),

                poultrySection('Inspection Set-Up'),
                poultrySwitch(
                  label: 'Water',
                  value: _isWaterChilled,
                  onChanged: (v) => setState(() => _isWaterChilled = v),
                ),
                poultrySwitch(
                  label: 'Whole Carcass',
                  value: _isWholeCarcass,
                  onChanged: (v) => setState(() => _isWholeCarcass = v),
                ),
                poultryField(_injectorName, 'Injector Name/Identifier'),
                poultrySwitch(
                  label: 'Regulated Standard',
                  value: _isRegulatedStandard,
                  onChanged: (v) => setState(() => _isRegulatedStandard = v),
                ),
                poultryField(_dispensation, 'Dispensation QUID %'),
                poultrySwitch(
                  label: 'Inspection Set-Up Details Complete',
                  value: _setupComplete,
                  onChanged: (v) => setState(() => _setupComplete = v),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save set-up'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
