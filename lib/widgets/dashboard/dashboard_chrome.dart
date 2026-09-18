import 'package:flutter/material.dart';

import 'dashboard_theme.dart';

class DashboardSlide extends StatelessWidget {
  const DashboardSlide({
    super.key,
    required this.metrics,
    required this.tint,
    required this.child,
    this.padding,
    this.gradient,
  });

  final DashboardMetrics metrics;
  final Color tint;
  final Widget child;
  final EdgeInsets? padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient ?? DashboardTheme.slideGradient(tint),
      ),
      child: Padding(
        padding: padding ?? metrics.slidePadding,
        child: child,
      ),
    );
  }
}

class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader({
    super.key,
    required this.metrics,
    required this.icon,
    required this.tint,
    required this.title,
    this.trailing,
  });

  final DashboardMetrics metrics;
  final IconData icon;
  final Color tint;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(metrics.isCompact ? 10 : 12),
          decoration: BoxDecoration(
            color: DashboardTheme.fade(tint, 0.14),
            borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
          ),
          child: Icon(icon, color: tint, size: metrics.iconSize),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: DashboardTheme.ink,
              fontSize: metrics.titleSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class DashboardGlassCard extends StatelessWidget {
  const DashboardGlassCard({
    super.key,
    required this.tint,
    required this.child,
    this.padding,
    this.emphasized = false,
  });

  final Color tint;
  final Widget child;
  final EdgeInsets? padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: DashboardTheme.glassCard(tint: tint, emphasized: emphasized),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(24),
        child: child,
      ),
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tint = DashboardTheme.accent,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color tint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: DashboardTheme.fade(tint, 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTheme.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTheme.inkMuted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardLoadingView extends StatelessWidget {
  const DashboardLoadingView({super.key, this.label = 'Getting your home ready…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DashboardTheme.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: DashboardTheme.accent,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: const TextStyle(
                color: DashboardTheme.inkMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPageDots extends StatelessWidget {
  const DashboardPageDots({
    super.key,
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final bool active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? DashboardTheme.accent
                : DashboardTheme.fade(Colors.white, 0.22),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
