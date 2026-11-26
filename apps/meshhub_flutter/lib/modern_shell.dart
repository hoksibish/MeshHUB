import 'package:material_ui/material_ui.dart';

class MeshWelcomeCard extends StatelessWidget {
  const MeshWelcomeCard({
    required this.connected,
    required this.onConnect,
    required this.onChannels,
    super.key,
  });
  final bool connected;
  final VoidCallback onConnect, onChannels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth > 650;
        return Container(
          padding: EdgeInsets.all(wide ? 32 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.12),
                  colors.surface,
                ),
                colors.surface,
                Color.alphaBlend(
                  colors.secondary.withValues(alpha: 0.1),
                  colors.surface,
                ),
              ],
            ),
            border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR OFF-GRID WORKSPACE',
                      style: TextStyle(
                        color: colors.primary,
                        letterSpacing: 1.8,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your mesh,\none place.',
                      style: TextStyle(
                        fontSize: wide ? 42 : 32,
                        height: 1.08,
                        letterSpacing: -1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'A little closer, even when you’re off-grid.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: onConnect,
                          icon: const Icon(Icons.bluetooth, size: 18),
                          label: Text(
                            connected ? 'Manage radio' : 'Connect a radio',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onChannels,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Explore channels'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 24),
                // Decorative brand artwork, not a map or measured network graph.
                Container(
                  width: 164,
                  height: 164,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.13),
                      width: 16,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: 0.12),
                      border: Border.all(
                        color: colors.secondary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      size: 52,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class MeshSummaryCard extends StatelessWidget {
  const MeshSummaryCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
    required this.width,
    super.key,
  });
  final IconData icon;
  final String value, label;
  final Color accent;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = width < 150;
    return Container(
      width: width,
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 18 : 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: compact ? 10 : 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class MeshActivityEmpty extends StatelessWidget {
  const MeshActivityEmpty({
    required this.connected,
    required this.onAction,
    super.key,
  });
  final bool connected;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 28,
              color: colors.secondary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'A conversation starts here',
            style: TextStyle(
              fontSize: 18,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            connected ? 'Open a channel to follow your community.' : 'Connect a MeshCore radio to discover channels and receive messages.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(connected ? 'Browse channels' : 'Set up your radio'),
          ),
        ],
      ),
    );
  }
}
