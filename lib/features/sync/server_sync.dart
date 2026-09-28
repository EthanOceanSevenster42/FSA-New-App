import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../auth/domain/auth_service.dart';
import '../eggs/data/eggs_repository.dart';
import '../eggs/data/eggs_sync_service.dart';
import '../pmp/data/pmp_repository.dart';
import '../poultry/data/poultry_capture_repository.dart';
import '../poultry/data/poultry_repository.dart';
import '../rawrmp/data/rawrmp_repository.dart';
import '../invoicing/data/invoice_repository.dart';
import '../visits/data/visit_repository.dart';

/// Server Sync — the whole handshake behind one tap.
///
/// The sidebar button does exactly what going offline and coming back does,
/// but on demand: pull the user list and every commodity's reference data
/// down, and push every completed record that has not reached the register
/// yet, photographs and signatures included. It reports as a popup over the
/// home screen — each step says what it did or why it could not, and that is
/// all there is to it.

enum SyncStepState { waiting, running, done, failed }

class SyncStep {
  SyncStep(this.title);

  final String title;
  SyncStepState state = SyncStepState.waiting;
  String detail = '';
}

class ServerSyncRunner {
  ServerSyncRunner({
    required this.authService,
    required this.eggs,
    required this.eggsSync,
    required this.poultry,
    required this.poultryCapture,
    required this.pmp,
    required this.rawRmp,
    this.visits,
    this.invoices,
  });

  final AuthService authService;
  final EggsRepository eggs;
  final EggsSyncService eggsSync;
  final PoultryRepository poultry;
  final PoultryCaptureRepository poultryCapture;
  final PmpRepository pmp;
  final RawRmpRepository rawRmp;

  /// Grouped inspections. Their members go up through the commodity steps
  /// above; the group itself is what the office's record is made from.
  final VisitRepository? visits;

  /// Builds the Request for Invoice for a grouped inspection, so it can
  /// travel with it.
  final InvoiceRepository? invoices;

  List<SyncStep> freshSteps() => [
        SyncStep('Users'),
        SyncStep('Eggs'),
        SyncStep('Poultry'),
        SyncStep('Processed Meat Products'),
        SyncStep('Certain Raw Processed Meat Products'),
        SyncStep('Grouped inspections'),
      ];

  static String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  Future<void> _step(
    SyncStep step,
    VoidCallback onChanged,
    Future<String> Function() work,
  ) async {
    step.state = SyncStepState.running;
    onChanged();
    try {
      step
        ..detail = await work()
        ..state = SyncStepState.done;
    } on Object catch (e) {
      final message = '$e';
      step
        ..detail =
            message.length > 320 ? '${message.substring(0, 320)}…' : message
        ..state = SyncStepState.failed;
    }
    onChanged();
  }

  /// Runs every step in order, mutating [steps] and calling [onChanged] as
  /// each one moves. Never throws: a failed step is a reported outcome.
  Future<void> run(
    List<SyncStep> steps,
    String username,
    VoidCallback onChanged,
  ) async {
    // Use the refresh-aware token provider. Other repositories expose the raw
    // cached access token, which may have expired while an inspector was in
    // the field and would leave otherwise valid completed work stuck at 401.
    final token = await eggs.storedToken();
    const noToken = 'Sent nothing — sign in once with signal first';

    await _step(steps[0], onChanged, () async {
      await authService.syncUsers();
      final total = await authService.localUserCount();
      return '${_plural(total, 'user')} can sign in offline';
    });

    await _step(steps[1], onChanged, () async {
      final rows = await eggs.syncReference();
      final report = await eggsSync.syncNow();
      if (report.failures > 0) {
        throw Exception(
          '${report.failures} record'
          '${report.failures == 1 ? '' : 's'} failed to send — kept on '
          'this device'
          '${report.firstError == null ? '' : '. ${report.firstError}'}',
        );
      }
      return '${_plural(rows, 'reference row')} updated, '
          '${_plural(report.sent, 'record')} sent';
    });

    await _step(steps[2], onChanged, () async {
      final rows = await poultry.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        // Grading inspections — the poultry form's own records. Left out
        // when this step was written, so they were captured, signed and
        // never sent: nothing on the handset ever carried them up.
        for (final i in await poultry.savedInspections(username)) {
          if (i.status != 'completed') continue;
          try {
            if (!i.isUploaded) {
              await poultry.upload(i, token: token);
              sent++;
            }
            await poultryCapture.uploadEvidenceFor(i.clientUuid, token: token);
          } on Object catch (e) {
            failed.add('$e');
          }
        }
        for (final i in await poultryCapture.labelInspections(username)) {
          if (i.status != 'completed') continue;
          try {
            if (!i.isUploaded) {
              await poultryCapture.uploadLabelInspection(i, token: token);
              sent++;
            }
            await poultryCapture.uploadEvidenceFor(i.clientUuid, token: token);
          } on Object catch (e) {
            failed.add('$e');
          }
        }
        for (final i in await poultryCapture.quidInspections(username)) {
          if (i.status != 'completed') continue;
          try {
            if (!i.isUploaded) {
              await poultryCapture.uploadQuidInspection(i, token: token);
              sent++;
            }
            await poultryCapture.uploadEvidenceFor(i.clientUuid, token: token);
          } on Object catch (e) {
            failed.add('$e');
          }
        }
        for (final d in await poultryCapture.directions(username)) {
          if (d.status != 'completed' || d.isUploaded) continue;
          try {
            await poultryCapture.uploadDirection(d, token: token);
            sent++;
          } on Object catch (e) {
            failed.add('$e');
          }
        }
      }
      if (failed.isNotEmpty) {
        throw Exception(
          '${_plural(sent, 'record')} sent, ${failed.length} failed — '
          'kept on this device. First error: ${failed.first}',
        );
      }
      return '${_plural(rows, 'reference row')} updated, '
          '${token == null ? noToken : "${_plural(sent, 'record')} sent"}';
    });

    await _step(steps[3], onChanged, () async {
      final rows = await pmp.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        for (final i in await pmp.savedInspections(username)) {
          if (i.status != 'completed') continue;
          try {
            if (!i.isUploaded) {
              await pmp.upload(i, token: token);
              sent++;
            }
            await poultryCapture.uploadEvidenceFor(i.clientUuid, token: token);
          } on Object catch (e) {
            failed.add('$e');
          }
        }
        for (final d in await pmp.directions(username)) {
          if (d.status != 'completed' || d.isUploaded) continue;
          try {
            await pmp.uploadDirection(d, token: token);
            sent++;
          } on Object catch (e) {
            failed.add('$e');
          }
        }
      }
      if (failed.isNotEmpty) {
        throw Exception(
          '${_plural(sent, 'record')} sent, ${failed.length} failed — '
          'kept on this device. First error: ${failed.first}',
        );
      }
      return '${_plural(rows, 'reference row')} updated, '
          '${token == null ? noToken : "${_plural(sent, 'record')} sent"}';
    });

    await _step(steps[4], onChanged, () async {
      final rows = await rawRmp.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        for (final i in await rawRmp.savedInspections(username)) {
          if (i.status != 'completed') continue;
          try {
            if (!i.isUploaded) {
              await rawRmp.upload(i, token: token);
              sent++;
            }
            await poultryCapture.uploadEvidenceFor(i.clientUuid, token: token);
          } on Object catch (e) {
            failed.add('$e');
          }
        }
        for (final d in await rawRmp.directions(username)) {
          if (d.status != 'completed' || d.isUploaded) continue;
          try {
            await rawRmp.uploadDirection(d, token: token);
            sent++;
          } on Object catch (e) {
            failed.add('$e');
          }
        }
      }
      if (failed.isNotEmpty) {
        throw Exception(
          '${_plural(sent, 'record')} sent, ${failed.length} failed — '
          'kept on this device. First error: ${failed.first}',
        );
      }
      return '${_plural(rows, 'reference row')} updated, '
          '${token == null ? noToken : "${_plural(sent, 'record')} sent"}';
    });

    await _step(steps[5], onChanged, () async {
      final repository = visits;
      if (repository == null) return 'Not configured on this device';
      if (token == null) return noToken;
      // Approvals given in Inspection Management that have not reached the
      // server yet.
      final approvals = await repository.sendPendingApprovals(token: token);
      final pending = await repository.pendingUploads();
      if (pending.isEmpty) {
        return approvals == 0
            ? 'Nothing waiting'
            : '${_plural(approvals, 'approval')} sent to the office';
      }
      var sent = 0;
      final failed = <String>[];
      for (final visit in pending) {
        try {
          // The Request for Invoice goes up with the group: it is the
          // billing document for that visit, and the office expects to
          // find it on the record rather than on a handset.
          File? rfi;
          var kilometres = 0.0;
          var hours = 0.0;
          final invoices = this.invoices;
          // An occurrence report is not billed: nothing was inspected, so
          // it carries its Occurrence Document and no Request for Invoice.
          if (invoices != null && !visit.isOccurrenceReport) {
            try {
              final form = await invoices.formFor(visit);
              rfi = await invoices.renderPdf(form);
              // The office bills off these two, and the RFI is where the
              // inspector enters them, so the record carries the same
              // numbers as the document attached to it.
              kilometres = form.kilometres;
              hours = form.normalHours + form.overtimeHours + form.sundayHours;
            } on Object {
              // A record without its billing document is still a record.
            }
          }
          if (await repository.upload(
            visit,
            token: token,
            invoicePdf: rfi,
            kilometres: kilometres,
            hours: hours,
          )) {
            sent++;
          } else {
            failed.add(visit.facilityName);
          }
        } on Object catch (e) {
          failed.add('${visit.facilityName}: $e');
        }
      }
      if (failed.isNotEmpty) {
        throw Exception(
          '${_plural(sent, 'group')} sent, ${failed.length} failed — kept '
          'on this device. First: ${failed.first}',
        );
      }
      // Approvals given before these visits synced can go now they are up.
      final approvedToo =
          approvals + await repository.sendPendingApprovals(token: token);
      return '${_plural(sent, 'grouped inspection')} sent to the office'
          '${approvedToo == 0 ? '' : ', ${_plural(approvedToo, 'approval')}'}';
    });
  }
}

/// The popup itself: opens over whatever screen the inspector is on, starts
/// straight away, ticks its steps off as they land, and closes on tap once
/// everything has been tried. Nothing to navigate, nothing else to do.
Future<void> showServerSyncDialog(
  BuildContext context, {
  required ServerSyncRunner runner,
  required String username,
}) {
  final steps = runner.freshSteps();
  var started = false;
  var finished = false;

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        if (!started) {
          started = true;
          Future(() async {
            await runner.run(steps, username, () {
              if (dialogContext.mounted) setState(() {});
            });
            if (dialogContext.mounted) setState(() => finished = true);
          });
        }
        final failures =
            steps.where((s) => s.state == SyncStepState.failed).length;
        return AlertDialog(
          title: const Text('Server Sync'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: switch (step.state) {
                            SyncStepState.waiting => Icon(
                                Icons.circle_outlined,
                                size: 18,
                                color: AppColors.muted,
                              ),
                            SyncStepState.running => const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            SyncStepState.done => const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: Color(0xFF2E7D32),
                              ),
                            SyncStepState.failed => Icon(
                                Icons.error,
                                size: 18,
                                color: AppColors.noticeForeground,
                              ),
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (step.detail.isNotEmpty)
                                Text(
                                  step.detail,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: step.state == SyncStepState.failed
                                        ? AppColors.noticeForeground
                                        : AppColors.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      failures == 0
                          ? 'All inspections are synced with the server.'
                          : 'Done, with $failures step'
                              '${failures == 1 ? '' : 's'} failed — those '
                              'records stay on this device and will retry.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: failures == 0
                            ? const Color(0xFF2E7D32)
                            : AppColors.noticeForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  finished ? () => Navigator.of(dialogContext).pop() : null,
              child: Text(finished ? 'Close' : 'Syncing…'),
            ),
          ],
        );
      },
    ),
  );
}
