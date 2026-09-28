import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/data/local_database.dart';
import '../../../core/platform/downloads.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../data/record_documents.dart';

/// The documents one inspection produced, each with a way to read it and a
/// way to keep it.
///
/// Shown wherever the record is — on the group and on the record itself —
/// because an inspector asked for a checklist is standing in front of
/// someone, not hunting through screens for it. Nothing is drawn until the
/// documents are known, and a record that has produced none takes no space.
class RecordDocumentsSection extends StatelessWidget {
  const RecordDocumentsSection({
    super.key,
    required this.database,
    required this.kind,
    required this.uuid,
    this.heading = true,
    this.padding = EdgeInsets.zero,
  });

  final LocalDatabase database;

  /// 'rawrmp' | 'pmp' | 'egg' | 'poultry' | 'poultry_label'
  final String kind;
  final String uuid;

  /// Whether to draw the DOCUMENTS heading, or sit under one already there.
  final bool heading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecordDocument>>(
      future: documentsForRecord(database, kind, uuid),
      builder: (context, snapshot) {
        final documents = snapshot.data ?? const <RecordDocument>[];
        if (documents.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (heading) ...[
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
                  'The forms this inspection produced — the same documents '
                  'sent to the office with the record.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.muted, height: 1.35),
                ),
              ],
              for (final document in documents) ...[
                const SizedBox(height: 14),
                Text(
                  document.title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  document.note,
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
                          onPressed: () =>
                              _open(context, document, download: false),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('VIEW',
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
                          onPressed: () =>
                              _open(context, document, download: true),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('DOWNLOAD',
                                maxLines: 1, style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Builds the document and shows it, or saves it to Downloads.
  Future<void> _open(BuildContext context, RecordDocument document,
      {required bool download}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final file = await document.build();
      if (file == null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text('${document.title} has nothing to show yet.')));
        return;
      }
      final bytes = await file.readAsBytes();
      if (download) {
        final saved = await Downloads.save(document.downloadName, bytes);
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
        return;
      }
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(document.title)),
          body: ContentWidth(
            child: PdfPreview(
              build: (_) => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: document.downloadName,
            ),
          ),
        ),
      ));
    } on Object catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('${document.title} could not be built. $e')));
    }
  }
}
