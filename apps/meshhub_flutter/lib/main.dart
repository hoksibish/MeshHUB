import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/testing.dart';

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
    final messages = MockRadioAdapter.sampleInbox()
        .where((message) => filter == null || message.protocol == filter)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _banner(),
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
                    ? 'MeshCore • SIMULATED'
                    : 'Meshtastic • SIMULATED',
              ),
            ),
          ),
      ],
    );
  }

  Widget _radios() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _banner(),
      const SizedBox(height: 12),
      Text('Radios', style: Theme.of(context).textTheme.headlineMedium),
      const ListTile(
        leading: Icon(Icons.bluetooth_disabled),
        title: Text('No real radios connected'),
        subtitle: Text(
          'BLE hardware integration is not active in Milestone 0.',
        ),
      ),
    ],
  );
}
