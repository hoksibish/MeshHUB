import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Original HUD art inspired by retro radio instrumentation; no synthetic telemetry.
abstract final class TacticalHudColors {
  static const background = Color(0xff07111d);
  static const panel = Color(0xff102235);
  static const cyan = Color(0xff29d7ff);
  static const teal = Color(0xff53e0d2);
  static const orange = Color(0xffff9f2f);
  static const text = Color(0xffd7f6ff);
  static const muted = Color(0xff8db8c7);
}

class TacticalHudBackdrop extends StatelessWidget {
  const TacticalHudBackdrop({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _HudGridPainter()),
        ),
      ),
      Positioned.fill(child: child),
    ],
  );
}

class TacticalHudStatusStrip extends StatelessWidget {
  const TacticalHudStatusStrip({
    required this.section,
    required this.connected,
    this.preset,
    super.key,
  });
  final String section;
  final bool connected;
  final String? preset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxWidth < 590;
      return Container(
        height: compact ? 44 : 55,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22),
        decoration: const BoxDecoration(
          color: Color(0xee0b1b2b),
          border: Border(
            bottom: BorderSide(color: TacticalHudColors.cyan, width: 0.8),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.radar, color: TacticalHudColors.orange, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                compact ? section.toUpperCase() : 'MESHHUB / ${section.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w700,
                  color: TacticalHudColors.cyan,
                ),
              ),
            ),
            const Spacer(),
            if (!compact && preset != null) ...[
              Text(
                preset!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: TacticalHudColors.muted,
                ),
              ),
              const SizedBox(width: 18),
            ],
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: connected
                    ? TacticalHudColors.teal
                    : TacticalHudColors.orange,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connected ? 'LINK UP' : 'NO LINK',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 1,
                color: TacticalHudColors.text,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Angular panels are interactive containers, not fake gauges or status graphs.
class TacticalHudPanel extends StatelessWidget {
  const TacticalHudPanel({
    required this.child,
    this.active = false,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });
  final Widget child;
  final bool active;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _HudFramePainter(active: active),
    child: Padding(padding: padding, child: child),
  );
}

class TacticalHudMetric extends StatelessWidget {
  const TacticalHudMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    super.key,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 212,
    child: TacticalHudPanel(
      active: highlight,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: highlight
                    ? TacticalHudColors.orange
                    : TacticalHudColors.cyan,
              ),
              const Spacer(),
              const Text(
                'SYS // LIVE',
                style: TextStyle(
                  color: TacticalHudColors.muted,
                  fontFamily: 'monospace',
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: highlight
                  ? TacticalHudColors.orange
                  : TacticalHudColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            maxLines: 2,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: TacticalHudColors.muted,
              fontSize: 11,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    ),
  );
}

class TacticalHudHeading extends StatelessWidget {
  const TacticalHudHeading(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(width: 4, height: 27, color: TacticalHudColors.orange),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TacticalHudColors.cyan,
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: const TextStyle(
            color: TacticalHudColors.muted,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ],
      const SizedBox(height: 12),
      Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              TacticalHudColors.orange.withValues(alpha: 0.9),
              TacticalHudColors.cyan.withValues(alpha: 0.4),
              TacticalHudColors.cyan.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    ],
  );
}

class _HudFramePainter extends CustomPainter {
  const _HudFramePainter({required this.active});
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bevel = math.min(13.0, math.min(size.width, size.height) / 5);
    final path = Path()
      ..moveTo(bevel, 0)
      ..lineTo(size.width - bevel, 0)
      ..lineTo(size.width, bevel)
      ..lineTo(size.width, size.height - bevel)
      ..lineTo(size.width - bevel, size.height)
      ..lineTo(bevel, size.height)
      ..lineTo(0, size.height - bevel)
      ..lineTo(0, bevel)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = TacticalHudColors.panel.withValues(alpha: 0.96)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = (active ? TacticalHudColors.orange : TacticalHudColors.cyan)
            .withValues(alpha: active ? 0.88 : 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.5 : 0.9,
    );
    final corner = Paint()
      ..color = active ? TacticalHudColors.orange : TacticalHudColors.teal
      ..strokeWidth = 2;
    final length = math.min(28.0, size.width / 5);
    canvas.drawLine(Offset(bevel, 0), Offset(bevel + length, 0), corner);
    canvas.drawLine(
      Offset(size.width, size.height - bevel - length),
      Offset(size.width, size.height - bevel),
      corner,
    );
    canvas.drawCircle(
      Offset(size.width - bevel / 2, bevel / 2),
      2,
      Paint()..color = TacticalHudColors.orange,
    );
  }

  @override
  bool shouldRepaint(_HudFramePainter old) => old.active != active;
}

class _HudGridPainter extends CustomPainter {
  const _HudGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = TacticalHudColors.cyan.withValues(alpha: 0.055)
      ..strokeWidth = 0.6;
    for (var x = 0.0; x <= size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final arc = Paint()
      ..color = TacticalHudColors.orange.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = Offset(size.width - 80, 92);
    for (final radius in [28.0, 45.0, 62.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.15,
        math.pi * 0.65,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_HudGridPainter old) => false;
}
