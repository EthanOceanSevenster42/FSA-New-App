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
    this.enabled = true,
    this.disabledHint,
    this.showPhotos = true,
    this.showSignatures = true,
    this.photosTitle,
    this.captureLabel,
    this.guidance,
    this.showClearPhotos = false,
    this.maxPhotos,
    this.minPhotos,
    this.captureNotes = const [],
  });

  final PoultryCaptureRepository repository;

  /// The record these belong to. Photographs are stored against it before the
  /// record itself has ever been uploaded — which is the ordinary case.
  final String recordUuid;

  /// `grading`, `label` or `quid`.
  final String kind;

  final VoidCallback? onChanged;

  /// False while the form's own rules say photographs may not be taken yet —
  /// the original greys its capture button rather than hiding it, so an
  /// inspector can see the step exists.
  final bool enabled;

  /// Shown in place of the capture control while [enabled] is false, saying
  /// what has to happen first.
  final String? disabledHint;

  /// A form may place the photographs and the signatures in different parts
  /// of the page, as the original does.
  final bool showPhotos;
  final bool showSignatures;

  /// The original names this block and its buttons differently per screen —
  /// "Product Photos" with "Take Product Photos" and "Clear Product Photos"
  /// on the PMP and Raw screens. Left null, the general wording stands.
  final String? photosTitle;
  final String? captureLabel;

  /// What the photographs are meant to show, in the inspector's own terms.
  ///
  /// A count on its own — "0 of 1 taken" — says how many but never what of,
  /// and a photograph that misses the mark it was meant to evidence cannot
  /// defend the finding it belongs to. Each screen says what its own
  /// evidence has to show.
  final String? guidance;
  final bool showClearPhotos;

  /// How many photographs this block will take. Left null, there is no
  /// ceiling. The camera closes once the last one is taken rather than
  /// refusing afterwards, so an inspector is never told a shot they have
  /// already framed is one too many.
  final int? maxPhotos;

  /// How many of them the form needs before it will move on. Shown in the
  /// count so an inspector can see which of the shots are the required
  /// ones and which are extra.
  final int? minPhotos;

  /// What to say before each of the first photographs, in order — the
  /// original stops and asks for a front view, then a rear view, so the two
  /// shots the checklist depends on are the two it gets.
  final List<({String title, String message})> captureNotes;

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
    // Its own kind only: a QUID record also carries a photograph per
    // verification document, and those are not the rejection's.
    final photos =
        await widget.repository.photosFor(widget.recordUuid, kind: widget.kind);
    final signatures = await widget.repository.signaturesFor(widget.recordUuid);
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

    // The note for this shot, if the form has one — front view, then rear.
    if (_photos.length < widget.captureNotes.length) {
      final note = widget.captureNotes[_photos.length];
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(note.title),
          content: Text(note.message, style: const TextStyle(height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

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

  /// What the line under the heading says: how many are on the record, how
  /// many the form needs, and how many more it will take.
  String get _countLine {
    final max = widget.maxPhotos;
    if (_full) return 'All $max taken. Delete one to take another.';
    final min = widget.minPhotos;
    if (min != null) {
      return '${_photos.length} of $max taken — the first $min are '
          'required, the rest optional.';
    }
    return '${_photos.length} of $max taken — $max at most, fewer is fine.';
  }

  /// Whether this block has all the photographs it takes.
  bool get _full =>
      widget.maxPhotos != null && _photos.length >= widget.maxPhotos!;

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
        if (widget.showPhotos) ...[
          poultrySection(widget.photosTitle ?? 'Photographs'),
          // How many are on the record, and how many this block will take.
          // Said as a count rather than only when the last one is used up:
          // an inspector deciding whether to take another shot should not
          // have to count thumbnails to find out.
          if (widget.guidance != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                widget.guidance!,
                style: TextStyle(
                    color: AppColors.inkSoft, fontSize: 13, height: 1.35),
              ),
            ),
          if (widget.maxPhotos != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _countLine,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          if (_photos.isNotEmpty)
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
            )
          // The count above already says none have been taken.
          else if (widget.maxPhotos == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'None taken yet.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          if (!widget.enabled && widget.disabledHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                widget.disabledHint!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.muted,
                ),
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed:
                    (_capturing || !widget.enabled || _full) ? null : _capture,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_capturing
                    ? 'Saving…'
                    : (widget.captureLabel ?? 'Take photograph')),
              ),
              if (widget.showClearPhotos)
                TextButton.icon(
                  onPressed: (_capturing || _photos.isEmpty)
                      ? null
                      : () async {
                          for (final photo in [..._photos]) {
                            await widget.repository.deletePhoto(photo.id);
                          }
                          await _reload();
                          widget.onChanged?.call();
                        },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear Product Photos'),
                ),
            ],
          ),
        ],
        if (widget.showSignatures) ...[
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
                child:
                    Icon(Icons.broken_image_outlined, color: AppColors.muted),
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
                // Red: this throws the photograph away. A grey badge
                // read as decoration on top of a thumbnail.
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
