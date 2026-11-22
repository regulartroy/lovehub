import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/memory_photo_average_color.dart';
import 'package:lovehub/widgets/dashboard/memory_photo_backdrop.dart';

void main() {
  const urlA =
      'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/hubs%2Fhome%2Fphotos%2Fa.jpg?alt=media&token=a';
  const urlB =
      'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/hubs%2Fhome%2Fphotos%2Fb.jpg?alt=media&token=b';

  testWidgets('uses the fallback colour while the average is loading', (
    tester,
  ) async {
    final started = Completer<void>();
    final release = Completer<Color?>();
    final cache = MemoryPhotoAverageColorCache(
      decode: (_) {
        started.complete();
        return release.future;
      },
    );

    await tester.pumpWidget(
      _harness(
        url: urlA,
        cache: cache,
        duration: const Duration(milliseconds: 200),
      ),
    );

    expect(_frameColor(tester), fallbackMemoryPhotoBackground);
    expect(
      _overlayColor(tester),
      overlayColorOn(fallbackMemoryPhotoBackground),
    );
    await started.future;
    release.complete(const Color(0xFFF5E6C8));
    await tester.pumpAndSettle();

    expect(_frameColor(tester), const Color(0xFFF5E6C8));
    expect(_overlayColor(tester), overlayColorOn(const Color(0xFFF5E6C8)));
    expect(_overlayColor(tester), const Color(0x8A000000));
  });

  testWidgets('keeps the previous colour until a new average arrives', (
    tester,
  ) async {
    final releaseB = Completer<Color?>();
    var calls = 0;
    final cache = MemoryPhotoAverageColorCache(
      decode: (url) {
        calls++;
        if (url == urlA) return Future<Color?>.value(const Color(0xFF224466));
        return releaseB.future;
      },
    );

    await tester.pumpWidget(
      _harness(url: urlA, cache: cache, duration: Duration.zero),
    );
    await tester.pumpAndSettle();
    expect(_frameColor(tester), const Color(0xFF224466));

    await tester.pumpWidget(
      _harness(url: urlB, cache: cache, duration: Duration.zero),
    );
    await tester.pump();
    expect(_frameColor(tester), const Color(0xFF224466));

    releaseB.complete(const Color(0xFF99AABB));
    await tester.pumpAndSettle();
    expect(_frameColor(tester), const Color(0xFF99AABB));
    expect(calls, 2);
  });

  testWidgets('falls back to black when the colour read fails', (tester) async {
    final cache = MemoryPhotoAverageColorCache(decode: (_) async => null);
    cache.seed(urlA, const Color(0xFF336699));

    await tester.pumpWidget(
      _harness(url: urlA, cache: cache, duration: Duration.zero),
    );
    expect(_frameColor(tester), const Color(0xFF336699));

    await tester.pumpWidget(
      _harness(url: urlB, cache: cache, duration: Duration.zero),
    );
    await tester.pumpAndSettle();
    expect(_frameColor(tester), fallbackMemoryPhotoBackground);
    expect(_overlayColor(tester), const Color(0x8AFFFFFF));
  });

  testWidgets('uses a cached colour on the first frame', (tester) async {
    var calls = 0;
    final cache = MemoryPhotoAverageColorCache(
      decode: (_) {
        calls++;
        return Future<Color?>.value(const Color(0xFF010203));
      },
    );
    cache.seed(urlA, const Color(0xFFCC5533));

    await tester.pumpWidget(
      _harness(url: urlA, cache: cache, duration: Duration.zero),
    );

    expect(_frameColor(tester), const Color(0xFFCC5533));
    expect(calls, 0);
  });
}

Widget _harness({
  required String url,
  required MemoryPhotoAverageColorCache cache,
  required Duration duration,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MemoryPhotoBackdrop(
        url: url,
        cache: cache,
        duration: duration,
        builder: (context, overlayColor) {
          return ColoredBox(
            key: const Key('memory-photo-overlay'),
            color: overlayColor,
            child: const SizedBox.expand(),
          );
        },
      ),
    ),
  );
}

Color _frameColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  final decoration = container.decoration as BoxDecoration;
  return decoration.color!;
}

Color _overlayColor(WidgetTester tester) {
  return tester
      .widget<ColoredBox>(find.byKey(const Key('memory-photo-overlay')))
      .color;
}
