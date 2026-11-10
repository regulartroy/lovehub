import 'package:flutter/material.dart';

import '../services/member_profile.dart';

/// Shared circular member photo used by Home, Dashboard, and Calendar.
///
/// Uses the raw stored URL with [Image.network]. On Flutter web (CanvasKit),
/// [WebHtmlElementStrategy.prefer] loads an HTML `<img>` / [WebImageInfo]
/// instead of an XHR byte-fetch. Many `googleusercontent` profile URLs have
/// no CORS headers; the byte-fetch 403s and the old `errorBuilder` drew the
/// same initial as a missing URL.
///
/// Do not set [Image.network] headers on web: a non-empty header map forces
/// the XHR path. Page-level `<meta name="referrer" content="no-referrer">`
/// is enough — do not rewrite Google photo URLs.
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

    final fallback = _FallbackFace(
      radius: radius,
      backgroundColor: bg,
      foregroundColor: fg,
      initial: initial,
      icon: icon,
    );

    Widget child = fallback;
    if (isUsablePhotoUrl(photoURL) && icon == null) {
      child = Image.network(
        photoURL!.trim(),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) => fallback,
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
