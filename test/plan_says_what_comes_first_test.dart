import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// The plan is walked in the order the counters were raised, and the page
/// now says so.
///
/// Nothing on the door page used to mention it. An inspector doing the raw
/// counter before the eggs had no way to know that adding raw first was what
/// decided it — they tapped START and were handed the egg form.
void main() {
  late LocalDatabase db;
  const visitUuid = 'visit-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          facilityName: const Value('Kroon Foods'),
          startedAt: DateTime(2026, 9, 23, 8),
        ));
  });
  tearDown(() async => db.close());

  Future<void> openDoor(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: visitUuid,
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();
    // The door is a long lazy list; the plan sits well below the fold and is
    // not built until it is scrolled to.
    await tester.scrollUntilVisible(
      find.text('PLAN — HOW MANY OF EACH'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Raises the counter on the [index]th plan row. The rows print in the
  /// order `_kinds` declares: eggs, poultry, raw, processed.
  Future<void> add(WidgetTester tester, int index) async {
    final button = find.byIcon(Icons.add_circle_outline).at(index);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  const egg = 0;
  const poultry = 1;
  const raw = 2;

  testWidgets('an empty plan says nothing about order', (tester) async {
    await openDoor(tester);
    expect(find.textContaining('start with'), findsNothing);
  });

  testWidgets('one commodity names itself as the start', (tester) async {
    await openDoor(tester);
    await add(tester, egg);
    expect(find.text("You'll start with Eggs."), findsOneWidget);
  });

  testWidgets('the first one added is the one named, not the first listed',
      (tester) async {
    await openDoor(tester);
    // Raw sits below eggs in the list, so choosing it first is exactly the
    // case the note exists for.
    await add(tester, raw);
    await add(tester, egg);
    await add(tester, poultry);

    expect(
      find.text('The first one you pick is the first one you do: '
          'Raw, then Eggs, then Poultry.'),
      findsOneWidget,
    );
  });

  testWidgets('the order survives leaving the visit and coming back',
      (tester) async {
    await openDoor(tester);
    await add(tester, poultry);
    await add(tester, egg);
    expect(
      find.text('The first one you pick is the first one you do: '
          'Poultry, then Eggs.'),
      findsOneWidget,
    );

    // Reopen it, the way an inspector does after stepping away.
    await openDoor(tester);
    expect(
      find.text('The first one you pick is the first one you do: '
          'Poultry, then Eggs.'),
      findsOneWidget,
      reason: 'the saved order must be what it reopens with',
    );
  });

  testWidgets('a commodity inherited from an older plan does not keep the '
      'front of the queue', (tester) async {
    // A visit saved before the order was recorded: eggs is on the plan, but
    // nothing says when it was chosen, so the load fills it in from the
    // printed list. The inspector then adds raw and re-adds eggs.
    await db.into(db.storeVisits).insertOnConflictUpdate(
          StoreVisitsCompanion.insert(
            uuid: visitUuid,
            inspectorUsername: const Value('ethan'),
            facilityName: const Value('Kroon Foods'),
            startedAt: DateTime(2026, 9, 23, 8),
            plannedEggs: const Value(1),
          ),
        );
    await openDoor(tester);
    expect(find.text("You'll start with Eggs."), findsOneWidget);

    // Take eggs back off, put raw on, then eggs on again — last chosen, so
    // last in the queue.
    await tester.tap(find.byIcon(Icons.remove_circle_outline).at(egg));
    await tester.pumpAndSettle();
    await add(tester, raw);
    await add(tester, egg);

    expect(
      find.text('The first one you pick is the first one you do: '
          'Raw, then Eggs.'),
      findsOneWidget,
    );
  });
}
