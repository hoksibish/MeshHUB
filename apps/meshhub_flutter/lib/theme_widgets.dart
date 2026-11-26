import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Palette-driven radio instrumentation for Retro 82. No synthetic telemetry.
class MeshThemeBackdrop extends StatelessWidget {
  const MeshThemeBackdrop({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Theme.of(context).scaffoldBackgroundColor,
          Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
        ],
      ),
    ),
    child: child,
  );
}

class MeshThemeStatusStrip extends StatelessWidget {
  const MeshThemeStatusStrip({
    required this.section,
    required this.connected,
    this.preset,
    super.key,
  });
  final String section;
  final bool connected;
  final String? preset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxWidth < 590;
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(Icons.radio, color: colors.primary, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  compact
                      ? section.toUpperCase()
                      : 'MESHHUB / ${section.toUpperCase()}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (!compact && preset != null) ...[
                Text(
                  preset!,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Text(
                connected ? 'LINK UP' : 'NO LINK',
                style: TextStyle(color: colors.secondary, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MeshThemePanel extends StatelessWidget {
  const MeshThemePanel({
    required this.child,
    this.active = false,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });
  final Widget child;
  final bool active;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (active ? colors.primary : colors.outlineVariant).withValues(
            alpha: active ? 0.45 : 0.4,
          ),
        ),
      ),
      padding: padding,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class MeshThemeMetric extends StatelessWidget {
  const MeshThemeMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    super.key,
  });
  final IconData icon;
  final String label, value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 186,
      child: MeshThemePanel(
        active: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.secondary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlight ? colors.primary : colors.onSurface,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MeshThemeLinkScope extends StatelessWidget {
  const MeshThemeLinkScope({
    required this.connected,
    required this.channelCount,
    required this.onOpenRadios,
    super.key,
  });
  final bool connected;
  final int channelCount;
  final VoidCallback onOpenRadios;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: math.min(304, MediaQuery.sizeOf(context).width - 40),
      child: MeshThemePanel(
        active: connected,
        child: Row(
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 36,
              color: colors.secondary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RADIO / LINK',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    connected ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$channelCount CH / CONFIGURED',
                    style: const TextStyle(fontSize: 10),
                  ),
                  TextButton(
                    onPressed: onOpenRadios,
                    child: const Text('RADIOS >'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MeshThemeHeading extends StatelessWidget {
  const MeshThemeHeading(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: colors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Container(width: 36, height: 3, color: colors.primary),
            Expanded(
              child: Container(
                height: 1,
                color: colors.secondary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
