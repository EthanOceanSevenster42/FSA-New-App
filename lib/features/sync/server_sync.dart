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
import '../invoicing/data/tariff_sync.dart';
import '../updates/data/version_report.dart';
import '../calendar/data/planned_visit_repository.dart';
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
    this.versionReport,
    this.planner,
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

  /// Tells the office which build this handset runs.
  final VersionReport? versionReport;

  /// The inspector's own planned visits, copied up so the office can see
  /// what is on for the week.
  final PlannedVisitRepository? planner;

  List<SyncStep> freshSteps() => [
        SyncStep('Sign-ins and fees'),
        SyncStep('Eggs'),
        SyncStep('Poultry'),
        SyncStep('Processed Meat Products'),
        SyncStep('Certain Raw Processed Meat Products'),
        SyncStep('Inspections'),
        SyncStep('Planning'),
      ];

  static String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  /// One commodity's outcome, in plain words: what came down and what went
  /// up (Ethan, 2026-10-01). "Up to date — nothing to send" when neither.
  static String _outcome(int rows, int sent) {
    if (rows == 0 && sent == 0) return 'Up to date — nothing to send';
    return '${rows == 0 ? 'Lists up to date' : '${_plural(rows, 'list item')} updated'}, '
        '${sent == 0 ? 'nothing to send' : '${_plural(sent, 'inspection')} sent to the office'}';
  }

  /// A step that sent some and could not send the rest.
  static String _partly(int sent, int failed, String first) =>
      '${_plural(sent, 'inspection')} sent, $failed could not be sent — '
      '${failed == 1 ? 'it stays' : 'they stay'} on this device and go on '
      'the next sync. $first';

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
    const noToken = 'Nothing sent — sign in once while you have signal';

    await _step(steps[0], onChanged, () async {
      await authService.syncUsers();
      final total = await authService.localUserCount();
      // The RFI tariff, as the office last set it on the web. Fetched first
      // so the Requests for Invoice sent further down bill with it.
      var tariff = '';
      if (token != null) {
        try {
          final changed = await TariffSync(
            database: eggs.database,
            baseUrl: eggs.baseUrl,
          ).pull(token: token);
          tariff = changed
              ? ' · RFI fees updated from the office'
              : ' · RFI fees up to date';
        } on Object {
          // The last tariff kept on the device stays in force.
        }
        try {
          await versionReport?.send(token: token);
        } on Object {
          // Only a report; it goes again with the next sync.
        }
      }
      return '${_plural(total, 'inspector')} can sign in without signal'
          '$tariff';
    });

    await _step(steps[1], onChanged, () async {
      final rows = await eggs.syncReference();
      final report = await eggsSync.syncNow();
      if (report.failures > 0) {
        throw Exception(_partly(
            report.sent,
            report.failures,
            report.firstError == null
                ? ''
                : 'First error: ${report.firstError}'));
      }
      return _outcome(rows, report.sent);
    });

    await _step(steps[2], onChanged, () async {
      final rows = await poultry.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        // Grading inspections — the poultry form's own records. Left out
        // when this step was written, so they were captured, signed and
        // never sent: nothing on the handset ever carried them up.
        for (final i in await poultry.inspectionsForUpload()) {
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
        for (final i in await poultryCapture.labelInspectionsForUpload()) {
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
        for (final i in await poultryCapture.quidInspectionsForUpload()) {
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
        for (final d in await poultryCapture.directionsForUpload()) {
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
            _partly(sent, failed.length, 'First error: ${failed.first}'));
      }
      return token == null
          ? '${_outcome(rows, 0).split(',').first} · $noToken'
          : _outcome(rows, sent);
    });

    await _step(steps[3], onChanged, () async {
      final rows = await pmp.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        for (final i in await pmp.inspectionsForUpload()) {
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
        for (final d in await pmp.directionsForUpload()) {
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
            _partly(sent, failed.length, 'First error: ${failed.first}'));
      }
      return token == null
          ? '${_outcome(rows, 0).split(',').first} · $noToken'
          : _outcome(rows, sent);
    });

    await _step(steps[4], onChanged, () async {
      final rows = await rawRmp.syncReference();
      var sent = 0;
      final failed = <String>[];
      if (token != null) {
        for (final i in await rawRmp.inspectionsForUpload()) {
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
        for (final d in await rawRmp.directionsForUpload()) {
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
            _partly(sent, failed.length, 'First error: ${failed.first}'));
      }
      return token == null
          ? '${_outcome(rows, 0).split(',').first} · $noToken'
          : _outcome(rows, sent);
    });

    await _step(steps[5], onChanged, () async {
      final repository = visits;
      if (repository == null) return 'Not configured on this device';
      if (token == null) return noToken;
      // Approvals given in Inspection Management that have not reached the
      // server yet.
      final approvals = await repository.sendPendingApprovals(token: token);
      // What the server holds for this inspector lately, seizures included,
      // brought down so Inspection Management shows it. A failure here
      // costs nothing but the pull; the uploads below still run.
      var pulled = 0;
      try {
        pulled =
            await repository.pullFromServer(token: token, owner: username);
      } on Object {
        pulled = 0;
      }
      final broughtDown = pulled == 0
          ? ''
          : ' · ${_plural(pulled, 'inspection')} brought down from the office';
      final pending = await repository.pendingUploads();
      if (pending.isEmpty) {
        // Nothing to send; still clear what the server has had for five
        // days (Ethan, 2026-10-03).
        final cleared = await repository.purgeUploadedVisits();
        final tidy = cleared == 0
            ? ''
            : ' · ${_plural(cleared, 'old inspection')} cleared off this '
                'device';
        return approvals == 0
            ? 'Everything is sent$broughtDown$tidy'
            : '${_plural(approvals, 'approval')} sent to the office'
                '$broughtDown$tidy';
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
          var inspectionStart = '';
          var inspectionEnd = '';
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
              // The times actually worked, which the form prints and which
              // the hours above have been rounded up from.
              inspectionStart = form.timeStarted;
              inspectionEnd = form.timeEnded;
            } on Object {
              // A record without its billing document is still a record.
            }
          }
          // Eggs and poultry only: the RFI is kept on the handset and not
          // sent (see VisitRepository.rfiStaysOnHandset).
          if (rfi != null && await repository.rfiStaysOnHandset(visit.uuid)) {
            rfi = null;
          }
          if (await repository.upload(
            visit,
            token: token,
            invoicePdf: rfi,
            kilometres: kilometres,
            hours: hours,
            inspectionStart: inspectionStart,
            inspectionEnd: inspectionEnd,
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
        throw Exception(_partly(sent, failed.length, 'First: ${failed.first}'));
      }
      // Approvals given before these visits synced can go now they are up.
      final approvedToo =
          approvals + await repository.sendPendingApprovals(token: token);
      // Work the server has had for five days goes off the handset, images
      // and all (Ethan, 2026-10-03). Nothing still waiting is touched.
      final cleared = await repository.purgeUploadedVisits();
      return '${_plural(sent, 'inspection')} sent to the office'
          '${approvedToo == 0 ? '' : ' · ${_plural(approvedToo, 'approval')} sent'}'
          '$broughtDown'
          '${cleared == 0 ? '' : ' · ${_plural(cleared, 'old inspection')} '
              'cleared off this device'}';
    });

    // The inspector's own planning, copied up so the office can answer
    // "what has she got on for Tuesday" without telephoning her. Last,
    // and deliberately forgiving: a plan is not a record, and nothing
    // that failed here is lost — it goes up on the next sync. A sync must
    // never be reported as failed over a diary entry.
    await _step(steps[6], onChanged, () async {
      final planner = this.planner;
      if (planner == null) return 'Not configured on this device';
      if (token == null) return noToken;
      try {
        final sent = await planner.uploadPending(
          token: token,
          inspector: username,
        );
        // Then the other direction: the office can put a visit on this
        // inspector's calendar now, and it reaches them here. Sent first
        // so the handset's own edits are already up before the office's
        // copy is read back \u2014 otherwise a plan changed on the tablet this
        // morning would be compared against a server row that has not
        // heard about it yet.
        final brought = await planner.downloadPlans(
          token: token,
          inspector: username,
        );
        final parts = [
          if (sent > 0) '${_plural(sent, 'planned visit')} sent to the office',
          if (brought > 0)
            '${_plural(brought, 'planned visit')} brought down',
        ];
        return parts.isEmpty
            ? 'Up to date \u2014 nothing to send'
            : parts.join(' \u00b7 ');
      } on Object catch (e) {
        return 'Could not sync planning this time \u2014 it will go again on '
            'the next sync. ($e)';
      }
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
  var steps = runner.freshSteps();
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
                          ? 'Everything is up to date with the office.'
                          : 'Done, but $failures step'
                              '${failures == 1 ? '' : 's'} could not finish — '
                              'those inspections stay on this device and go '
                              'on the next sync.',
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
            // Sends everything on the device again, whether or not it has
            // changed. For when the office is holding an older copy than
            // this device has — documents built by an earlier version of the
            // app, say — which an ordinary sync leaves alone because the
            // record is already marked sent (Ethan, 2026-10-08).
            //
            // Not done on every sign-in: that would re-upload days of work
            // every morning, often on mobile data, and would hide a genuine
            // upload failure behind the noise.
            if (finished && runner.visits != null)
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('Send everything again?'),
                      content: const Text(
                        'Every inspection still on this device goes to the '
                        'office again, even the ones already sent. The '
                        'office replaces its copies rather than filing '
                        'second ones. Use this when a report reached the '
                        'office with something missing.',
                        style: TextStyle(height: 1.4),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(confirmContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(confirmContext).pop(true),
                          child: const Text('Send again'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  final marked = await runner.visits!.markAllForResend();
                  if (!dialogContext.mounted) return;
                  if (marked == 0) {
                    ScaffoldMessenger.of(dialogContext)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        content: Text(
                            'Nothing on this device to send again.'),
                      ));
                    return;
                  }
                  // Round two, from the top.
                  setState(() {
                    steps = runner.freshSteps();
                    started = false;
                    finished = false;
                  });
                },
                child: const Text('Re-send everything'),
              ),
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
