import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Letterbox colour used before a photo average is ready, and if decoding
/// or a web pixel read fails.
const Color fallbackMemoryPhotoBackground = Color(0xFF000000);

/// Longest edge of the downscaled decode used to average a photo.
const int memoryPhotoColorSampleSize = 32;

/// Pixel-readable provider for the average-colour path only.
///
/// Display still uses [hubMemoryImageProvider], which prefers an HTML `<img>`
/// so a CORS failure cannot blank the picture. This provider forces the XHR
/// decode Flutter needs to read pixels on web. It must not add headers, and
/// it must not rewrite the URL.
ImageProvider memoryPhotoColorImageProvider(String url) {
  return ResizeImage(
    NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.never),
    width: memoryPhotoColorSampleSize,
  );
}

/// Mean RGB of the opaque pixels in a raw RGBA buffer. Transparent pixels
/// are skipped. Returns null when the buffer is empty or fully transparent.
Color? averageColorFromRgba(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) return null;
  final expected = width * height * 4;
  if (pixels.length < expected) return null;

  var r = 0;
  var g = 0;
  var b = 0;
  var count = 0;
  for (var i = 0; i < expected; i += 4) {
    if (pixels[i + 3] == 0) continue;
    r += pixels[i];
    g += pixels[i + 1];
    b += pixels[i + 2];
    count++;
  }
  if (count == 0) return null;
  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}

/// Icon / overlay colour that stays readable on [background].
Color overlayColorOn(Color background, {double lightThreshold = 0.45}) {
  return background.computeLuminance() > lightThreshold
      ? const Color(0x8A000000)
      : const Color(0x8AFFFFFF);
}

/// Decodes [provider] and returns its average colour. A timeout, a decode
/// error, or a missing pixel buffer becomes null so the slide can keep the
/// fallback background.
Future<Color?> averageColorFromImageProvider(
  ImageProvider provider, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final stream = provider.resolve(const ImageConfiguration());
  final completer = Completer<ImageInfo>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  try {
    final info = await completer.future.timeout(timeout);
    try {
      final bytes = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (bytes == null) return null;
      return averageColorFromRgba(
        bytes.buffer.asUint8List(),
        width: info.image.width,
        height: info.image.height,
      );
    } finally {
      info.dispose();
    }
  } finally {
    stream.removeListener(listener);
  }
}

Future<Color?> decodeMemoryPhotoAverageColor(String url) {
  return averageColorFromImageProvider(memoryPhotoColorImageProvider(url));
}

/// Session cache of average colours, keyed by the photo download URL.
///
/// A failed read is cached as null so a CORS or decode problem is not retried
/// on every rebuild.
class MemoryPhotoAverageColorCache {
  MemoryPhotoAverageColorCache({Future<Color?> Function(String url)? decode})
    : _decode = decode ?? decodeMemoryPhotoAverageColor;

  final Future<Color?> Function(String url) _decode;
  final Map<String, Color?> _cache = {};
  final Map<String, Future<Color?>> _inflight = {};

  bool contains(String url) => _cache.containsKey(url);

  /// The cached colour, or null when the URL is unknown or the read failed.
  Color? operator [](String url) => _cache[url];

  Future<Color?> colorFor(String url) {
    if (_cache.containsKey(url)) return Future<Color?>.value(_cache[url]);
    return _inflight.putIfAbsent(url, () async {
      Color? color;
      try {
        color = await _decode(url);
      } catch (_) {
        color = null;
      }
      _cache[url] = color;
      _inflight.remove(url);
      return color;
    });
  }

  @visibleForTesting
  void seed(String url, Color? color) {
    _cache[url] = color;
  }
}

/// Shared cache so a later rotation of the same memory is instant.
final MemoryPhotoAverageColorCache memoryPhotoAverageColors =
    MemoryPhotoAverageColorCache();
