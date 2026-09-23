import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/event_tentative_field.dart';

void main() {
  test('the switch is shown only when the save writes an event document', () {
    expect(
      eventFormWritesStatus(existingEventId: null, category: 'general'),
      isTrue,
    );
    expect(
      eventFormWritesStatus(existingEventId: null, category: 'work'),
      isTrue,
    );
    expect(
      eventFormWritesStatus(existingEventId: null, category: 'birthday'),
      isFalse,
    );
    expect(
      eventFormWritesStatus(
        existingEventId: 'c2-rota:2026-09-20',
        category: 'work',
      ),
      isTrue,
    );
    expect(
      eventFormWritesStatus(
        existingEventId: 'bday_maria_2026',
        category: 'birthday',
      ),
      isFalse,
    );
  });

  testWidgets('tentative switch starts off and toggles on', (tester) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return EventTentativeField(
                value: value,
                onChanged: (next) => setState(() => value = next),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Tentative'), findsOneWidget);
    Switch control = tester.widget(find.byType(Switch));
    expect(control.value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    control = tester.widget(find.byType(Switch));
    expect(control.value, isTrue);
    expect(value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(value, isFalse);
  });
}
