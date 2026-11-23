import 'dart:async';

import 'meshhub_domain.dart';

/// In-memory bytes only; never connects to a BLE or TCP device.
final class FakeRadioTransport implements RadioTransport {
  FakeRadioTransport(this.protocol);

  @override
  final MeshProtocol protocol;
  final _controller = StreamController<List<int>>.broadcast();
  final _written = <List<int>>[];
  bool _opened = false;
  bool _closed = false;

  bool get isSimulated => true;
  List<List<int>> get writtenFrames => List.unmodifiable(_written);

  @override
  Stream<List<int>> get frames => _controller.stream;

  @override
  Future<void> open() async {
    if (_closed) throw StateError('Fake transport cannot reopen after close');
    _opened = true;
  }

  void injectInbound(List<int> bytes) {
    if (!_opened) throw StateError('Fake transport is not open');
    _controller.add(List.unmodifiable(bytes));
  }

  @override
  Future<void> writeFrame(List<int> bytes) async {
    if (!_opened) throw StateError('Fake transport is not open');
    _written.add(List.unmodifiable(bytes));
  }

  @override
  Future<void> close() async {
    _opened = false;
    _closed = true;
    await _controller.close();
  }
}

/// Ephemeral fixture store. Never writes message content to disk.
final class InMemoryMessageRepository implements MessageRepository {
  InMemoryMessageRepository(List<RadioMessage> samples)
    : _samples = List.unmodifiable(samples);

  final List<RadioMessage> _samples;

  @override
  Future<List<RadioMessage>> forProtocol(MeshProtocol protocol) async =>
      List.unmodifiable(
        _samples.where((message) => message.protocol == protocol),
      );
}

/// Deterministic demo adapter; never opens a Bluetooth socket or transmits RF.
final class MockRadioAdapter implements RadioAdapter {
  const MockRadioAdapter.meshCore() : protocol = MeshProtocol.meshCore;
  const MockRadioAdapter.meshtastic() : protocol = MeshProtocol.meshtastic;

  @override
  final MeshProtocol protocol;

  static List<RadioMessage> sampleInbox() => const [
    RadioMessage(
      id: 'meshcore-demo-1',
      conversationId: 'meshcore-demo',
      protocol: MeshProtocol.meshCore,
      sender: 'MeshCore example',
      text: 'Sample MeshCore conversation — no radio connected',
      isSimulated: true,
    ),
    RadioMessage(
      id: 'meshtastic-demo-1',
      conversationId: 'meshtastic-demo',
      protocol: MeshProtocol.meshtastic,
      sender: 'Meshtastic example',
      text: 'Sample Meshtastic conversation — no radio connected',
      isSimulated: true,
    ),
  ];

  @override
  Stream<RadioMessage> get incomingText => Stream.fromIterable(
    protocol == MeshProtocol.meshCore
        ? sampleInbox().where((message) => message.protocol == protocol)
        : const <RadioMessage>[],
  );

  @override
  Future<SendStatus> sendText({
    required ConversationTarget target,
    required String text,
  }) async {
    if (target.protocol != protocol) {
      throw ArgumentError.value(
        target,
        'target',
        'Protocol does not match adapter',
      );
    }
    return SendStatus.simulated;
  }

  @override
  Future<List<RadioDevice>> discover() async => [
    RadioDevice(
      id: '${protocol.name}-demo-radio',
      displayName: '${protocol.name} sample radio',
      protocol: protocol,
      isSimulated: true,
      capabilities: protocol == MeshProtocol.meshCore
          ? const {RadioCapability.receiveText}
          : const {},
    ),
  ];
}
