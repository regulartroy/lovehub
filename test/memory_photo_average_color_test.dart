import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/memory_photo_average_color.dart';
import 'package:lovehub/widgets/hub_memory_image.dart';

void main() {
  const url =
      'https://firebasestorage.googleapis.com/v0/b/lovehub-26107.firebasestorage.app/o/hubs%2Fhome%2Fphotos%2Fa.jpg?alt=media&token=abc';

  test('colour provider uses a small xhr decode and leaves the url alone', () {
    final provider = memoryPhotoColorImageProvider(url);
    expect(provider, isA<ResizeImage>());
    final resized = provider as ResizeImage;
    expect(resized.width, memoryPhotoColorSampleSize);
    expect(resized.height, isNull);
    final network = resized.imageProvider as NetworkImage;
    expect(network.url, url);
    expect(network.headers, isNull);
    expect(network.webHtmlElementStrategy, WebHtmlElementStrategy.never);
    expect(
      hubMemoryImageProvider(url).webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );
  });

  test('average of a solid colour buffer is that colour', () {
    final pixels = Uint8List.fromList([200, 40, 10, 255, 200, 40, 10, 255]);
    expect(
      averageColorFromRgba(pixels, width: 2, height: 1),
      const Color(0xFFC8280A),
    );
  });

  test('average skips transparent pixels and means mixed colours', () {
    final pixels = Uint8List.fromList([
      255,
      0,
      0,
      255,
      0,
      0,
      255,
      255,
      1,
      2,
      3,
      0,
      0,
      0,
      0,
      0,
    ]);
    expect(
      averageColorFromRgba(pixels, width: 2, height: 2),
      const Color(0xFF800080),
    );
  });

  test('average returns null for empty or fully transparent buffers', () {
    expect(averageColorFromRgba(Uint8List(0), width: 0, height: 0), isNull);
    expect(
      averageColorFromRgba(
        Uint8List.fromList([1, 2, 3, 0]),
        width: 1,
        height: 1,
      ),
      isNull,
    );
    expect(
      averageColorFromRgba(Uint8List.fromList([1, 2, 3]), width: 1, height: 1),
      isNull,
    );
  });

  test('overlay flips to dark ink on a light background', () {
    expect(overlayColorOn(const Color(0xFF101010)), const Color(0x8AFFFFFF));
    expect(overlayColorOn(const Color(0xFFF5E6C8)), const Color(0x8A000000));
  });

  testWidgets('average colour can be read from a decoded still image', (
    tester,
  ) async {
    final color = await tester.runAsync(() async {
      final image = await _solidImage(
        const Color(0xFF336699),
        width: 8,
        height: 4,
      );
      try {
        return await averageColorFromImageProvider(_TestImageProvider(image));
      } finally {
        image.dispose();
      }
    });
    expect(color, const Color(0xFF336699));
  });

  test('cache remembers a colour and does not decode again', () async {
    var calls = 0;
    final cache = MemoryPhotoAverageColorCache(
      decode: (requested) async {
        calls++;
        expect(requested, url);
        return const Color(0xFF112233);
      },
    );

    expect(cache.contains(url), isFalse);
    expect(await cache.colorFor(url), const Color(0xFF112233));
    expect(await cache.colorFor(url), const Color(0xFF112233));
    expect(calls, 1);
    expect(cache.contains(url), isTrue);
    expect(cache[url], const Color(0xFF112233));
  });

  test('cache stores a failed read as null and does not retry', () async {
    var calls = 0;
    final cache = MemoryPhotoAverageColorCache(
      decode: (_) async {
        calls++;
        throw Exception('cors');
      },
    );

    expect(await cache.colorFor(url), isNull);
    expect(await cache.colorFor(url), isNull);
    expect(calls, 1);
    expect(cache.contains(url), isTrue);
    expect(cache[url], isNull);
  });

  test('in-flight reads share one decode', () async {
    var calls = 0;
    final started = Completer<void>();
    final release = Completer<Color?>();
    final cache = MemoryPhotoAverageColorCache(
      decode: (_) {
        calls++;
        started.complete();
        return release.future;
      },
    );

    final first = cache.colorFor(url);
    final second = cache.colorFor(url);
    await started.future;
    release.complete(const Color(0xFF445566));
    expect(await first, const Color(0xFF445566));
    expect(await second, const Color(0xFF445566));
    expect(calls, 1);
  });
}

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  const _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_TestImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: image.clone())),
    );
  }
}

Future<ui.Image> _solidImage(
  Color color, {
  int width = 4,
  int height = 4,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}
