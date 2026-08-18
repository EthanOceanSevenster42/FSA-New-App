import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/data/eggs_sync_service.dart';

/// The upload status has to change while the inspector is looking at it.
///
/// Re-queueing a record marked it Pending, and it only turned Uploaded after
/// leaving the page and coming back — which reads as the app having done
/// nothing. The list has to redraw when a sync pass finishes, not when it
/// happens to be rebuilt.
class _StatusList extends StatefulWidget {
  const _StatusList({required this.onSync, required this.statusOf});

  final Stream<SyncReport> onSync;

  /// Re-read on every redraw, standing in for the database query.
  final String Function() statusOf;

  @override
  State<_StatusList> createState() => _StatusListState();
}

class _StatusListState extends State<_StatusList> {
  StreamSubscription<SyncReport>? _watch;
  late String _status = widget.statusOf();

  @override
  void initState() {
    super.initState();
    _watch = widget.onSync.listen((_) {
      if (mounted) setState(() => _status = widget.statusOf());
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: Text(_status)));
}

void main() {
  testWidgets('a finished pass turns Pending into Uploaded on screen',
      (tester) async {
    final reports = StreamController<SyncReport>.broadcast();
    var uploaded = false;

    await tester.pumpWidget(
      _StatusList(
        onSync: reports.stream,
        statusOf: () => uploaded ? 'Uploaded' : 'Pending',
      ),
    );

    expect(find.text('Pending'), findsOneWidget);

    // The record goes up in the background.
    uploaded = true;
    reports.add(const SyncReport(
      inspectionsSent: 1,
      directionsSent: 0,
      failures: 0,
    ));
    await tester.pump();

    expect(find.text('Uploaded'), findsOneWidget,
        reason: 'without leaving the page and coming back');
    expect(find.text('Pending'), findsNothing);

    await reports.close();
  });

  testWidgets('the listener is released with the page', (tester) async {
    final reports = StreamController<SyncReport>.broadcast();

    await tester.pumpWidget(
      _StatusList(onSync: reports.stream, statusOf: () => 'Pending'),
    );
    expect(reports.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(reports.hasListener, isFalse,
        reason: 'a page that has gone must not keep redrawing');

    await reports.close();
  });

  test('a pass that sent something is announced', () {
    // Only reports that did something are emitted, so an idle app is not
    // redrawing its lists every two minutes for nothing.
    const nothing = SyncReport.nothingToDo();
    expect(nothing.didAnything, isFalse);

    const sent = SyncReport(
      inspectionsSent: 1,
      directionsSent: 0,
      failures: 0,
    );
    expect(sent.didAnything, isTrue);

    const failed = SyncReport(
      inspectionsSent: 0,
      directionsSent: 0,
      failures: 1,
    );
    expect(failed.didAnything, isTrue,
        reason: 'a failure changes what the list should show too');
  });
}
