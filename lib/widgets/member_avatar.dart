import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/member_profile.dart';

/// Shared circular member photo used by Home, Dashboard, and Calendar.
///
/// Flutter web (CanvasKit) cannot fetch many Google profile URLs as bytes
/// because `lh3.googleusercontent.com` often omits CORS. We prefer an HTML
/// `<img>` on web, request a concrete `sz` / `=sNN-c`, and never send custom
/// headers (headers force the byte-fetch path).
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    this.photoURL,
    this.name,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.icon,
  });

  final String? photoURL;
  final String? name;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BoxBorder? border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.primary;
    final fg = foregroundColor ?? Colors.white;
    final initial = memberInitial(name);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final pixelSize = (radius * 2 * dpr).round().clamp(64, 256);
    final url = hardenPhotoUrl(photoURL, size: pixelSize);

    final fallback = _FallbackFace(
      radius: radius,
      backgroundColor: bg,
      foregroundColor: fg,
      initial: initial,
      icon: icon,
    );

    Widget child = fallback;
    if (isUsablePhotoUrl(url) && icon == null) {
      child = Image.network(
        url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        // Headers would disable HTML-element loading on web.
        headers: kIsWeb ? null : const {'Accept': 'image/*'},
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('MemberAvatar failed to load $url: $error');
          return fallback;
        },
      );
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _FallbackFace extends StatelessWidget {
  const _FallbackFace({
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.initial,
    this.icon,
  });

  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final String initial;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: icon != null
            ? Icon(icon, color: foregroundColor, size: radius * 1.2)
            : Text(
                initial,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: radius * 0.85,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
