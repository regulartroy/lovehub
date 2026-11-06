import 'package:flutter/material.dart';

/// One claim per URL. A slide rebuild must not report the same failure twice.
class HubMemoryLoadGate {
  String? _url;

  bool claim(String url) {
    if (_url == url) return false;
    _url = url;
    return true;
  }

  void reset() {
    _url = null;
  }
}

/// The image provider used for a hub memory.
///
/// Flutter's default web [NetworkImage] fetches bytes with XHR
/// ([WebHtmlElementStrategy.never]). That fails when the host sends no CORS
/// headers, and the dashboard then draws "Photo could not load". Member
/// photos already prefer an HTML `<img>`, which can paint the same URL
/// without reading pixels. Headers stay empty: a non-empty map forces the
/// XHR path. The URL is not rewritten and is not sent through a proxy.
NetworkImage hubMemoryImageProvider(String url) {
  return NetworkImage(
    url,
    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
  );
}

/// Drops one failed entry so a later rotation can try the URL again.
void evictHubMemoryImage(String url) {
  PaintingBinding.instance.imageCache.evict(hubMemoryImageProvider(url));
}

/// Hub gallery / dashboard photo. No auth headers and no retry of its own.
class HubMemoryImage extends StatefulWidget {
  const HubMemoryImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoadError,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Called once per [url] after the frame, never during build.
  final ValueChanged<String>? onLoadError;

  @override
  State<HubMemoryImage> createState() => _HubMemoryImageState();
}

class _HubMemoryImageState extends State<HubMemoryImage> {
  final HubMemoryLoadGate _gate = HubMemoryLoadGate();

  @override
  void didUpdateWidget(HubMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _gate.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: hubMemoryImageProvider(widget.url),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: (context, error, stackTrace) {
        _reportOnce(widget.url);
        return widget.errorBuilder?.call(context, error, stackTrace) ??
            const SizedBox.shrink();
      },
    );
  }

  void _reportOnce(String url) {
    if (url.isEmpty || widget.onLoadError == null) return;
    if (!_gate.claim(url)) return;
    final report = widget.onLoadError!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.url != url) return;
      report(url);
    });
  }
}
