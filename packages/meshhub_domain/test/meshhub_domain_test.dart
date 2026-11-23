import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/testing.dart';

void main() {
  test(
    'mock radio reports simulation and protocol-specific capabilities',
    () async {
      final adapter = MockRadioAdapter.meshCore();
      final devices = await adapter.discover();

      expect(adapter.protocol, MeshProtocol.meshCore);
      expect(devices, hasLength(1));
      expect(devices.single.isSimulated, isTrue);
      expect(
        devices.single.capabilities,
        contains(RadioCapability.receiveText),
      );
      expect(
        devices.single.capabilities,
        isNot(contains(RadioCapability.rfTransmit)),
      );
    },
  );

  test('sample inbox retains separate protocol identities', () {
    final messages = MockRadioAdapter.sampleInbox();
    expect(messages.map((message) => message.protocol).toSet(), {
      MeshProtocol.meshCore,
      MeshProtocol.meshtastic,
    });
    expect(messages.every((message) => message.isSimulated), isTrue);
    expect(
      messages.map((message) => message.conversationId).toSet(),
      hasLength(2),
    );
  });

  test('mock send rejects a conversation on the other protocol', () async {
    await expectLater(
      MockRadioAdapter.meshCore().sendText(
        target: const ConversationTarget(
          id: 'meshtastic-demo',
          protocol: MeshProtocol.meshtastic,
        ),
        text: 'hello',
      ),
      throwsArgumentError,
    );
  });

  test('mock send accepts matching targets and never claims RF', () async {
    for (final adapter in [
      MockRadioAdapter.meshCore(),
      MockRadioAdapter.meshtastic(),
    ]) {
      final result = await adapter.sendText(
        target: ConversationTarget(id: 'shared-id', protocol: adapter.protocol),
        text: 'hello',
      );
      expect(result, SendStatus.simulated);
    }
    await expectLater(
      MockRadioAdapter.meshtastic().sendText(
        target: const ConversationTarget(
          id: 'shared-id',
          protocol: MeshProtocol.meshCore,
        ),
        text: 'hello',
      ),
      throwsArgumentError,
    );
  });

  test(
    'incoming text streams contain only simulated own-protocol messages',
    () async {
      for (final adapter in [
        MockRadioAdapter.meshCore(),
        MockRadioAdapter.meshtastic(),
      ]) {
        final messages = await adapter.incomingText.toList();
        if (adapter.protocol == MeshProtocol.meshtastic) {
          expect(messages, isEmpty); // This mock does not claim receiveText.
          continue;
        }
        expect(messages, hasLength(1));
        expect(messages.single.protocol, adapter.protocol);
        expect(messages.single.isSimulated, isTrue);
        expect(messages.single.id, 'meshcore-demo-1');
      }
    },
  );

  test('Meshtastic adapter has independent capabilities', () async {
    final core = (await MockRadioAdapter.meshCore().discover()).single;
    final meshtastic = (await MockRadioAdapter.meshtastic().discover()).single;
    expect(meshtastic.protocol, MeshProtocol.meshtastic);
    expect(meshtastic.capabilities, isEmpty);
    expect(core.capabilities, contains(RadioCapability.receiveText));
    expect(meshtastic.isSimulated, isTrue);
  });

  test(
    'mock message repository only retains protocol-specific samples',
    () async {
      final repository = InMemoryMessageRepository(
        MockRadioAdapter.sampleInbox(),
      );
      final core = await repository.forProtocol(MeshProtocol.meshCore);
      expect(core, hasLength(1));
      expect(core.single.protocol, MeshProtocol.meshCore);
      expect(core.single.isSimulated, isTrue);
    },
  );

  test('fake transport replays bytes without opening a radio', () async {
    final transport = FakeRadioTransport(MeshProtocol.meshCore);
    await transport.open();
    final next = transport.frames.first;
    transport.injectInbound([1, 2, 3]);
    expect(await next, [1, 2, 3]);
    await transport.writeFrame([4]);
    expect(transport.writtenFrames, [
      [4],
    ]);
    expect(transport.isSimulated, isTrue);
    await transport.close();
  });

  test('closed fake transport refuses reopening', () async {
    final transport = FakeRadioTransport(MeshProtocol.meshCore);
    await transport.open();
    await transport.close();
    await expectLater(transport.open(), throwsStateError);
  });
}
