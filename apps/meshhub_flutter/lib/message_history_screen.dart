import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';

/// Archived content is read-only. A historical slot must never select a live
/// outgoing radio/channel after its identity or key has changed.
class MessageHistoryScreen extends StatefulWidget {
  const MessageHistoryScreen({required this.repository, super.key});
  final MessageHistoryRepository repository;
  @override
  State<MessageHistoryScreen> createState() => _MessageHistoryScreenState();
}

class _MessageHistoryScreenState extends State<MessageHistoryScreen> {
  String query = '';
  MeshProtocol? protocol;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Encrypted history')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            key: const Key('history-search'),
            decoration: const InputDecoration(
              labelText: 'Search saved messages',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value.toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: protocol == null,
                onSelected: (_) => setState(() => protocol = null),
              ),
              for (final p in MeshProtocol.values)
                ChoiceChip(
                  label: Text(
                    p == MeshProtocol.meshCore ? 'MeshCore' : 'Meshtastic',
                  ),
                  selected: protocol == p,
                  onSelected: (_) => setState(() => protocol = p),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            'Saved locally · read-only archive · delivery labels retain their original meaning',
            style: TextStyle(fontSize: 11),
          ),
        ),
        Expanded(
          child: StreamBuilder<void>(
            stream: widget.repository.changes,
            builder: (context, _) => FutureBuilder<List<MessageHistoryEntry>>(
              future: widget.repository.entries(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'History is unavailable. Unlock or retry it in Settings.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final matches =
                    snapshot.data!
                        .where(
                          (e) =>
                              (protocol == null ||
                                  e.message.protocol == protocol) &&
                              '${e.message.text} ${e.message.sender} ${e.conversationName}'
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .toList()
                      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
                if (matches.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty
                          ? 'No saved messages yet.'
                          : 'No matching saved messages.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: matches.length,
                  itemBuilder: (context, index) =>
                      _entry(context, matches[index]),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _entry(BuildContext context, MessageHistoryEntry entry) {
    final message = entry.message;
    final identity = entry.radioIdentity;
    final suffix = identity.length > 8
        ? identity.substring(identity.length - 8)
        : identity;
    final time = entry.recordedAt.toLocal();
    final label =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.conversationName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '${message.protocol == MeshProtocol.meshCore ? 'MeshCore' : 'Meshtastic'} · radio …$suffix · saved $label',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            SelectableText(message.text),
            const SizedBox(height: 10),
            Text(message.sender, style: Theme.of(context).textTheme.bodySmall),
            Text(
              message.deliveryState == MessageDeliveryState.acceptedByLocalRadio
                  ? 'Accepted by local radio · recipient delivery unverified'
                  : 'Received by radio · sender identity unverified',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
