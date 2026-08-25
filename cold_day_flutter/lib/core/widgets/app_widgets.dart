import 'package:flutter/material.dart';

import 'package:cold_day_flutter/core/theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, textAlign: TextAlign.center);
    final button = outlined
        ? (icon == null
              ? OutlinedButton(onPressed: onPressed, child: child)
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: child,
                ))
        : (icon == null
              ? FilledButton(onPressed: onPressed, child: child)
              : FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: child,
                ));
    return Semantics(button: true, label: label, child: button);
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = color ?? _statusColor(scheme, label);
    final textColor = color == null
        ? _statusTextColor(scheme, label)
        : badgeColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme scheme, String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('complet') || normalized.contains('verific')) {
      return scheme.tertiary;
    }
    if (normalized.contains('rechaz') || normalized.contains('error')) {
      return scheme.error;
    }
    if (normalized.contains('pend') || normalized.contains('bidding')) {
      return scheme.secondary;
    }
    return scheme.primary;
  }

  Color _statusTextColor(ColorScheme scheme, String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('complet') || normalized.contains('verific')) {
      return scheme.onTertiaryContainer;
    }
    if (normalized.contains('rechaz') || normalized.contains('error')) {
      return scheme.onErrorContainer;
    }
    if (normalized.contains('pend') || normalized.contains('bidding')) {
      return scheme.onSecondaryContainer;
    }
    return scheme.primary;
  }
}

class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 1240,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width >= 905 ? 24 : 16,
        ),
        child: child,
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class AppTimelineEvent {
  const AppTimelineEvent({
    required this.title,
    required this.subtitle,
    required this.status,
    this.icon = Icons.circle,
    this.isCurrent = false,
  });

  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final bool isCurrent;
}

/// A responsive, data-only timeline for request history and operational events.
class AppTimeline extends StatelessWidget {
  const AppTimeline({super.key, required this.events});

  final List<AppTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < events.length; index++)
          _TimelineRow(
            event: events[index],
            isLast: index == events.length - 1,
            scheme: scheme,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isLast,
    required this.scheme,
  });

  final AppTimelineEvent event;
  final bool isLast;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final marker = event.isCurrent ? scheme.secondaryContainer : scheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: marker,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 4),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 3),
                  ],
                ),
                child: Icon(event.icon, size: 12, color: scheme.onPrimary),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 72,
                  color: scheme.surfaceContainerHighest,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      event.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    StatusBadge(label: event.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  event.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.message,
    required this.action,
    this.icon = Icons.cloud_off,
  });

  final String message;
  final VoidCallback action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Reintentar',
                onPressed: action,
                icon: Icons.refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
