import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';
import 'package:meshhub_domain/testing.dart';

import 'field_session.dart';
import 'linux_meshcore_ble.dart';

void main() => runApp(const MeshHubApp());

enum MeshHubTheme { light, dark, tactical }

class MeshHubApp extends StatefulWidget {
  const MeshHubApp({super.key, this.fieldSession});

  /// Allows a synthetic field session in widget tests; production uses BlueZ.
  final MeshCoreFieldSession? fieldSession;

  @override
  State<MeshHubApp> createState() => _MeshHubAppState();
}

class _ChannelPost {
  const _ChannelPost({
    required this.channel,
    required this.sender,
    required this.text,
    required this.status,
  });

  final int channel;
  final String sender;
  final String text;
  final String status;
}

class _MeshHubAppState extends State<MeshHubApp> {
  MeshHubTheme theme = MeshHubTheme.dark;
  MeshProtocol? filter;
  int destination = 0;
  late final MeshCoreFieldSession field;
  final messageInput = TextEditingController();
  final channelMessageInput = TextEditingController();
  final keyPrefixInput = TextEditingController();
  final List<_ChannelPost> _channelPosts = [];
  final Set<String> _seenMessageIds = {};
  int? selectedChannel;
  String? _selectedChannelName;
  bool showExamples = false;
  bool verifiedDestination = false;
  bool verifiedChannel = false;

  @override
  void initState() {
    super.initState();
    field = widget.fieldSession ?? MeshCoreFieldSession();
    _captureNewMessages();
    field.addListener(_refresh);
  }

  void _captureNewMessages() {
    for (final message in field.messages) {
      if (message.protocol != MeshProtocol.meshCore ||
          message.isSimulated ||
          !_seenMessageIds.add(message.id)) {
        continue;
      }
      final match = RegExp(r'^meshcore-channel-(\d+)$')
          .firstMatch(message.conversationId);
      if (match == null) continue;
      _channelPosts.add(
        _ChannelPost(
          channel: int.parse(match.group(1)!),
          sender: message.sender,
          text: message.text,
          status: 'LIVE · received by this radio',
        ),
      );
    }
  }

  void _refresh() {
    _captureNewMessages();
    if (!field.connected || field.channelsLoading) {
      verifiedDestination = false;
      verifiedChannel = false;
    }
    if (selectedChannel != null && !field.channelsLoading) {
      final matching = field.channels.where((c) => c.index == selectedChannel);
      if (matching.isEmpty || matching.first.name != _selectedChannelName) {
        selectedChannel = null;
        _selectedChannelName = null;
        verifiedChannel = false;
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
      MeshHubTheme.dark => const Color(0xff69d5bf),
      MeshHubTheme.tactical => const Color(0xffb2dc7c),
    };
    final mode = theme == MeshHubTheme.light
        ? Brightness.light
        : Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: color, brightness: mode);
    return MaterialApp(
      title: 'MeshHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('MeshHub'),
          actions: [
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
              if (constraints.maxWidth >= 700)
                NavigationRail(
                  selectedIndex: destination,
                  extended: constraints.maxWidth >= 1000,
                  onDestinationSelected: (index) =>
                      setState(() => destination = index),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      label: Text('Inbox'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.router_outlined),
                      label: Text('Radios'),
                    ),
                  ],
                ),
              Expanded(
                child: destination == 0
                    ? _inbox()
                    : Builder(builder: (innerContext) => _radios(innerContext)),
              ),
            ],
          ),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 700
            ? NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: (index) =>
                    setState(() => destination = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    label: 'Inbox',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.router_outlined),
                    label: 'Radios',
                  ),
                ],
              )
            : null,
      ),
    );
  }

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
            width: wide ? 300 : constraints.maxWidth,
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
        Text(
          'Channels',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 4),
        const Text('Read-only names from the connected MeshCore radio.'),
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
          for (final channel in field.channels)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tag),
                title: Text(channel.name),
                subtitle: Text(
                  'MeshCore · slot ${channel.index} · ${_channelPosts.where((p) => p.channel == channel.index).length} posts this session',
                ),
                selected: selectedChannel == channel.index,
                onTap: () => setState(() {
                  selectedChannel = channel.index;
                  _selectedChannelName = channel.name;
                  verifiedChannel = false;
                  channelMessageInput.clear();
                }),
              ),
            ),
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

  Widget _channelThread(BuildContext context, {bool narrow = false}) {
    final matching = field.channels.where((c) => c.index == selectedChannel);
    if (selectedChannel == null || matching.isEmpty) {
      return const Center(child: Text('Select a channel to open its feed.'));
    }
    final channel = matching.first;
    final posts = _channelPosts.where((p) => p.channel == channel.index);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (narrow)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                selectedChannel = null;
                verifiedChannel = false;
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('All channels'),
            ),
          ),
        Text(
          channel.name,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        Text('MeshCore · channel slot ${channel.index} · this session only'),
        const SizedBox(height: 8),
        const Text(
          'Channel broadcasts appear in order received. MeshCore does not provide Reddit-style reply-to-post links or verified channel senders.',
        ),
        const Divider(height: 28),
        if (posts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No posts in this channel during this session yet.'),
            ),
          ),
        for (final post in posts)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.sender,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(post.text),
                  const SizedBox(height: 8),
                  Text(
                    post.status,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 28),
        Text(
          'Post to ${channel.name}',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        TextField(
          controller: channelMessageInput,
          maxLines: 2,
          maxLength: 133,
          decoration: const InputDecoration(
            labelText: 'Message (UTF-8, max 133 bytes)',
          ),
        ),
        if (field.identity?.radioPreset case final rf?)
          Text(
            'RF: ${rf.frequencyKHz} kHz · ${rf.bandwidthHz} Hz · SF${rf.spreadingFactor} · CR${rf.codingRate}',
          ),
        CheckboxListTile(
          title: Text(
            'I verified RF region, displayed preset, ${channel.name} (slot ${channel.index}) and a reachable peer',
          ),
          value: verifiedChannel,
          onChanged: field.connected
              ? (value) => setState(() => verifiedChannel = value ?? false)
              : null,
        ),
        FilledButton.icon(
          onPressed:
              field.connected &&
                  !field.channelsLoading &&
                  !field.sending &&
                  verifiedChannel
              ? () => _sendChannelPost(context)
              : null,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Post once to selected channel'),
        ),
        const Text(
          'Local radio acceptance is not peer delivery. If a send is interrupted, do not blindly retry.',
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
        verified: verifiedChannel,
      );
      if (!mounted) return;
      setState(() {
        verifiedChannel = false;
        if (result == MeshCoreLocalSendResult.acceptedByRadio) {
          _channelPosts.add(
            _ChannelPost(
              channel: channel,
              sender: 'You · local radio',
              text: text,
              status: 'Accepted locally · peer delivery unverified',
            ),
          );
          channelMessageInput.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => verifiedChannel = false);
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
