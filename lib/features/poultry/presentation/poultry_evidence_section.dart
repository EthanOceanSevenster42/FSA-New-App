import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';
import '../../../core/services/in_app_camera.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import 'poultry_form_widgets.dart';
import 'signature_pad.dart';

/// Photographs and signatures for a poultry record.
///
/// One widget for all three capture screens: the evidence attached to a
/// grading inspection, a label checklist and a QUID checklist is the same
/// thing recorded against a different `kind`, and three copies of this would
/// be three places to get the upload wrong.
class PoultryEvidenceSection extends StatefulWidget {
  const PoultryEvidenceSection({
    super.key,
    required this.repository,
    required this.recordUuid,
    required this.kind,
    this.onChanged,
  });

  final PoultryCaptureRepository repository;

  /// The record these belong to. Photographs are stored against it before the
  /// record itself has ever been uploaded — which is the ordinary case.
  final String recordUuid;

  /// `grading`, `label` or `quid`.
  final String kind;

  final VoidCallback? onChanged;

  @override
  State<PoultryEvidenceSection> createState() => _PoultryEvidenceSectionState();
}

/// The signature blocks the original carries, in its own words.
const _roles = <({String role, String label})>[
  (role: 'inspector', label: 'Inspector'),
  (role: 'client', label: 'Client'),
  (role: 'new_client', label: 'New/Updated Client'),
];

class _PoultryEvidenceSectionState extends State<PoultryEvidenceSection> {
  List<PoultryPhoto> _photos = const [];
  List<PoultrySignature> _signatures = const [];
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    // No notification on the first load: telling the form "evidence changed"
    // while merely opening it would save an empty draft for a record the
    // inspector may never fill in.
    _reload(notify: false);
  }

  Future<void> _reload({bool notify = true}) async {
    final photos = await widget.repository.photosFor(widget.recordUuid);
    final signatures =
        await widget.repository.signaturesFor(widget.recordUuid);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _signatures = signatures;
    });
    if (notify) widget.onChanged?.call();
  }

  Future<void> _capture() async {
    // One at a time. Two cameras in flight would race on the file name.
    if (_capturing) return;

    final String? shotPath;
    try {
      shotPath = await capturePhoto(context, title: 'Photograph');
    } on Object catch (e) {
      if (mounted) _toast('The camera could not be opened. $e');
      return;
    }
    if (shotPath == null) return;

    setState(() => _capturing = true);
    try {
      final storage = await PhotoStorage.instance();
      // Millisecond stamp rather than a running count: deleting a photo would
      // make a count repeat and overwrite a file that is still referenced.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await storage.adopt(
        File(shotPath),
        name: 'poultry_${widget.recordUuid}_${widget.kind}_$stamp.jpg',
      );
      await widget.repository.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: widget.recordUuid,
          kind: widget.kind,
          filePath: path,
          capturedAt: DateTime.now(),
        ),
      );
      await _reload();
    } on Object catch (e) {
      if (mounted) _toast('The photo could not be saved. $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _sign(String role, String label) async {
    final storage = await PhotoStorage.instance();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = storage.pathFor(
      'sig_${widget.recordUuid}_${role}_$stamp.png',
    );

    if (!mounted) return;
    final saved = await captureSignature(
      context,
      title: label,
      outputPath: path,
    );
    if (saved == null) return;

    await widget.repository.saveSignature(
      PoultrySignaturesCompanion.insert(
        recordUuid: widget.recordUuid,
        role: role,
        signedAt: DateTime.now(),
        filePath: Value(saved),
      ),
    );
    await _reload();
  }

  /// Records that a signature was refused.
  ///
  /// A refusal is an outcome the original has a role for, not a blank. Stored
  /// so it can be told apart from an inspection nobody finished.
  Future<void> _decline() async {
    await widget.repository.saveSignature(
      PoultrySignaturesCompanion.insert(
        recordUuid: widget.recordUuid,
        role: 'no_client',
        signedAt: DateTime.now(),
        declined: const Value(true),
      ),
    );
    await _reload();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  PoultrySignature? _for(String role) {
    for (final s in _signatures) {
      if (s.role == role) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // The row's flag, not its existence: un-ticking leaves a row behind, and
    // treating any row as a refusal would keep the client blocks closed.
    final declined = _for('no_client')?.declined ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poultrySection('Photographs'),
        if (_photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'None taken yet.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(
                photo: _photos[i],
                onDelete: () async {
                  await widget.repository.deletePhoto(_photos[i].id);
                  await _reload();
                },
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _capturing ? null : _capture,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_capturing ? 'Saving…' : 'Take photograph'),
          ),
        ),

        poultrySection('Signatures'),
        for (final entry in _roles)
          _SignatureRow(
            label: entry.label,
            signature: _for(entry.role),
            // Once a refusal is recorded there is nobody to sign, so the
            // client blocks are closed rather than left inviting a signature
            // the record already says was not given.
            disabled: declined && entry.role != 'inspector',
            onSign: () => _sign(entry.role, entry.label),
          ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: declined,
          title: const Text(
            'No Client Signature is available',
            style: TextStyle(fontSize: 13.5),
          ),
          onChanged: (on) async {
            if (on ?? false) {
              await _decline();
            } else {
              await widget.repository.saveSignature(
                PoultrySignaturesCompanion.insert(
                  recordUuid: widget.recordUuid,
                  role: 'no_client',
                  signedAt: DateTime.now(),
                  declined: const Value(false),
                ),
              );
              await _reload();
            }
          },
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onDelete});

  final PoultryPhoto photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Stack(
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
                child: Icon(Icons.broken_image_outlined,
                    color: AppColors.muted),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      );
}

class _SignatureRow extends StatelessWidget {
  const _SignatureRow({
    required this.label,
    required this.signature,
    required this.disabled,
    required this.onSign,
  });

  final String label;
  final PoultrySignature? signature;
  final bool disabled;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final signed = signature != null && !signature!.declined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: disabled ? AppColors.muted : AppColors.ink,
              ),
            ),
          ),
          if (signed)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(signature!.filePath),
                width: 96,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.check, color: AppColors.brandTeal),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: disabled ? null : onSign,
            child: Text(signed ? 'Re-sign' : 'Sign'),
          ),
        ],
      ),
    );
  }
}
