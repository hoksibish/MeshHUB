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
  static const _canvas = Color(0xff0e131a);
  static const _surface = Color(0xff19222c);
  static const _meshCoreAccent = Color(0xff55d6cb);
  static const _meshtasticAccent = Color(0xffb6df62);
  static const _tacticalAccent = TacticalHudColors.cyan;
  Color get _pageBackground => switch (theme) {
    MeshHubTheme.light => const Color(0xfff6f9fc),
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
      MeshHubTheme.light => const Color(0xff146c61),
      MeshHubTheme.dark => _meshCoreAccent,
      MeshHubTheme.tactical => _tacticalAccent,
    };
    final mode = theme == MeshHubTheme.light
        ? Brightness.light
        : Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: color, brightness: mode);
    final themedScheme = theme == MeshHubTheme.tactical
        ? scheme.copyWith(
            primary: TacticalHudColors.cyan,
            onPrimary: TacticalHudColors.background,
            secondary: TacticalHudColors.orange,
            onSecondary: TacticalHudColors.background,
            surface: TacticalHudColors.panel,
            onSurface: TacticalHudColors.text,
            onSurfaceVariant: TacticalHudColors.muted,
            outline: TacticalHudColors.cyan.withValues(alpha: 0.5),
            outlineVariant: TacticalHudColors.cyan.withValues(alpha: 0.25),
          )
        : scheme;
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
                  color: TacticalHudColors.orange,
                ),
                selectedLabelTextStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: TacticalHudColors.orange,
                ),
              )
            : null,
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
            : null,
        scaffoldBackgroundColor: _pageBackground,
        cardTheme: CardThemeData(
          color: panel,
          elevation: 0,
          shape: theme == MeshHubTheme.tactical
              ? BeveledRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: TacticalHudColors.cyan.withValues(alpha: 0.55),
                  ),
                )
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: theme == MeshHubTheme.light
              ? const Color(0xffeaf1f5)
              : panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              theme == MeshHubTheme.tactical ? 4 : 20,
            ),
            borderSide: theme == MeshHubTheme.tactical
                ? const BorderSide(color: TacticalHudColors.cyan)
                : BorderSide.none,
          ),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: panel,
          title: Text(
            theme == MeshHubTheme.tactical ? 'MESHHUB // HUD' : 'MeshHub',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: theme == MeshHubTheme.tactical ? 'monospace' : null,
              letterSpacing: theme == MeshHubTheme.tactical ? 1.3 : 0,
              color: theme == MeshHubTheme.tactical
                  ? TacticalHudColors.cyan
                  : null,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: theme == MeshHubTheme.tactical
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: Container(
                    height: 2,
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
                      field.connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: field.connected ? _accent : scheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      field.connected ? 'Radio online' : 'Offline',
                      style: const TextStyle(fontSize: 13),
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
                selectedIndex: destination == 4 ? 4 : destination == 5 ? 4 : destination,
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
            preset: rf == null ? null : '${rf.frequencyKHz} kHz / SF${rf.spreadingFactor}',
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _messagesHome(BuildContext context) {
    final recent = field.messages.reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (theme == MeshHubTheme.tactical)
          const TacticalHudHeading(
            'Operations // Overview',
            subtitle: 'LIVE TELEMETRY / CURRENT LOCAL SESSION',
          )
        else ...[
          Text(
            'Your mesh, one place.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MeshCore and Meshtastic messaging, without mixing networks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
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
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
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
                    onPressed: () => setState(() => destination = field.connected ? 1 : 4),
                    icon: Icon(field.connected ? Icons.tag : Icons.bluetooth),
                    label: Text(field.connected ? 'Browse channels' : 'Connect a radio'),
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
                message.protocol == MeshProtocol.meshCore ? 'MeshCore' : 'Meshtastic',
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
                    _selectedChannelName = matching.isEmpty ? null : matching.first.name;
                  });
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _metricCard(IconData icon, String value, String label, Color accent) {
    if (theme == MeshHubTheme.tactical) {
      return TacticalHudMetric(
        icon: icon,
        label: label,
        value: value,
        highlight: accent == _meshtasticAccent,
      );
    }
    return Container(
      width: 195,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panelBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _nodesView(BuildContext context) => _featurePlaceholder(
    context,
    'Nodes',
    Icons.hub_outlined,
    'Node discovery and live telemetry will appear here as protocol adapters are completed.',
    'No verified node inventory is available yet. MeshHub will not invent battery levels, hops, or signal quality.',
  );

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
                    backgroundColor: _meshCoreAccent.withValues(alpha: 0.15),
                    child: Icon(icon, color: _meshCoreAccent, size: 34),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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
    padding: const EdgeInsets.all(22),
    children: [
      Text(
        'Settings',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 18),
      Card(
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.palette_outlined, color: _meshCoreAccent),
              title: Text('Appearance'),
              subtitle: Text('Choose your display theme'),
            ),
            for (final choice in MeshHubTheme.values)
              ListTile(
                leading: Icon(
                  choice == theme
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: choice == theme ? _meshCoreAccent : null,
                ),
                title: Text(choice.name),
                selected: choice == theme,
                onTap: () => setState(() => theme = choice),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: ListTile(
          leading: const Icon(Icons.router_outlined, color: _meshCoreAccent),
          title: const Text('Radios & Bluetooth'),
          subtitle: Text(field.connected ? 'Radio connected' : 'Connect your radio'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => destination = 4),
        ),
      ),
      const SizedBox(height: 14),
      const Card(
        child: ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('Privacy'),
          subtitle: Text('Message history is session-only; encrypted persistence is not yet implemented.'),
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
            width: wide ? (constraints.maxWidth >= 1150 ? 340 : 280) : constraints.maxWidth,
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
      padding: const EdgeInsets.all(16),
      children: [
        if (theme == MeshHubTheme.tactical)
          const TacticalHudHeading(
            'Channel Array',
            subtitle: 'RADIO-REPORTED CHANNELS / SESSION-ONLY MESSAGES',
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
        const SizedBox(height: 8),
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
        const Divider(height: 32),
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
        const Divider(height: 32),
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
    final count = field.messages.where(
      (message) =>
          message.protocol == MeshProtocol.meshCore &&
          message.conversationId == 'meshcore-channel-${channel.index}',
    ).length;
    final item = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: CircleAvatar(
        radius: 23,
        backgroundColor: _accent.withValues(alpha: 0.18),
        child: Icon(Icons.tag, color: _accent),
      ),
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'MeshCore · $count messages · slot ${channel.index}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        selected && theme == MeshHubTheme.tactical
            ? Icons.radio_button_checked
            : Icons.chevron_right,
        color: selected && theme == MeshHubTheme.tactical
            ? TacticalHudColors.orange
            : null,
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
        padding: const EdgeInsets.symmetric(vertical: 5),
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
    final posts = field.messages.where(
      (m) =>
          m.protocol == MeshProtocol.meshCore &&
          m.conversationId == 'meshcore-channel-${channel.index}',
    ).toList();
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                radius: 22,
                backgroundColor: _meshCoreAccent.withValues(alpha: 0.17),
                child: const Icon(Icons.tag, color: _meshCoreAccent),
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
                field.connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: field.connected ? _meshCoreAccent : colors.error,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                  ),
                  subtitle: Text(
                    '${field.status} · MeshHub cannot verify repeater coverage or recipient delivery.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 45),
                  child: Center(
                    child: Text('No posts in this channel during this session yet.'),
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
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
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
                                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                                        MessageDeliveryState.acceptedByLocalRadio
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                          hintText: 'Message ${channel.name}',
                          prefixIcon: const Icon(Icons.chat_bubble_outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FilledButton.icon(
                        onPressed:
                            field.connected &&
                                !field.channelsLoading &&
                                !field.sending &&
                                field.identity?.radioPreset != null &&
                                field.channels.any((c) => c.index == channel.index)
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
    final info = field.deviceInfo;
    final rf = field.identity?.radioPreset;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (theme == MeshHubTheme.tactical)
          const TacticalHudHeading(
            'Communications Console',
            subtitle: 'LIVE BLE TRANSPORT / CONFIGURATION READBACK',
          )
        else
          Text(
          'Radios',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: field.scanning ? null : () => unawaited(field.discover()),
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Discover MeshCore radios'),
        ),
        if (field.scanning) const LinearProgressIndicator(),
        for (final candidate in field.candidates)
          Card(
            child: ListTile(
              title: Text(
                candidate.name.isEmpty
                    ? 'Unnamed BLE candidate'
                    : candidate.name,
              ),
              subtitle: Text(
                candidate.assessment ==
                        MeshCoreCandidateAssessment.serviceUuidKnown
                    ? 'MeshCore service known · ${candidate.isFresh ? 'fresh' : 'cached'}'
                    : 'Name hint only · GATT verification required',
              ),
              trailing: TextButton(
                onPressed: field.connecting
                    ? null
                    : () => unawaited(field.connect(candidate)),
                child: const Text('Connect'),
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  field.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                ),
                title: Text(field.selected?.name ?? 'No radio selected'),
                subtitle: Text(
                  'Bluetooth: ${field.connected ? 'connected, paired' : 'not ready'} · ${field.status}',
                ),
              ),
              if (field.connected)
                TextButton(
                  onPressed: () => unawaited(field.disconnect()),
                  child: const Text('Disconnect'),
                ),
              if (field.error != null) ListTile(title: Text(field.error!)),
              if (info != null) ...[
                ListTile(
                  title: Text('${info.model} · ${info.version}'),
                  subtitle: Text(
                    'Build ${info.build} · protocol ${info.firmwareCode} · ${info.maxChannels} channel slots',
                  ),
                ),
                if (rf != null)
                  ListTile(
                    title: Text(
                      'RF: ${rf.frequencyKHz} kHz · ${rf.bandwidthHz} Hz',
                    ),
                    subtitle: Text(
                      'SF${rf.spreadingFactor} · CR${rf.codingRate} · read-only; region not verified by app',
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Field diagnostics',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        ListTile(
          title: Text('Connection: ${field.status}'),
          subtitle: Text(
            'Waiting pushes: ${field.waitingCount} · received: ${field.receiveCount} · malformed: ${field.rejectedFrames} · local sends accepted: ${field.sendCount} · reconnect attempts: ${field.reconnectAttempts}',
          ),
        ),
        const Divider(),
        Text(
          'Direct test message',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const Text(
          'Channel conversations and their inline composer are in Inbox. For a direct test, verify region, displayed preset, contact prefix and a reachable peer before transmitting.',
        ),
        TextField(
          controller: keyPrefixInput,
          decoration: const InputDecoration(
            labelText: 'Verified direct contact key prefix (12 lowercase hex characters)',
          ),
        ),
        TextField(
          controller: messageInput,
          maxLines: 2,
          maxLength: 133,
          decoration: const InputDecoration(
            labelText: 'Direct test message (UTF-8, max 133 bytes)',
          ),
        ),
        CheckboxListTile(
          title: const Text(
            'I verified RF region, displayed preset, direct contact and reachable test peer',
          ),
          value: verifiedDestination,
          onChanged: (value) =>
              setState(() => verifiedDestination = value ?? false),
        ),
        FilledButton(
          onPressed: !field.connected || !verifiedDestination || field.sending
              ? null
              : () => unawaited(_sendDirectOnce(context)),
          child: const Text('Send direct once (local radio acceptance only)'),
        ),
        const Text(
          'Local radio acceptance is not over-the-air or recipient delivery. An interrupted send is uncertain; do not blindly resend.',
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
