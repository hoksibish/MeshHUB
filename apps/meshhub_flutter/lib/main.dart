import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';
import 'package:meshhub_domain/testing.dart';

import 'field_session.dart';
import 'firmware_manager_screen.dart';
import 'linux_meshcore_ble.dart';
import 'meshtastic_connection_panel.dart';
import 'meshtastic_session.dart';
import 'mesh_theme.dart';
import 'modern_shell.dart';

void main() => runApp(const MeshHubApp());

class MeshHubApp extends StatefulWidget {
  const MeshHubApp({super.key, this.fieldSession});

  /// Allows a synthetic field session in widget tests; production uses BlueZ.
  final MeshCoreFieldSession? fieldSession;

  @override
  State<MeshHubApp> createState() => _MeshHubAppState();
}

class _MeshHubAppState extends State<MeshHubApp> {
  MeshHubTheme theme = MeshHubTheme.firesky;
  MeshPalette get _palette => theme.palette;
  Color get _panelBackground => _palette.panel;
  Color get _accent => _palette.primary;
  Color get _meshCoreAccent => _palette.primary;
  Color get _meshtasticAccent => _palette.secondary;
  MeshProtocol? filter;
  int destination = 0;
  late final MeshCoreFieldSession field;
  final meshtastic = MeshtasticSession();
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
    meshtastic.addListener(_refreshConnection);
  }

  void _refreshConnection() {
    // A pairing panel can be removed while a scrolling frame is finalizing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
    meshtastic.removeListener(_refreshConnection);
    meshtastic.dispose();
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
    final scheme = _palette.buildTheme().colorScheme;
    final themedScheme = scheme;
    final panel = _panelBackground;
    return MaterialApp(
      title: 'MeshHub',
      debugShowCheckedModeBanner: false,
      theme: _palette.buildTheme(),
      home: Scaffold(
        appBar: AppBar(
          toolbarHeight: 76,
          backgroundColor: _palette.background,
          foregroundColor: themedScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 24,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accent, _palette.secondary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: scheme.onPrimary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'MeshHub',
                style: TextStyle(
                  fontSize: 22,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            if (MediaQuery.sizeOf(context).width >= 500)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: (field.connected || meshtastic.connected)
                        ? _accent.withValues(alpha: 0.12)
                        : scheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (field.connected || meshtastic.connected)
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: (field.connected || meshtastic.connected)
                            ? _accent
                            : scheme.onSurfaceVariant,
                        size: theme == MeshHubTheme.retro82 ? 16 : 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        field.connected && meshtastic.connected
                            ? 'Radios online'
                            : field.connected
                            ? 'MeshCore online'
                            : meshtastic.connected
                            ? 'Meshtastic online'
                            : 'Offline',
                        style: TextStyle(
                          fontSize: theme == MeshHubTheme.retro82 ? 11 : 12,
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
                    (value) => PopupMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: value.palette.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(value.label),
                          const Spacer(),
                          if (value == theme) const Icon(Icons.check, size: 16),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (constraints.maxWidth >= 760)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 8, 16),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: NavigationRail(
                    minWidth: 84,
                    minExtendedWidth: 204,
                    backgroundColor: Colors.transparent,
                    leading: Padding(
                      padding: const EdgeInsets.only(bottom: 24, top: 8),
                      child: Text(
                        constraints.maxWidth >= 1040 ? 'WORKSPACE' : 'MESH',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    selectedIndex: destination,
                    extended: constraints.maxWidth >= 1040,
                    labelType: constraints.maxWidth >= 1040
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
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    0,
                    constraints.maxWidth >= 760 ? 16 : 0,
                    0,
                  ),
                  child: _workspace(context),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: NavigationBar(
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
                  ),
                ),
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
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320),
        child: content,
      ),
    );
  }

  Widget _messagesHome(BuildContext context) {
    final recent = field.messages.reversed.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        MeshWelcomeCard(
          connected: field.connected,
          onConnect: () => setState(() => destination = 4),
          onChannels: () => setState(() => destination = 1),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, bounds) {
            final width = (bounds.maxWidth - 24) / 3;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metricCard(
                  Icons.bluetooth,
                  field.connected ? 'Connected' : 'Offline',
                  'MeshCore radio',
                  _meshCoreAccent,
                  width: width,
                ),
                const SizedBox(width: 12),
                _metricCard(
                  Icons.tag,
                  '${field.channels.length}',
                  'Configured channels',
                  _meshCoreAccent,
                  width: width,
                ),
                const SizedBox(width: 12),
                _metricCard(
                  Icons.forum_outlined,
                  '${field.messages.length}',
                  'Messages this session',
                  _meshtasticAccent,
                  width: width,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
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
          MeshActivityEmpty(
            connected: field.connected,
            onAction: () =>
                setState(() => destination = field.connected ? 1 : 4),
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

  Widget _metricCard(
    IconData icon,
    String value,
    String label,
    Color accent, {
    double width = 190,
  }) => MeshSummaryCard(
    icon: icon,
    value: value,
    label: label,
    accent: accent,
    width: width,
  );

  /// Shared screen hierarchy with palette-specific radio instrumentation.
  Widget _screenHeading(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
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
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: _accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: null,
                  letterSpacing: 0,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
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
        const SizedBox(height: 22),
        child,
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(padding: const EdgeInsets.all(22), child: content),
      ),
    );
  }

  Widget _readout(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: null,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
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
              fontFamily: null,
              color: _accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
    return SizedBox(width: 150, child: Card(child: content));
  }

  Widget _nodesView(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        _screenHeading(
          context,
          'Nodes',
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
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                title: Text(choice.label),
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
      padding: EdgeInsets.all(theme == MeshHubTheme.retro82 ? 12 : 16),
      children: [
        _screenHeading(
          context,
          'Channels',
          'Your radio channels · session-only conversations',
          Icons.tag_rounded,
        ),
        const SizedBox(height: 20),
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
        Divider(height: theme == MeshHubTheme.retro82 ? 20 : 32),
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
        Divider(height: theme == MeshHubTheme.retro82 ? 20 : 32),
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
      dense: theme == MeshHubTheme.retro82,
      horizontalTitleGap: theme == MeshHubTheme.retro82 ? 10 : null,
      contentPadding: EdgeInsets.symmetric(
        horizontal: theme == MeshHubTheme.retro82 ? 10 : 12,
        vertical: theme == MeshHubTheme.retro82 ? 0 : 6,
      ),
      leading: CircleAvatar(
        radius: theme == MeshHubTheme.retro82 ? 17 : 23,
        backgroundColor: _accent.withValues(alpha: 0.18),
        child: Icon(
          Icons.tag,
          color: _accent,
          size: theme == MeshHubTheme.retro82 ? 19 : 24,
        ),
      ),
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: theme == MeshHubTheme.retro82 ? 15 : null,
        ),
      ),
      subtitle: Text(
        theme == MeshHubTheme.retro82
            ? 'MeshCore · $count msgs · slot ${channel.index}'
            : 'MeshCore · $count messages · slot ${channel.index}',
        maxLines: theme == MeshHubTheme.retro82 ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme == MeshHubTheme.retro82
            ? const TextStyle(fontSize: 11)
            : null,
      ),
      trailing: Icon(
        selected && theme == MeshHubTheme.retro82
            ? Icons.radio_button_checked
            : Icons.chevron_right,
        color: selected && theme == MeshHubTheme.retro82
            ? _palette.primary
            : null,
        size: theme == MeshHubTheme.retro82 ? 19 : 24,
      ),
      selected: selected,
      selectedTileColor: _accent.withValues(alpha: 0.10),
      onTap: () => setState(() {
        selectedChannel = channel.index;
        _selectedChannelName = channel.name;
        channelMessageInput.clear();
      }),
    );
    return Card(clipBehavior: Clip.antiAlias, child: item);
  }

  Widget _channelThread(BuildContext context, {bool narrow = false}) {
    final matching = field.channels.where((c) => c.index == selectedChannel);
    if (selectedChannel == null || matching.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 54, color: _meshCoreAccent),
            const SizedBox(height: 16),
            const Text('Choose a channel to view its conversation'),
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
            theme == MeshHubTheme.retro82 ? 12 : 16,
            theme == MeshHubTheme.retro82 ? 8 : 12,
            theme == MeshHubTheme.retro82 ? 12 : 16,
            theme == MeshHubTheme.retro82 ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: theme == MeshHubTheme.retro82
                ? _palette.panel.withValues(alpha: 0.93)
                : null,
            border: Border(
              bottom: BorderSide(
                color: theme == MeshHubTheme.retro82
                    ? _palette.primary
                    : colors.outlineVariant,
                width: theme == MeshHubTheme.retro82 ? 2 : 1,
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
                radius: theme == MeshHubTheme.retro82 ? 17 : 22,
                backgroundColor: _meshCoreAccent.withValues(alpha: 0.17),
                child: Icon(
                  Icons.tag,
                  size: theme == MeshHubTheme.retro82 ? 19 : 24,
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
                        fontSize: theme == MeshHubTheme.retro82 ? 17 : null,
                        fontFamily: theme == MeshHubTheme.retro82
                            ? 'monospace'
                            : null,
                        letterSpacing: theme == MeshHubTheme.retro82 ? 1.1 : 0,
                        color: theme == MeshHubTheme.retro82
                            ? _palette.primary
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
              theme == MeshHubTheme.retro82 ? 12 : 16,
              theme == MeshHubTheme.retro82 ? 10 : 16,
              theme == MeshHubTheme.retro82 ? 12 : 16,
              theme == MeshHubTheme.retro82 ? 14 : 24,
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
                    style: theme == MeshHubTheme.retro82
                        ? const TextStyle(fontSize: 12)
                        : null,
                  ),
                  subtitle: Text(
                    theme == MeshHubTheme.retro82
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
                          theme == MeshHubTheme.retro82 ? 10 : 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: theme == MeshHubTheme.retro82
                                      ? 12
                                      : 14,
                                  backgroundColor: post.isOutgoing
                                      ? _meshCoreAccent
                                      : colors.secondaryContainer,
                                  child: Text(
                                    post.isOutgoing ? 'Y' : '#',
                                    style: TextStyle(
                                      color: post.isOutgoing
                                          ? _palette.background
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
              theme == MeshHubTheme.retro82 ? 12 : 16,
              theme == MeshHubTheme.retro82 ? 6 : 8,
              theme == MeshHubTheme.retro82 ? 12 : 16,
              theme == MeshHubTheme.retro82 ? 6 : 12,
            ),
            decoration: BoxDecoration(
              color: theme == MeshHubTheme.retro82
                  ? _palette.panel.withValues(alpha: 0.98)
                  : null,
              border: Border(
                top: BorderSide(
                  color: theme == MeshHubTheme.retro82
                      ? _palette.primary
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
                          isDense: theme == MeshHubTheme.retro82,
                          counterStyle: theme == MeshHubTheme.retro82
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
                        top: theme == MeshHubTheme.retro82 ? 2 : 4,
                      ),
                      child: FilledButton.icon(
                        style: theme == MeshHubTheme.retro82
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
    final colors = Theme.of(context).colorScheme;
    final info = field.deviceInfo;
    final rf = field.identity?.radioPreset;
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        _screenHeading(
          context,
          'Radios & Bluetooth',
          'MeshCore and Meshtastic connections, readback and session diagnostics',
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
          title: 'MeshCore connection',
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
        _sectionPanel(
          context,
          title: 'Meshtastic connection',
          subtitle: 'Bluetooth LE · in-app PIN pairing · device readback',
          icon: Icons.bluetooth,
          child: MeshtasticConnectionPanel(session: meshtastic),
        ),
        const SizedBox(height: 12),
        _sectionPanel(
          context,
          title: 'Firmware Manager',
          subtitle: 'Offline firmware library · guarded Heltec V3 USB flashing',
          icon: Icons.system_update_alt,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Inspect firmware, save it for offline use, check the USB '
                  'chip, and flash only after explicit confirmation.',
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FirmwareManagerScreen(
                      instrument: false,
                      radioConnected: () =>
                          field.connected ||
                          field.connecting ||
                          meshtastic.active,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
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
              _readout(context, 'Last local send', field.lastSendOutcome),
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
                    'Send requests',
                    field.sendRequestCount,
                  ),
                  _diagnosticMetric(
                    context,
                    'Rejected sends',
                    field.rejectedSendCount,
                  ),
                  _diagnosticMetric(
                    context,
                    'Uncertain sends',
                    field.uncertainSendCount,
                  ),
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
