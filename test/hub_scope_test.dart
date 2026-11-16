import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/hub_scope.dart';

/// Stands in for a hub section: subscribes in initState (like the calendar
/// did) and remembers whatever the first hub sent it.
class _Section extends StatefulWidget {
  const _Section({required this.hubId, required this.feeds, required this.log});
  final String hubId;
  final Map<String, StreamController<String>> feeds;
  final List<String> log;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late final String _subscribedHub;
  StreamSubscription<String>? _sub;
  String? _data;

  @override
  void initState() {
    super.initState();
    _subscribedHub = widget.hubId;
    widget.log.add('init:$_subscribedHub');
    _sub = widget.feeds[_subscribedHub]!.stream.listen(
      (v) => setState(() => _data = v),
    );
  }

  @override
  void dispose() {
    widget.log.add('dispose:$_subscribedHub');
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_data ?? 'loading', textDirection: TextDirection.ltr);
}

void main() {
  late Map<String, StreamController<String>> feeds;
  late List<String> log;

  setUp(() {
    feeds = {
      'paddy': StreamController<String>.broadcast(sync: true),
      'burroni': StreamController<String>.broadcast(sync: true),
    };
    log = [];
  });

  tearDown(() {
    for (final c in feeds.values) {
      c.close();
    }
  });

  Widget host(String hubId) => HubScoped(
    hubId: hubId,
    section: 'calendar',
    child: _Section(hubId: hubId, feeds: feeds, log: log),
  );

  testWidgets('switching hub rebuilds the section with fresh data', (
    tester,
  ) async {
    await tester.pumpWidget(host('paddy'));
    feeds['paddy']!.add("Paddy's shift");
    await tester.pump();
    expect(find.text("Paddy's shift"), findsOneWidget);

    await tester.pumpWidget(host('burroni'));
    // Old subscription cancelled, new one made; no stale Paddy data shown.
    expect(
      log,
      unorderedEquals(['init:paddy', 'dispose:paddy', 'init:burroni']),
    );
    expect(find.text("Paddy's shift"), findsNothing);
    expect(find.text('loading'), findsOneWidget);
    expect(feeds['paddy']!.hasListener, isFalse);

    feeds['paddy']!.add('late paddy event');
    feeds['burroni']!.add('Burroni dinner');
    await tester.pump();
    expect(find.text('Burroni dinner'), findsOneWidget);
    expect(find.text('late paddy event'), findsNothing);
  });

  testWidgets('same hub keeps state', (tester) async {
    await tester.pumpWidget(host('burroni'));
    feeds['burroni']!.add('kept');
    await tester.pump();
    await tester.pumpWidget(host('burroni'));
    expect(log, ['init:burroni']);
    expect(find.text('kept'), findsOneWidget);
  });

  test('keys differ per hub and per section', () {
    expect(HubScoped.keyFor('a', 'feed'), isNot(HubScoped.keyFor('b', 'feed')));
    expect(
      HubScoped.keyFor('a', 'feed'),
      isNot(HubScoped.keyFor('a', 'calendar')),
    );
    expect(HubScoped.keyFor('a', 'feed'), HubScoped.keyFor('a', 'feed'));
  });
}
