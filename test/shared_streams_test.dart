import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/shared_streams.dart';

void main() {
  test('same key -> one source listen, latest value replayed', () async {
    final cache = SharedStreams();
    var creates = 0;
    final ctrl = StreamController<int>.broadcast();
    Stream<int> make() {
      creates++;
      return ctrl.stream;
    }

    final a = cache.watch('k', make);
    final b = cache.watch('k', make);
    expect(identical(a, b), isTrue);
    final seenA = <int>[];
    a.listen(seenA.add);
    await Future<void>.delayed(Duration.zero);
    ctrl.add(1);
    await Future<void>.delayed(Duration.zero);
    final seenB = <int>[];
    b.listen(seenB.add);
    await Future<void>.delayed(Duration.zero);
    expect(seenA, [1]);
    expect(seenB, [1], reason: 'late listener gets the latest snapshot');
    expect(creates, 1);
    cache.evictPrefix('k', keep: 'k');
    expect(cache.activeSources, 1);
    cache.evictPrefix('k');
    expect(cache.activeSources, 0);
    cache.dispose();
    await ctrl.close();
  });

  testWidgets('rebuilding a StreamBuilder 100x does not add subscriptions', (
    t,
  ) async {
    final cache = SharedStreams();
    final ctrl = StreamController<int>.broadcast();
    var listens = 0;
    final source = ctrl.stream.transform(
      StreamTransformer<int, int>.fromBind((s) {
        listens++;
        return s;
      }),
    );
    final tick = ValueNotifier(0);
    await t.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, v, __) => StreamBuilder<int>(
            stream: cache.watch('events:hub:2026-08-21', () => source),
            builder: (_, s) => Text('${s.data} $v'),
          ),
        ),
      ),
    );
    ctrl.add(7);
    await t.pump();
    final before = SharedStreams.debugSourceListens;
    for (var i = 0; i < 100; i++) {
      tick.value++;
      await t.pump();
    }
    expect(find.text('7 100'), findsOneWidget);
    expect(listens, 1);
    expect(SharedStreams.debugSourceListens, before);
    expect(cache.activeSources, 1);
    cache.dispose();
    await ctrl.close();
  });
}
