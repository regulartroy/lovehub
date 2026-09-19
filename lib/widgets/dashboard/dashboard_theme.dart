import 'package:flutter/material.dart';

export '../../theme/calendar_colors.dart';

/// Shared tokens for the kiosk / wall-tablet dashboard.
/// Keeps slides visually related while allowing a tint per topic.
class DashboardTheme {
  static const Color canvas = Color(0xFF07070C);
  static const Color surface = Color(0xFF14141F);
  static const Color ink = Colors.white;
  static const Color inkMuted = Color(0xB3FFFFFF);
  static const Color inkFaint = Color(0x61FFFFFF);
  static const Color accent = Color(0xFFFF80AB);

  static const Color schedule = Color(0xFF82B1FF);
  static const Color tasks = Color(0xFFFFD54F);
  static const Color rota = Color(0xFFB388FF);
  static const Color shopping = Color(0xFF69F0AE);
  static const Color shoppingUrgent = Color(0xFFFF8A80);
  static const Color weather = Color(0xFF82B1FF);
  static const Color photos = Color(0xFFFFAB91);

  static const double compactBreakpoint = 700;
  static const double wideBreakpoint = 1100;

  static const double radiusLg = 24;
  static const double radiusMd = 18;
  static const double radiusSm = 12;

  static Color fade(Color color, double alpha) => color.withValues(alpha: alpha);

  static LinearGradient slideGradient(Color tint) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [fade(tint, 0.14), canvas],
    );
  }

  static BoxDecoration glassCard({required Color tint, bool emphasized = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          fade(tint, emphasized ? 0.16 : 0.10),
          fade(Colors.black, 0.72),
        ],
      ),
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(
        color: fade(tint, emphasized ? 0.42 : 0.20),
        width: emphasized ? 1.6 : 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: fade(Colors.black, 0.35),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

/// Layout numbers derived from the current viewport so phone and tablet
/// slides share one hierarchy with different density.
class DashboardMetrics {
  DashboardMetrics(this.size);

  final Size size;

  bool get isCompact => size.width < DashboardTheme.compactBreakpoint;
  bool get isWide => size.width >= DashboardTheme.wideBreakpoint;

  double get slidePadH => isCompact ? 20 : 40;
  double get slidePadTop => isCompact ? 118 : 148;
  double get slidePadBottom => isCompact ? 28 : 40;

  EdgeInsets get slidePadding => EdgeInsets.fromLTRB(
        slidePadH,
        slidePadTop,
        slidePadH,
        slidePadBottom,
      );

  double get clockSize => isCompact ? 36 : 54;
  double get secondsSize => isCompact ? 16 : 24;
  double get dateSize => isCompact ? 11 : 14;
  double get titleSize => isCompact ? 24 : 30;
  double get bodySize => isCompact ? 20 : 24;
  double get quoteSize => isCompact ? 26 : (isWide ? 42 : 34);
  double get headerPadH => isCompact ? 20 : 36;
  double get headerPadTop => isCompact ? 12 : 28;
  double get iconSize => isCompact ? 26 : 30;
}
