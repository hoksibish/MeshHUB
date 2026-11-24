import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/testing.dart';

import 'field_session.dart';
import 'linux_meshcore_ble.dart';

void main() => runApp(const MeshHubApp());

enum MeshHubTheme { light, dark, tactical }

class MeshHubApp extends StatefulWidget {
  const MeshHubApp({super.key});

  @override
  State<MeshHubApp> createState() => _MeshHubAppState();
}

class _MeshHubAppState extends State<MeshHubApp> {
  MeshHubTheme theme = MeshHubTheme.dark;
  MeshProtocol? filter;
  int destination = 0;
  final field = MeshCoreFieldSession();
  final messageInput = TextEditingController();
  final channelInput = TextEditingController(text: '0');
  final keyPrefixInput = TextEditingController();
  bool directMode = false;
  bool showExamples = false;
  bool verifiedDestination = false;

  @override
  void initState() {
    super.initState();
    field.addListener(_refresh);
  }

  void _refresh() {
    if (!field.connected) verifiedDestination = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    field.removeListener(_refresh);
    unawaited(field.disconnect().whenComplete(field.dispose));
    messageInput.dispose();
    channelInput.dispose();
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
              Expanded(child: destination == 0 ? _inbox() : _radios()),
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

  Widget _inbox() {
    final messages = [
      ...field.messages,
      if (showExamples) ...MockRadioAdapter.sampleInbox(),
    ].where((message) => filter == null || message.protocol == filter).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Show simulated examples'),
          subtitle: const Text('Off = live in-memory messages only'),
          value: showExamples,
          onChanged: (value) => setState(() => showExamples = value),
        ),
        if (showExamples) _banner(),
        if (field.messages.isNotEmpty)
          const ListTile(title: Text('LIVE MeshCore · volatile memory only')),
        const SizedBox(height: 12),
        Text('Inbox', style: Theme.of(context).textTheme.headlineMedium),
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
        const SizedBox(height: 12),
        for (final message in messages)
          Card(
            child: ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(message.sender),
              subtitle: Text(message.text),
              trailing: Text(
                message.protocol == MeshProtocol.meshCore
                    ? (message.isSimulated
                          ? 'MeshCore • SIMULATED'
                          : 'MeshCore • LIVE')
                    : 'Meshtastic • SIMULATED',
              ),
            ),
          ),
      ],
    );
  }

  Widget _radios() {
    final info = field.deviceInfo;
    final rf = field.identity?.radioPreset;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Radios', style: Theme.of(context).textTheme.headlineMedium),
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
          style: Theme.of(context).textTheme.titleLarge,
        ),
        ListTile(
          title: Text('Connection: ${field.status}'),
          subtitle: Text(
            'Waiting pushes: ${field.waitingCount} · received: ${field.receiveCount} · malformed: ${field.rejectedFrames} · local sends accepted: ${field.sendCount} · reconnect attempts: ${field.reconnectAttempts}',
          ),
        ),
        const Divider(),
        Text(
          'Prepare test message',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'No automatic sending or retry. Verify region, displayed preset, destination and reachable peer before transmitting.',
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Channel'),
              selected: !directMode,
              onSelected: (_) => setState(() {
                directMode = false;
                verifiedDestination = false;
              }),
            ),
            ChoiceChip(
              label: const Text('Direct contact'),
              selected: directMode,
              onSelected: (_) => setState(() {
                directMode = true;
                verifiedDestination = false;
              }),
            ),
          ],
        ),
        if (!directMode)
          TextField(
            controller: channelInput,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Channel slot (0–${(info?.maxChannels ?? 40) - 1})',
            ),
          ),
        if (directMode)
          TextField(
            controller: keyPrefixInput,
            decoration: const InputDecoration(
              labelText:
                  'Verified contact key prefix (12 lowercase hex characters)',
            ),
          ),
        TextField(
          controller: messageInput,
          maxLines: 2,
          maxLength: 133,
          decoration: const InputDecoration(
            labelText: 'Test message (UTF-8, max 133 bytes)',
          ),
        ),
        CheckboxListTile(
          title: const Text(
            'I verified RF region, displayed preset, selected destination and reachable test peer',
          ),
          value: verifiedDestination,
          onChanged: (value) =>
              setState(() => verifiedDestination = value ?? false),
        ),
        FilledButton(
          onPressed: !field.connected || !verifiedDestination || field.sending
              ? null
              : _sendSelected,
          child: const Text('Send once (local radio acceptance only)'),
        ),
        const Text(
          'Local radio acceptance is not over-the-air or recipient delivery. An interrupted send is uncertain; do not blindly resend.',
        ),
      ],
    );
  }

  void _sendSelected() {
    if (directMode) {
      unawaited(_sendOnce(null));
      return;
    }
    final channel = int.tryParse(channelInput.text);
    if (channel == null || channelInput.text != channel.toString()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid channel slot.')),
      );
      return;
    }
    unawaited(_sendOnce(channel));
  }

  Future<void> _sendOnce(int? channel) async {
    try {
      if (channel == null) {
        await field.sendDirect(
          keyPrefix: keyPrefixInput.text,
          text: messageInput.text,
          verified: verifiedDestination,
        );
      } else {
        await field.sendChannel(
          channel: channel,
          text: messageInput.text,
          verified: verifiedDestination,
        );
      }
      if (mounted) setState(() => verifiedDestination = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
