import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';
import 'package:meshhub_domain/testing.dart';

import 'field_session.dart';
import 'linux_meshcore_ble.dart';
import 'tactical_hud.dart';

void main() => runApp(const MeshHubApp());

enum MeshHubTheme { light, dark, tactical }

class MeshHubApp extends StatefulWidget {
  const MeshHubApp({super.key, this.fieldSession});

  /// Allows a synthetic field session in widget tests; production uses BlueZ.
  final MeshCoreFieldSession? fieldSession;

  @override
  State<MeshHubApp> createState() => _MeshHubAppState();
}

class _MeshHubAppState extends State<MeshHubApp> {
  MeshHubTheme theme = MeshHubTheme.dark;
  static const _canvas = Color(0xff101923);
  static const _surface = Color(0xff1b2834);
  static const _meshCoreAccent = Color(0xff55d6cb);
  static const _meshtasticAccent = Color(0xffb6df62);
  static const _tacticalAccent = TacticalHudColors.cyan;
  Color get _pageBackground => switch (theme) {
    MeshHubTheme.light => const Color(0xfff3f7f9),
    MeshHubTheme.dark => _canvas,
    MeshHubTheme.tactical => TacticalHudColors.background,
  };
  Color get _panelBackground => switch (theme) {
    MeshHubTheme.light => const Color(0xffffffff),
    MeshHubTheme.dark => _surface,
    MeshHubTheme.tactical => TacticalHudColors.panel,
  };
  Color get _accent => switch (theme) {
    MeshHubTheme.light => const Color(0xff087e83),
    MeshHubTheme.dark => _meshCoreAccent,
    MeshHubTheme.tactical => TacticalHudColors.cyan,
  };
  MeshProtocol? filter;
  int destination = 0;
  late final MeshCoreFieldSession field;
  final messageInput = TextEditingController();
  final channelMessageInput = TextEditingController();
  final keyPrefixInput = TextEditingController();
  int? selectedChannel;
  String? _selectedChannelName;
  bool showExamples = false;
  bool verifiedDestination = false;

  @override
  void initState() {
    super.initState();
    field = widget.fieldSession ?? MeshCoreFieldSession();
    field.addListener(_refresh);
  }

  void _refresh() {
    if (!field.connected || field.channelsLoading) {
      verifiedDestination = false;
    }
    if (selectedChannel != null && !field.channelsLoading) {
      final matching = field.channels.where((c) => c.index == selectedChannel);
      if (matching.isEmpty || matching.first.name != _selectedChannelName) {
        selectedChannel = null;
        _selectedChannelName = null;
        channelMessageInput.clear();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    field.removeListener(_refresh);
    if (widget.fieldSession == null) {
      unawaited(field.disconnect().whenComplete(field.dispose));
    }
    messageInput.dispose();
    channelMessageInput.dispose();
    keyPrefixInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (theme) {
      MeshHubTheme.light => const Color(0xff087e83),
      MeshHubTheme.dark => _meshCoreAccent,
      MeshHubTheme.tactical => _tacticalAccent,
    };
    final mode = theme == MeshHubTheme.light
        ? Brightness.light
        : Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: color, brightness: mode);
    final themedScheme = switch (theme) {
      MeshHubTheme.tactical => scheme.copyWith(
        primary: TacticalHudColors.cyan,
        onPrimary: TacticalHudColors.background,
        secondary: TacticalHudColors.orange,
        onSecondary: TacticalHudColors.background,
        surface: TacticalHudColors.panel,
        onSurface: TacticalHudColors.text,
        onSurfaceVariant: TacticalHudColors.muted,
        outline: TacticalHudColors.cyan.withValues(alpha: 0.5),
        outlineVariant: TacticalHudColors.cyan.withValues(alpha: 0.25),
      ),
      MeshHubTheme.dark => scheme.copyWith(
        primary: _meshCoreAccent,
        onPrimary: _canvas,
        surface: _surface,
        onSurface: const Color(0xffedf4f6),
        onSurfaceVariant: const Color(0xffa8bdc6),
        outline: const Color(0xff4a606b),
        outlineVariant: const Color(0xff344752),
      ),
      MeshHubTheme.light => scheme.copyWith(
        primary: const Color(0xff087e83),
        onPrimary: const Color(0xffffffff),
        surface: const Color(0xffffffff),
        onSurface: const Color(0xff172d36),
        onSurfaceVariant: const Color(0xff566d78),
        outline: const Color(0xffa6bac3),
        outlineVariant: const Color(0xffd5e2e7),
      ),
    };
    final panel = _panelBackground;
    return MaterialApp(
      title: 'MeshHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: themedScheme,
        useMaterial3: true,
        navigationRailTheme: theme == MeshHubTheme.tactical
            ? NavigationRailThemeData(
                backgroundColor: TacticalHudColors.panel,
                indicatorColor: TacticalHudColors.cyan.withValues(alpha: 0.14),
                selectedIconTheme: const IconThemeData(
                  size: 20,
                  color: TacticalHudColors.orange,
                ),
                unselectedIconTheme: const IconThemeData(
                  size: 20,
                  color: TacticalHudColors.muted,
                ),
                selectedLabelTextStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: TacticalHudColors.orange,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  fontSize: 11,
                  color: TacticalHudColors.muted,
                ),
              )
            : NavigationRailThemeData(
                backgroundColor: panel,
                indicatorColor: _accent.withValues(alpha: 0.15),
                selectedIconTheme: IconThemeData(size: 22, color: _accent),
                unselectedIconTheme: IconThemeData(
                  size: 22,
                  color: themedScheme.onSurfaceVariant,
                ),
                selectedLabelTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
                unselectedLabelTextStyle: TextStyle(
                  fontSize: 12,
                  color: themedScheme.onSurfaceVariant,
                ),
              ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: panel,
          indicatorColor: _accent.withValues(alpha: 0.15),
          height: theme == MeshHubTheme.tactical ? 62 : 68,
        ),
        filledButtonTheme: theme == MeshHubTheme.tactical
            ? FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: TacticalHudColors.orange,
                  foregroundColor: TacticalHudColors.background,
                  shape: BeveledRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              )
            : FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: theme == MeshHubTheme.light
                      ? const Color(0xffffffff)
                      : _canvas,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
        scaffoldBackgroundColor: _pageBackground,
        dividerColor: themedScheme.outlineVariant,
        listTileTheme: theme == MeshHubTheme.tactical
            ? const ListTileThemeData(
                dense: true,
                horizontalTitleGap: 10,
                minVerticalPadding: 4,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              )
            : null,
        cardTheme: CardThemeData(
          color: panel,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: theme == MeshHubTheme.tactical
              ? BeveledRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
                    color: TacticalHudColors.cyan.withValues(alpha: 0.4),
                  ),
                )
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: themedScheme.outlineVariant),
                ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: theme == MeshHubTheme.light
              ? const Color(0xffedf3f6)
              : theme == MeshHubTheme.dark
              ? const Color(0xff243440)
              : panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              theme == MeshHubTheme.tactical ? 4 : 12,
            ),
            borderSide: BorderSide(color: themedScheme.outlineVariant),
          ),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          toolbarHeight: theme == MeshHubTheme.tactical ? 48 : 52,
          backgroundColor: panel,
          foregroundColor: themedScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            theme == MeshHubTheme.tactical ? 'MESHHUB // HUD' : 'MeshHub',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: theme == MeshHubTheme.tactical ? 'monospace' : null,
              fontSize: theme == MeshHubTheme.tactical ? 18 : 20,
              letterSpacing: theme == MeshHubTheme.tactical ? 1.0 : 0,
              color: theme == MeshHubTheme.tactical
                  ? TacticalHudColors.cyan
                  : themedScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: theme == MeshHubTheme.tactical
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          TacticalHudColors.orange,
                          TacticalHudColors.cyan,
                          TacticalHudColors.background,
                        ],
                      ),
                    ),
                  ),
                )
              : null,
          actions: [
            if (MediaQuery.sizeOf(context).width >= 500)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: field.connected
                        ? _accent.withValues(alpha: 0.12)
                        : scheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        field.connected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: field.connected
                            ? _accent
                            : scheme.onSurfaceVariant,
                        size: theme == MeshHubTheme.tactical ? 16 : 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        field.connected ? 'Radio online' : 'Offline',
                        style: TextStyle(
                          fontSize: theme == MeshHubTheme.tactical ? 11 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            PopupMenuButton<MeshHubTheme>(
              tooltip: 'Theme',
              icon: const Icon(Icons.palette_outlined),
              onSelected: (choice) => setState(() => theme = choice),
              itemBuilder: (_) => MeshHubTheme.values
                  .map(
                    (value) =>
                        PopupMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (constraints.maxWidth >= 760)
                NavigationRail(
                  minWidth: theme == MeshHubTheme.tactical ? 68 : 72,
                  backgroundColor: panel,
                  selectedIndex: destination,
                  extended: constraints.maxWidth >= 1220,
                  labelType: constraints.maxWidth >= 1220
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  onDestinationSelected: (index) =>
                      setState(() => destination = index),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: Text('Messages'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tag_outlined),
                      selectedIcon: Icon(Icons.tag),
                      label: Text('Channels'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_outlined),
                      selectedIcon: Icon(Icons.hub),
                      label: Text('Nodes'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map),
                      label: Text('Map'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.router_outlined),
                      selectedIcon: Icon(Icons.router),
                      label: Text('Radios'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              Expanded(child: _workspace(context)),
            ],
          ),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
            ? NavigationBar(
                height: 68,
                selectedIndex: destination == 4
                    ? 4
                    : destination == 5
                    ? 4
                    : destination,
                onDestinationSelected: (index) => setState(() {
                  destination = index == 4 ? 5 : index;
                }),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: 'Messages',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tag_outlined),
                    selectedIcon: Icon(Icons.tag),
                    label: 'Channels',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: 'Nodes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'More',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _workspace(BuildContext context) {
    final content = switch (destination) {
      0 => _messagesHome(context),
      1 => _inbox(),
      2 => _nodesView(context),
      3 => _mapView(context),
      4 => _radios(context),
      _ => _settingsView(context),
    };
    if (theme != MeshHubTheme.tactical) return content;
    final section = switch (destination) {
      0 => 'Messages',
      1 => 'Channels',
      2 => 'Nodes',
      3 => 'Map',
      4 => 'Radios',
      _ => 'Settings',
    };
    final rf = field.identity?.radioPreset;
    return TacticalHudBackdrop(
      child: Column(
        children: [
          TacticalHudStatusStrip(
            section: section,
            connected: field.connected,
            preset: rf == null
                ? null
                : '${rf.frequencyKHz} kHz / SF${rf.spreadingFactor}',
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _messagesHome(BuildContext context) {
    final recent = field.messages.reversed.toList();
    return ListView(
      padding: EdgeInsets.all(theme == MeshHubTheme.tactical ? 14 : 20),
      children: [
        if (theme == MeshHubTheme.tactical)
          const TacticalHudHeading(
            'Operations // Overview',
            subtitle: 'LIVE TELEMETRY / CURRENT LOCAL SESSION',
          )
        else ...[
          Text(
            'Your mesh, one place.',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'MeshCore and Meshtastic messaging, without mixing networks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        SizedBox(height: theme == MeshHubTheme.tactical ? 12 : 18),
        Wrap(
          spacing: theme == MeshHubTheme.tactical ? 8 : 12,
          runSpacing: theme == MeshHubTheme.tactical ? 8 : 12,
          children: [
            _metricCard(
              Icons.bluetooth,
              field.connected ? 'Connected' : 'Offline',
              'MeshCore radio',
              _meshCoreAccent,
            ),
            _metricCard(
              Icons.tag,
              '${field.channels.length}',
              'Configured channels',
              _meshCoreAccent,
            ),
            _metricCard(
              Icons.forum_outlined,
              '${field.messages.length}',
              'Messages this session',
              _meshtasticAccent,
            ),
            if (theme == MeshHubTheme.tactical)
              TacticalHudLinkScope(
                connected: field.connected,
                channelCount: field.channels.length,
                onOpenRadios: () => setState(() => destination = 4),
              ),
          ],
        ),
        SizedBox(height: theme == MeshHubTheme.tactical ? 18 : 26),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => destination = 1),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Channels'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.mark_chat_unread_outlined, size: 42),
                  const SizedBox(height: 12),
                  const Text('No messages in this session yet'),
                  const SizedBox(height: 8),
                  Text(
                    field.connected
                        ? 'Open Channels to follow live conversations.'
                        : 'Connect a radio to discover channels and receive messages.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        setState(() => destination = field.connected ? 1 : 4),
                    icon: Icon(field.connected ? Icons.tag : Icons.bluetooth),
                    label: Text(
                      field.connected ? 'Browse channels' : 'Connect a radio',
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final message in recent.take(20))
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: message.protocol == MeshProtocol.meshCore
                    ? _meshCoreAccent.withValues(alpha: 0.18)
                    : _meshtasticAccent.withValues(alpha: 0.18),
                child: Icon(
                  message.isOutgoing ? Icons.north_east : Icons.south_west,
                  color: message.protocol == MeshProtocol.meshCore
                      ? _meshCoreAccent
                      : _meshtasticAccent,
                ),
              ),
              title: Text(message.sender),
              subtitle: Text(
                message.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                message.protocol == MeshProtocol.meshCore
                    ? 'MeshCore'
                    : 'Meshtastic',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onTap: () {
                final match = RegExp(r'^meshcore-channel-(\d+)$')
                    .firstMatch(message.conversationId);
                if (match != null) {
                  setState(() {
                    destination = 1;
                    selectedChannel = int.parse(match.group(1)!);
                    final matching = field.channels.where(
                      (c) => c.index == selectedChannel,
                    );
                    _selectedChannelName = matching.isEmpty
                        ? null
                        : matching.first.name;
                  });
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _metricCard(IconData icon, String value, String label, Color accent) {
    final effectiveAccent = theme == MeshHubTheme.light ? _accent : accent;
    if (theme == MeshHubTheme.tactical) {
      return TacticalHudMetric(
        icon: icon,
        label: label,
        value: value,
        highlight: accent == _meshtasticAccent,
      );
    }
    return Container(
      width: 190,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panelBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: effectiveAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: effectiveAccent, size: 23),
          const SizedBox(height: 11),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  /// Shared screen typography and panels. Tactical has its own HUD chrome;
  /// Light and Dark use the same compact, accessible information hierarchy.
  Widget _screenHeading(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    if (theme == MeshHubTheme.tactical) {
      return TacticalHudHeading(title, subtitle: subtitle);
    }
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 23, color: _accent),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: textTheme.bodySmall),
      ],
    );
  }

  Widget _sectionPanel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) {
    final tactical = theme == MeshHubTheme.tactical;
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: tactical ? 17 : 19,
              color: tactical ? TacticalHudColors.orange : _accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                tactical ? title.toUpperCase() : title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: tactical ? 'monospace' : null,
                  letterSpacing: tactical ? 0.7 : 0,
                  fontSize: tactical ? 13 : 15,
                  fontWeight: FontWeight.w700,
                  color: tactical ? TacticalHudColors.cyan : colors.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 10),
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 12),
        child,
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: tactical
          ? TacticalHudPanel(padding: const EdgeInsets.all(14), child: content)
          : Card(
              child: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
    );
  }

  Widget _readout(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final tactical = theme == MeshHubTheme.tactical;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: tactical ? 110 : 128,
            child: Text(
              tactical ? label.toUpperCase() : label,
              style: TextStyle(
                fontSize: tactical ? 10 : 12,
                fontFamily: tactical ? 'monospace' : null,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: tactical ? 12 : 13,
                color: emphasize ? _accent : colors.onSurface,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagnosticMetric(BuildContext context, String label, int value) {
    final tactical = theme == MeshHubTheme.tactical;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFamily: tactical ? 'monospace' : null,
              color: tactical ? TacticalHudColors.teal : _accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tactical ? label.toUpperCase() : label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
    return SizedBox(
      width: 150,
      child: tactical
          ? TacticalHudPanel(padding: EdgeInsets.zero, child: content)
          : Card(child: content),
    );
  }

  Widget _nodesView(BuildContext context) {
    final tactical = theme == MeshHubTheme.tactical;
    return ListView(
      padding: EdgeInsets.all(tactical ? 14 : 20),
      children: [
        _screenHeading(
          context,
          tactical ? 'Node Monitor' : 'Nodes',
          'MeshCore and Meshtastic · verified network information only',
          Icons.hub_outlined,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricCard(
              Icons.hub_outlined,
              'Unavailable',
              'Verified node inventory',
              _accent,
            ),
            _metricCard(
              Icons.bluetooth_connected,
              field.connected ? 'Connected' : 'Offline',
              'MeshCore companion',
              _accent,
            ),
            _metricCard(
              Icons.tag_outlined,
              '${field.channels.length}',
              'Configured channels (not nodes)',
              _accent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionPanel(
          context,
          title: 'Node inventory',
          icon: Icons.radar_outlined,
          subtitle: 'No live node inventory source is connected yet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 19, color: _accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'MeshHub can read the attached radio and its channels, '
                      'but node discovery and telemetry are not implemented. '
                      'An empty inventory here does not mean the mesh is empty.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => destination = 4),
                    icon: const Icon(Icons.router_outlined, size: 18),
                    label: const Text('Radio details'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => destination = 1),
                    icon: const Icon(Icons.tag_outlined, size: 18),
                    label: const Text('Open channels'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionPanel(
          context,
          title: 'Telemetry readiness',
          icon: Icons.monitor_heart_outlined,
          subtitle:
              'Fields will appear only when a protocol adapter reports them',
          child: Column(
            children: [
              _readout(context, 'Node identity', 'Awaiting verified discovery'),
              _readout(context, 'Last heard / hops', 'Not available'),
              _readout(context, 'Signal / battery', 'Not available'),
              _readout(context, 'Location', 'Not available'),
              const SizedBox(height: 6),
              Text(
                'No simulated nodes, inferred reachability, or fabricated '
                'signal statistics are displayed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapView(BuildContext context) => _featurePlaceholder(
    context,
    'Map',
    Icons.map_outlined,
    'Your mesh network, locations, and eventual RF coverage planning.',
    'Live node positions and offline terrain regions have not been connected yet.',
  );

  Widget _featurePlaceholder(
    BuildContext context,
    String title,
    IconData icon,
    String description,
    String detail,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: _accent.withValues(alpha: 0.15),
                    child: Icon(icon, color: _accent, size: 34),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(description, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => destination = 4),
                    icon: const Icon(Icons.router_outlined),
                    label: const Text('View radios'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsView(BuildContext context) => ListView(
    padding: EdgeInsets.all(theme == MeshHubTheme.tactical ? 14 : 20),
    children: [
      _screenHeading(
        context,
        'Settings',
        'Appearance, radio access and data handling',
        Icons.settings_outlined,
      ),
      const SizedBox(height: 14),
      _sectionPanel(
        context,
        title: 'Appearance',
        subtitle: 'Choose the same information in your preferred visual style',
        icon: Icons.palette_outlined,
        child: Column(
          children: [
            for (final choice in MeshHubTheme.values)
              ListTile(
                dense: true,
                leading: Icon(
                  choice == theme
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: choice == theme ? _accent : null,
                ),
                title: Text(
                  choice.name[0].toUpperCase() + choice.name.substring(1),
                ),
                selected: choice == theme,
                onTap: () => setState(() => theme = choice),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      InkWell(
        onTap: () => setState(() => destination = 4),
        child: _sectionPanel(
          context,
          title: 'Radios & Bluetooth',
          icon: Icons.router_outlined,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              field.connected ? 'Radio connected' : 'Connect your radio',
            ),
            subtitle: const Text('Discovery, pairing status and diagnostics'),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _sectionPanel(
        context,
        title: 'Privacy',
        icon: Icons.shield_outlined,
        child: const Text(
          'Message history is session-only. Encrypted on-disk persistence '
          'is not yet implemented.',
        ),
      ),
    ],
  );

  Widget _banner() => const Card(
    child: ListTile(
      leading: Icon(Icons.science_outlined),
      title: Text('SIMULATED DATA — no radio connected'),
      subtitle: Text(
        'Samples are not received messages or RF delivery evidence.',
      ),
    ),
  );

  Widget _inbox() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      if (!wide && selectedChannel != null) {
        return _channelThread(context, narrow: true);
      }
      return Row(
        children: [
          SizedBox(
            width: wide
                ? (constraints.maxWidth >= 1150 ? 340 : 280)
                : constraints.maxWidth,
            child: _channelList(context),
          ),
          if (wide) ...[
            const VerticalDivider(width: 1),
            Expanded(child: _channelThread(context)),
          ],
        ],
      );
    },
  );

  Widget _channelList(BuildContext context) {
    final others = [
      ...field.messages.where(
        (m) => !m.conversationId.startsWith('meshcore-channel-'),
      ),
      if (showExamples) ...MockRadioAdapter.sampleInbox(),
    ].where((m) => filter == null || m.protocol == filter).toList();
    return ListView(
      padding: EdgeInsets.all(theme == MeshHubTheme.tactical ? 12 : 16),
      children: [
        if (theme == MeshHubTheme.tactical)
          const TacticalHudHeading(
            'Channel Array',
            subtitle: 'RADIO CHANNELS / SESSION ONLY',
          )
        else ...[
          Text(
            'Channels',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          const Text('Your radio channels · session-only conversations'),
        ],
        SizedBox(height: theme == MeshHubTheme.tactical ? 6 : 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: filter == null,
              onSelected: (_) => setState(() => filter = null),
            ),
            for (final protocol in MeshProtocol.values)
              ChoiceChip(
                label: Text(
                  protocol == MeshProtocol.meshCore ? 'MeshCore' : 'Meshtastic',
                ),
                selected: filter == protocol,
                onSelected: (_) => setState(() => filter = protocol),
              ),
          ],
        ),
        if (!field.connected)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Connect a MeshCore radio in Radios to load channels.'),
          ),
        if (field.channelsLoading) const LinearProgressIndicator(),
        if (field.channelsError != null)
          Text('Channel read incomplete: ${field.channelsError}'),
        if (field.connected)
          TextButton.icon(
            onPressed: field.channelsLoading
                ? null
                : () => unawaited(field.refreshChannels()),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh channels'),
          ),
        if (field.connected && !field.channelsLoading && field.channels.isEmpty)
          const Text(
            'No configured channel names were returned by this radio.',
          ),
        if (filter != MeshProtocol.meshtastic)
          for (final channel in field.channels) _channelTile(channel),
        Divider(height: theme == MeshHubTheme.tactical ? 20 : 32),
        Text(
          'Other messages',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        if (others.isEmpty)
          const Text('No direct messages received in this session.'),
        for (final message in others)
          Card(
            child: ListTile(
              title: Text(message.sender),
              subtitle: Text(message.text),
              trailing: Text(
                message.isSimulated ? 'SIMULATED' : 'LIVE · MeshCore',
              ),
            ),
          ),
        Divider(height: theme == MeshHubTheme.tactical ? 20 : 32),
        SwitchListTile(
          title: const Text('Show simulated examples'),
          subtitle: const Text('Off = live in-memory messages only'),
          value: showExamples,
          onChanged: (value) => setState(() => showExamples = value),
        ),
        if (showExamples) _banner(),
      ],
    );
  }

  Widget _channelTile(MeshCoreChannel channel) {
    final selected = selectedChannel == channel.index;
    final count = field.messages
        .where(
          (message) =>
              message.protocol == MeshProtocol.meshCore &&
              message.conversationId == 'meshcore-channel-${channel.index}',
        )
        .length;
    final item = ListTile(
      dense: theme == MeshHubTheme.tactical,
      horizontalTitleGap: theme == MeshHubTheme.tactical ? 10 : null,
      contentPadding: EdgeInsets.symmetric(
        horizontal: theme == MeshHubTheme.tactical ? 10 : 12,
        vertical: theme == MeshHubTheme.tactical ? 0 : 6,
      ),
      leading: CircleAvatar(
        radius: theme == MeshHubTheme.tactical ? 17 : 23,
        backgroundColor: _accent.withValues(alpha: 0.18),
        child: Icon(
          Icons.tag,
          color: _accent,
          size: theme == MeshHubTheme.tactical ? 19 : 24,
        ),
      ),
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: theme == MeshHubTheme.tactical ? 15 : null,
        ),
      ),
      subtitle: Text(
        theme == MeshHubTheme.tactical
            ? 'MeshCore · $count msgs · slot ${channel.index}'
            : 'MeshCore · $count messages · slot ${channel.index}',
        maxLines: theme == MeshHubTheme.tactical ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme == MeshHubTheme.tactical
            ? const TextStyle(fontSize: 11)
            : null,
      ),
      trailing: Icon(
        selected && theme == MeshHubTheme.tactical
            ? Icons.radio_button_checked
            : Icons.chevron_right,
        color: selected && theme == MeshHubTheme.tactical
            ? TacticalHudColors.orange
            : null,
        size: theme == MeshHubTheme.tactical ? 19 : 24,
      ),
      selected: selected,
      selectedTileColor: _accent.withValues(alpha: 0.10),
      onTap: () => setState(() {
        selectedChannel = channel.index;
        _selectedChannelName = channel.name;
        channelMessageInput.clear();
      }),
    );
    if (theme == MeshHubTheme.tactical) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: TacticalHudPanel(
          active: selected,
          padding: EdgeInsets.zero,
          child: item,
        ),
      );
    }
    return Card(clipBehavior: Clip.antiAlias, child: item);
  }

  Widget _channelThread(BuildContext context, {bool narrow = false}) {
    final matching = field.channels.where((c) => c.index == selectedChannel);
    if (selectedChannel == null || matching.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 54, color: _meshCoreAccent),
            SizedBox(height: 16),
            Text('Choose a channel to view its conversation'),
          ],
        ),
      );
    }
    final channel = matching.first;
    final posts = field.messages
        .where(
          (m) =>
              m.protocol == MeshProtocol.meshCore &&
              m.conversationId == 'meshcore-channel-${channel.index}',
        )
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            theme == MeshHubTheme.tactical ? 12 : 16,
            theme == MeshHubTheme.tactical ? 8 : 12,
            theme == MeshHubTheme.tactical ? 12 : 16,
            theme == MeshHubTheme.tactical ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: theme == MeshHubTheme.tactical
                ? TacticalHudColors.panel.withValues(alpha: 0.93)
                : null,
            border: Border(
              bottom: BorderSide(
                color: theme == MeshHubTheme.tactical
                    ? TacticalHudColors.orange
                    : colors.outlineVariant,
                width: theme == MeshHubTheme.tactical ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (narrow)
                IconButton(
                  tooltip: 'All channels',
                  onPressed: () => setState(() {
                    selectedChannel = null;
                  }),
                  icon: const Icon(Icons.arrow_back),
                ),
              CircleAvatar(
                radius: theme == MeshHubTheme.tactical ? 17 : 22,
                backgroundColor: _meshCoreAccent.withValues(alpha: 0.17),
                child: Icon(
                  Icons.tag,
                  size: theme == MeshHubTheme.tactical ? 19 : 24,
                  color: _meshCoreAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: theme == MeshHubTheme.tactical ? 17 : null,
                        fontFamily: theme == MeshHubTheme.tactical
                            ? 'monospace'
                            : null,
                        letterSpacing: theme == MeshHubTheme.tactical ? 1.1 : 0,
                        color: theme == MeshHubTheme.tactical
                            ? TacticalHudColors.cyan
                            : colors.onSurface,
                      ),
                    ),
                    Text(
                      'MeshCore · channel slot ${channel.index} · session only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                field.connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: field.connected ? _meshCoreAccent : colors.error,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              theme == MeshHubTheme.tactical ? 12 : 16,
              theme == MeshHubTheme.tactical ? 10 : 16,
              theme == MeshHubTheme.tactical ? 12 : 16,
              theme == MeshHubTheme.tactical ? 14 : 24,
            ),
            children: [
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    field.connected
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: field.connected ? _meshCoreAccent : colors.error,
                  ),
                  title: Text(
                    field.connected ? 'Radio connected' : 'Radio disconnected',
                    style: theme == MeshHubTheme.tactical
                        ? const TextStyle(fontSize: 12)
                        : null,
                  ),
                  subtitle: Text(
                    theme == MeshHubTheme.tactical
                        ? '${field.status} · Coverage unverified'
                        : '${field.status} · MeshHub cannot verify repeater coverage or recipient delivery.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 45),
                  child: Center(
                    child: Text(
                      'No posts in this channel during this session yet.',
                    ),
                  ),
                ),
              for (final post in posts)
                Align(
                  alignment: post.isOutgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Card(
                      color: post.isOutgoing
                          ? _meshCoreAccent.withValues(alpha: 0.13)
                          : null,
                      child: Padding(
                        padding: EdgeInsets.all(
                          theme == MeshHubTheme.tactical ? 10 : 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: theme == MeshHubTheme.tactical
                                      ? 12
                                      : 14,
                                  backgroundColor: post.isOutgoing
                                      ? _meshCoreAccent
                                      : colors.secondaryContainer,
                                  child: Text(
                                    post.isOutgoing ? 'Y' : '#',
                                    style: TextStyle(
                                      color: post.isOutgoing
                                          ? _canvas
                                          : colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    post.sender,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(post.text),
                            const SizedBox(height: 10),
                            Text(
                              post.isSimulated
                                  ? 'SIMULATED'
                                  : post.deliveryState ==
                                        MessageDeliveryState
                                            .acceptedByLocalRadio
                                  ? 'Accepted locally · peer delivery unverified'
                                  : 'LIVE · received by this radio',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              theme == MeshHubTheme.tactical ? 12 : 16,
              theme == MeshHubTheme.tactical ? 6 : 8,
              theme == MeshHubTheme.tactical ? 12 : 16,
              theme == MeshHubTheme.tactical ? 6 : 12,
            ),
            decoration: BoxDecoration(
              color: theme == MeshHubTheme.tactical
                  ? TacticalHudColors.panel.withValues(alpha: 0.98)
                  : null,
              border: Border(
                top: BorderSide(
                  color: theme == MeshHubTheme.tactical
                      ? TacticalHudColors.cyan
                      : colors.outlineVariant,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (field.identity?.radioPreset == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Connect a configured radio before sending.',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: channelMessageInput,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 133,
                        decoration: InputDecoration(
                          isDense: theme == MeshHubTheme.tactical,
                          counterStyle: theme == MeshHubTheme.tactical
                              ? const TextStyle(fontSize: 10)
                              : null,
                          hintText: 'Message ${channel.name}',
                          prefixIcon: const Icon(Icons.chat_bubble_outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: EdgeInsets.only(
                        top: theme == MeshHubTheme.tactical ? 2 : 4,
                      ),
                      child: FilledButton.icon(
                        style: theme == MeshHubTheme.tactical
                            ? FilledButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 13),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                              )
                            : null,
                        onPressed:
                            field.connected &&
                                !field.channelsLoading &&
                                !field.sending &&
                                field.identity?.radioPreset != null &&
                                field.channels.any(
                                  (c) => c.index == channel.index,
                                )
                            ? () => _sendChannelPost(context)
                            : null,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendChannelPost(BuildContext messengerContext) async {
    final messenger = ScaffoldMessenger.of(messengerContext);
    final channel = selectedChannel;
    final name = _selectedChannelName;
    final text = channelMessageInput.text;
    if (channel == null || name == null) return;
    try {
      final result = await field.sendChannel(
        channel: channel,
        text: text,
        verified: true,
      );
      if (!mounted) return;
      if (result == MeshCoreLocalSendResult.acceptedByRadio) {
        channelMessageInput.clear();
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Send rejected or uncertain (${e.runtimeType}); inspect diagnostics. Do not retry blindly.',
          ),
        ),
      );
    }
  }

  Widget _radios(BuildContext context) {
    final tactical = theme == MeshHubTheme.tactical;
    final colors = Theme.of(context).colorScheme;
    final info = field.deviceInfo;
    final rf = field.identity?.radioPreset;
    return ListView(
      padding: EdgeInsets.all(tactical ? 14 : 20),
      children: [
        _screenHeading(
          context,
          tactical ? 'Communications Console' : 'Radios & Bluetooth',
          'Companion connection, verified readback and session diagnostics',
          Icons.router_outlined,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricCard(
              Icons.bluetooth_connected,
              field.connected ? 'Online' : 'Offline',
              'MeshCore link',
              _accent,
            ),
            _metricCard(
              Icons.router_outlined,
              info?.model ?? 'Unknown',
              'Radio model',
              _accent,
            ),
            _metricCard(
              Icons.tune,
              rf == null ? 'Unavailable' : '${rf.frequencyKHz} kHz',
              'Read-only RF frequency',
              _accent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionPanel(
          context,
          title: 'Connection',
          subtitle: 'Bluetooth LE companion · local radio only',
          icon: field.connected
              ? Icons.bluetooth_connected
              : Icons.bluetooth_disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  field.connected
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  color: field.connected ? _accent : colors.onSurfaceVariant,
                ),
                title: Text(field.selected?.name ?? 'No radio selected'),
                subtitle: Text(
                  field.connected
                      ? 'Connected / paired · ${field.status}'
                      : 'Not ready · ${field.status}',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: field.scanning
                        ? null
                        : () => unawaited(field.discover()),
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label: const Text('Discover MeshCore radios'),
                  ),
                  if (field.connected)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(field.disconnect()),
                      icon: const Icon(Icons.bluetooth_disabled, size: 18),
                      label: const Text('Disconnect'),
                    ),
                ],
              ),
              if (field.scanning) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (field.error != null) ...[
                const SizedBox(height: 10),
                Text(field.error!, style: TextStyle(color: colors.error)),
              ],
              for (final candidate in field.candidates) ...[
                const Divider(height: 16),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    candidate.assessment ==
                            MeshCoreCandidateAssessment.serviceUuidKnown
                        ? Icons.bluetooth_searching
                        : Icons.help_outline,
                    color: _accent,
                  ),
                  title: Text(
                    candidate.name.isEmpty
                        ? 'Unnamed BLE candidate'
                        : candidate.name,
                  ),
                  subtitle: Text(
                    candidate.assessment ==
                            MeshCoreCandidateAssessment.serviceUuidKnown
                        ? 'MeshCore service seen · ${candidate.isFresh ? 'fresh' : 'cached'}'
                        : 'Name hint only · service verification required',
                  ),
                  trailing: TextButton(
                    onPressed: field.connecting
                        ? null
                        : () => unawaited(field.connect(candidate)),
                    child: const Text('Connect'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            final width = wide
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: _sectionPanel(
                    context,
                    title: 'Device identification',
                    icon: Icons.memory_outlined,
                    subtitle: 'Reported by the connected radio',
                    child: info == null
                        ? const Text(
                            'Connect a radio for model and firmware details.',
                          )
                        : Column(
                            children: [
                              _readout(context, 'Model', info.model),
                              _readout(context, 'Firmware', info.version),
                              _readout(context, 'Build', info.build),
                              _readout(
                                context,
                                'Protocol',
                                '${info.firmwareCode}',
                              ),
                              _readout(
                                context,
                                'Channel slots',
                                '${info.maxChannels}',
                              ),
                            ],
                          ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _sectionPanel(
                    context,
                    title: 'RF configuration',
                    icon: Icons.settings_input_antenna,
                    subtitle:
                        'Read-only preset · regulatory region not verified',
                    child: rf == null
                        ? const Text(
                            'No RF preset available until a radio is connected.',
                          )
                        : Column(
                            children: [
                              _readout(
                                context,
                                'Frequency',
                                '${rf.frequencyKHz} kHz',
                                emphasize: true,
                              ),
                              _readout(
                                context,
                                'Bandwidth',
                                '${rf.bandwidthHz} Hz',
                              ),
                              _readout(
                                context,
                                'Spreading',
                                'SF${rf.spreadingFactor}',
                              ),
                              _readout(
                                context,
                                'Coding rate',
                                'CR${rf.codingRate}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'MeshHub has not verified legal RF region, repeater coverage, or peer delivery.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _sectionPanel(
          context,
          title: 'Field diagnostics',
          subtitle: 'Counters observed by this local session · not RF delivery receipts',
          icon: Icons.monitor_heart_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _readout(context, 'Connection', field.status),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _diagnosticMetric(context, 'Received', field.receiveCount),
                  _diagnosticMetric(
                    context,
                    'Waiting pushes',
                    field.waitingCount,
                  ),
                  _diagnosticMetric(context, 'Malformed', field.rejectedFrames),
                  _diagnosticMetric(context, 'Local accepts', field.sendCount),
                  _diagnosticMetric(
                    context,
                    'Reconnects',
                    field.reconnectAttempts,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionPanel(
          context,
          title: 'Advanced field tools',
          subtitle:
              'Direct test sends require explicit destination verification',
          icon: Icons.science_outlined,
          child: ExpansionTile(
            key: const PageStorageKey('direct-test-tools'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Direct test message'),
            subtitle: const Text('Optional · local acceptance is not delivery'),
            children: [
              const SizedBox(height: 8),
              const Text(
                'Before transmitting, verify RF region, the readback preset, '
                'the direct contact prefix, and a reachable peer. '
                'An interrupted send remains uncertain.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyPrefixInput,
                decoration: const InputDecoration(
                  labelText: 'Verified direct contact prefix',
                  helperText: '12 lowercase hexadecimal characters',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageInput,
                maxLines: 2,
                maxLength: 133,
                decoration: const InputDecoration(
                  labelText: 'Direct test message (UTF-8, max 133 bytes)',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I verified RF region, preset, contact, and reachable peer',
                ),
                value: verifiedDestination,
                onChanged: (value) =>
                    setState(() => verifiedDestination = value ?? false),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed:
                      !field.connected || !verifiedDestination || field.sending
                      ? null
                      : () => unawaited(_sendDirectOnce(context)),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send direct once'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Radio acceptance does not confirm over-the-air or recipient delivery. '
                'Do not blindly retransmit an uncertain send.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendDirectOnce(BuildContext messengerContext) async {
    final messenger = ScaffoldMessenger.of(messengerContext);
    try {
      await field.sendDirect(
        keyPrefix: keyPrefixInput.text,
        text: messageInput.text,
        verified: verifiedDestination,
      );
      if (mounted) setState(() => verifiedDestination = false);
    } catch (e) {
      if (mounted) {
        setState(() => verifiedDestination = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Send rejected or uncertain (${e.runtimeType}); inspect diagnostics.',
            ),
          ),
        );
      }
    }
  }
}
