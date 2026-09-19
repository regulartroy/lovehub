import 'package:flutter/material.dart';

import '../services/member_profile.dart';
import 'google_photo_image.dart';

/// Shared circular member photo used by Home, Dashboard, and Calendar.
///
/// Flutter web (CanvasKit) cannot fetch many Google profile URLs as bytes.
/// Google photos also 403 when the page sends a Referer. [GooglePhotoImage]
/// loads them as an HTML `<img referrerpolicy="no-referrer">` and retries
/// durable URL variants so errorBuilder is not the first and only outcome.
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

    final fallback = _FallbackFace(
      radius: radius,
      backgroundColor: bg,
      foregroundColor: fg,
      initial: initial,
      icon: icon,
    );

    Widget child = fallback;
    if (isUsablePhotoUrl(photoURL) && icon == null) {
      child = GooglePhotoImage(
        photoURL: photoURL!,
        size: pixelSize,
        fallback: fallback,
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
