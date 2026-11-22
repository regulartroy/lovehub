import 'package:flutter/material.dart';

import '../../services/memory_photo_average_color.dart';
import 'dashboard_theme.dart';

/// Rounded photo well whose background tracks the average colour of [url].
///
/// The colour fades when the memory changes. Until a colour is known, and
/// when the read fails, the well stays on [fallbackMemoryPhotoBackground]
/// (or the previous photo's colour while the next average is loading).
class MemoryPhotoBackdrop extends StatefulWidget {
  const MemoryPhotoBackdrop({
    super.key,
    required this.url,
    required this.builder,
    this.cache,
    this.duration = const Duration(milliseconds: 600),
    this.fallback = fallbackMemoryPhotoBackground,
  });

  final String url;
  final Widget Function(BuildContext context, Color overlayColor) builder;
  final MemoryPhotoAverageColorCache? cache;
  final Duration duration;
  final Color fallback;

  @override
  State<MemoryPhotoBackdrop> createState() => _MemoryPhotoBackdropState();
}

class _MemoryPhotoBackdropState extends State<MemoryPhotoBackdrop> {
  late Color _color;
  late Color _overlay;

  MemoryPhotoAverageColorCache get _cache =>
      widget.cache ?? memoryPhotoAverageColors;

  @override
  void initState() {
    super.initState();
    _apply(_cachedColor(widget.url), animate: false);
    _load(widget.url);
  }

  @override
  void didUpdateWidget(MemoryPhotoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url && oldWidget.cache == widget.cache) {
      return;
    }
    final cached = _cachedColor(widget.url);
    if (cached != null || _cache.contains(widget.url)) {
      _apply(cached);
    }
    _load(widget.url);
  }

  Color? _cachedColor(String url) {
    if (!_cache.contains(url)) return null;
    return _cache[url];
  }

  void _apply(Color? color, {bool animate = true}) {
    final next = color ?? widget.fallback;
    if (!animate) {
      _color = next;
      _overlay = overlayColorOn(next);
      return;
    }
    if (next == _color) return;
    setState(() {
      _color = next;
      _overlay = overlayColorOn(next);
    });
  }

  Future<void> _load(String url) async {
    if (_cache.contains(url)) return;
    final color = await _cache.colorFor(url);
    if (!mounted || widget.url != url) return;
    _apply(color);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: widget.duration,
      curve: Curves.easeInOut,
      decoration: memoryPhotoFrameDecoration(_color),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
        child: widget.builder(context, _overlay),
      ),
    );
  }
}

BoxDecoration memoryPhotoFrameDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
    boxShadow: const [
      BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10)),
    ],
  );
}
