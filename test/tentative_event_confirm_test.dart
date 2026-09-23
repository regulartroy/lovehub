import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/widgets/tentative_event_confirm.dart';

void main() {
  test('narrow screens use the shorter confirm label', () {
    expect(tentativeConfirmActionLabel(390), "Confirm I'm working this");
    expect(tentativeConfirmActionLabel(359), "I'm working this");
  });

  testWidgets('confirm writes through and keep leaves the shift alone', (
    tester,
  ) async {
    var confirmed = 0;
    var edited = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTentativeEventConfirmSheet(
                context: context,
                eventId: 'c2-rota:2026-09-20',
                title: 'C2 Show — Artist',
                subtitle: 'Sun 20 Sep · 15:00–23:30',
                notes: 'call time 14:30',
                onConfirm: () async {
                  confirmed += 1;
                },
                onEdit: () => edited += 1,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('C2 Show — Artist'), findsOneWidget);
    expect(find.text('Tentative'), findsOneWidget);
    expect(find.text("Confirm I'm working this"), findsOneWidget);
    expect(find.text('Keep tentative'), findsOneWidget);

    await tester.tap(find.text('Keep tentative'));
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(edited, 0);
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Confirm I'm working this"));
    await tester.pumpAndSettle();

    expect(confirmed, 1);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Tentative'), findsNothing);
  });

  testWidgets('a failed confirm stays on the sheet and keeps the shift', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTentativeEventConfirmSheet(
                context: context,
                eventId: 'c2-rota:2026-09-20',
                title: 'C2 Show — Artist',
                onConfirm: () async {
                  throw StateError('offline');
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Confirm I'm working this"));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('tentative-event-confirm-error')),
      findsOneWidget,
    );
    expect(find.text('C2 Show — Artist'), findsOneWidget);
    expect(find.text('Keep tentative'), findsOneWidget);
  });

  testWidgets('a narrow phone shows the short confirm label', (tester) async {
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTentativeEventConfirmSheet(
                context: context,
                eventId: 'c2-rota:2026-09-20',
                title: 'C2 Show',
                onConfirm: () async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text("I'm working this"), findsOneWidget);
    expect(find.text("Confirm I'm working this"), findsNothing);
  });

  test('chip tap confirms, marks tentative, or edits', () {
    EventModel event({required String id, String? status}) {
      return EventModel(
        id: id,
        summary: 'Shift',
        start: DateTime.utc(2026, 9, 20, 15),
        end: DateTime.utc(2026, 9, 20, 23),
        status: status,
      );
    }

    expect(
      eventChipStatusAction(
        event(id: 'c2-rota:2026-09-20', status: 'tentative'),
      ),
      EventChipStatusAction.confirm,
    );
    expect(
      eventChipStatusAction(
        event(id: 'c2-rota:2026-09-20', status: 'confirmed'),
      ),
      EventChipStatusAction.markTentative,
    );
    expect(
      eventChipStatusAction(event(id: 'dinner')),
      EventChipStatusAction.markTentative,
    );
    expect(
      eventChipStatusAction(event(id: 'bday_maria_2026')),
      EventChipStatusAction.edit,
    );
  });

  testWidgets('mark tentative writes through and keep leaves it confirmed', (
    tester,
  ) async {
    var marked = 0;
    var edited = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMarkEventTentativeSheet(
                context: context,
                eventId: 'c2-rota:2026-09-20',
                title: 'C2 Show — Artist',
                subtitle: 'Sun 20 Sep · 15:00–23:30',
                notes: 'call time 14:30',
                onMarkTentative: () async {
                  marked += 1;
                },
                onEdit: () => edited += 1,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('C2 Show — Artist'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Mark tentative'), findsOneWidget);
    expect(find.text('Keep confirmed'), findsOneWidget);
    expect(find.text('Edit details'), findsOneWidget);

    await tester.tap(find.text('Keep confirmed'));
    await tester.pumpAndSettle();

    expect(marked, 0);
    expect(edited, 0);
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark tentative'));
    await tester.pumpAndSettle();

    expect(marked, 1);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
  });

  testWidgets('a failed mark tentative stays on the sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMarkEventTentativeSheet(
                context: context,
                eventId: 'dinner',
                title: 'Dinner',
                onMarkTentative: () async {
                  throw StateError('offline');
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark tentative'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mark-event-tentative-error')),
      findsOneWidget,
    );
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Keep confirmed'), findsOneWidget);
  });

  testWidgets('edit details closes the mark sheet and opens edit', (
    tester,
  ) async {
    var edited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMarkEventTentativeSheet(
                context: context,
                eventId: 'dinner',
                title: 'Dinner',
                onMarkTentative: () async {},
                onEdit: () => edited += 1,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    expect(edited, 1);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Mark tentative'), findsNothing);
  });
}
