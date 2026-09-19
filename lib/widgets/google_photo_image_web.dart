import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/member_profile.dart';

/// Web loader: a real HTML `<img>` with `referrerPolicy=no-referrer`.
///
/// Live LoveHub is CanvasKit. `Image.network` fetches bytes (CORS) and
/// googleusercontent often 403s when the page sends a Referer. Tom's photo
/// can still load; Maria's stored URL is requested and fails. An HTML img
/// that never sends Referer is the reliable path.
class GooglePhotoImage extends StatefulWidget {
  const GooglePhotoImage({
    super.key,
    required this.photoURL,
    required this.fallback,
    this.size = 128,
  });

  final String photoURL;
  final Widget fallback;
  final int size;

  @override
  State<GooglePhotoImage> createState() => _GooglePhotoImageState();
}

class _GooglePhotoImageState extends State<GooglePhotoImage> {
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = googlePhotoUrlCandidates(widget.photoURL, size: widget.size);
  }

  @override
  void didUpdateWidget(covariant GooglePhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoURL != widget.photoURL ||
        oldWidget.size != widget.size) {
      _candidates = googlePhotoUrlCandidates(
        widget.photoURL,
        size: widget.size,
      );
      _index = 0;
    }
  }

  void _advance() {
    if (!mounted) return;
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates.isEmpty || _index >= _candidates.length) {
      return widget.fallback;
    }
    final url = _candidates[_index];
    return HtmlElementView.fromTagName(
      key: ValueKey(url),
      tagName: 'img',
      onElementCreated: (Object element) {
        final img = element as web.HTMLImageElement;
        // Set policy BEFORE src so the photo request has no Referer.
        img.referrerPolicy = 'no-referrer';
        img.alt = '';
        final style = img.style;
        style.setProperty('width', '100%');
        style.setProperty('height', '100%');
        style.setProperty('object-fit', 'cover');
        style.setProperty('border-radius', '50%');
        style.setProperty('display', 'block');
        img.addEventListener(
          'error',
          (web.Event _) {
            style.setProperty('visibility', 'hidden');
            _advance();
          }.toJS,
        );
        img.src = url;
      },
    );
  }
}
