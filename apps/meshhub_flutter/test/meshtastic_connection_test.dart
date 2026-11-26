import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/meshtastic_ble.dart';
import 'package:meshhub_flutter/meshtastic_connection_panel.dart';
import 'package:meshhub_flutter/meshtastic_connection_protocol.dart';
import 'package:meshhub_flutter/meshtastic_session.dart';

const radio = MeshCoreBleObservation('/test/heltec', 'Meshtastic_test', [
  meshtasticServiceUuid,
]);

class PairingDevice extends Fake implements BlueZDevice {
  PairingDevice(String id) : path = DBusObjectPath(id);
  @override
  DBusObjectPath path;
}

List<int> uintField(int field, int value) {
  final encoded = MeshtasticConnectionReport.requestConfig(value);
  return [field << 3, ...encoded.skip(1)];
}

List<int> messageField(int field, List<int> value) => [
  (field << 3) | 2,
  value.length,
  ...value,
];

class FakeLink implements MeshtasticBleLink {
  final data = StreamController<void>.broadcast();
  final lost = StreamController<void>.broadcast();
  final queue = Queue<List<int>>();
  final writes = <List<int>>[];
  bool requirePin = false, completeConfig = true, includeNode = true;
  bool closed = false, malformed = false;
  int? staleNonce;
  String? pinReceived;
  int readsInFlight = 0, maxReadsInFlight = 0;
  Completer<void>? holdRead;
  @override
  Stream<void> get dataAvailable => data.stream;
  @override
  Stream<void> get disconnected => lost.stream;
  @override
  Future<void> open(
    String id,
    MeshtasticPinRequest requestPin,
    void Function() cancelPrompt,
  ) async {
    expect(id, radio.id);
    if (requirePin) {
      pinReceived = await requestPin();
      cancelPrompt();
      if (pinReceived == null) throw StateError('Pairing cancelled');
    }
  }

  @override
  Future<void> writeConfigRequest(List<int> bytes) async {
    writes.add(List.of(bytes));
    expect(bytes.first, 0x18); // Only want_config_id, never a mesh packet.
    if (malformed) {
      queue.add([0x1a, 0x7f]);
      return;
    }
    if (includeNode) queue.add(messageField(3, uintField(1, 42)));
    queue.add(
      messageField(13, [
        ...messageField(1, utf8.encode('2.7.26')),
        ...uintField(9, 43),
      ]),
    );
    if (completeConfig) {
      queue.add(
        staleNonce == null
            ? [0x38, ...bytes.skip(1)]
            : uintField(7, staleNonce!),
      );
    }
  }

  @override
  Future<List<int>> readFromRadio() async {
    readsInFlight++;
    if (readsInFlight > maxReadsInFlight) maxReadsInFlight = readsInFlight;
    try {
      await holdRead?.future;
      return queue.isEmpty ? [] : queue.removeFirst();
    } finally {
      readsInFlight--;
    }
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    holdRead?.complete();
    holdRead = null;
    await data.close();
    await lost.close();
  }
}

MeshtasticSession sessionFor(
  FakeLink link, {
  Duration timeout = const Duration(seconds: 1),
}) => MeshtasticSession(
  scan: (_) async => [
    radio,
    const MeshCoreBleObservation('/test/meshcore', 'Heltec', [
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    ]),
  ],
  linkFactory: () => link,
  handshakeTimeout: timeout,
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('pairing agent only requests a PIN for the selected device', () async {
    var prompts = 0, cancellations = 0;
    final agent = MeshtasticPairingAgent(
      radio.id,
      () async {
        prompts++;
        return '012345';
      },
      () {
        cancellations++;
      },
    );
    final wrong = await agent.requestPasskey(PairingDevice('/test/other'));
    expect(wrong.response, isA<DBusMethodErrorResponse>());
    expect(prompts, 0);
    final passkey = await agent.requestPasskey(PairingDevice(radio.id));
    expect(passkey.response.returnValues.single, const DBusUint32(12345));
    final pin = await agent.requestPinCode(PairingDevice(radio.id));
    expect(pin.response.returnValues.single, const DBusString('012345'));
    expect(cancellations, 2);
    expect(
      (await agent.requestConfirmation(
        PairingDevice(radio.id),
        12345,
      )).response,
      isA<DBusMethodErrorResponse>(),
    );
    await agent.release();
    expect(
      (await agent.requestPasskey(PairingDevice(radio.id))).response,
      isA<DBusMethodErrorResponse>(),
    );
    expect(prompts, 2);
  });

  test('pairing agent rejects cancelled and malformed PINs', () async {
    for (final value in <String?>[null, '', '123', '12345x', '1234567']) {
      final agent = MeshtasticPairingAgent(radio.id, () async => value, () {});
      expect(
        (await agent.requestPasskey(PairingDevice(radio.id))).response,
        isA<DBusMethodErrorResponse>(),
      );
    }
  });

  test(
    'config request and real schema readback use Meshtastic field numbers',
    () {
      expect(MeshtasticConnectionReport.requestConfig(300), [0x18, 0xac, 2]);
      final mine = MeshtasticConnectionReport.decode([0x1a, 2, 8, 42]);
      expect(mine.nodeNumber, 42);
      expect(
        MeshtasticConnectionReport.decode([0x38, 0xac, 2]).configCompleteId,
        300,
      );
      // Unknown fixed32/fixed64/config bytes are safely skipped, not persisted.
      expect(
        MeshtasticConnectionReport.decode([
          0x0d,
          0,
          0,
          0,
          0,
          0x09,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0x2a,
          2,
          8,
          1,
        ]).nodeNumber,
        isNull,
      );
    },
  );

  test(
    'malformed lengths, types, uint32 overflow and oversized BLE frames reject',
    () {
      for (final frame in <List<int>>[
        [0x1a, 127],
        [0x38, 0x80],
        [0],
        [0x3a, 0],
        [0x38, 0x80, 0x80, 0x80, 0x80, 0x10],
        [0x38, ...List.filled(10, 0xff)],
        List.filled(513, 0),
        [-1],
        [0x1b],
      ]) {
        expect(
          () => MeshtasticConnectionReport.decode(frame),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'service discovery excludes MeshCore and verifies config before ready',
    () async {
      final link = FakeLink();
      final session = sessionFor(link);
      await session.discover();
      expect(session.candidates, [radio]);
      await session.connect(radio);
      expect(session.connected, true);
      expect(session.nodeNumber, 42);
      expect(session.firmwareVersion, '2.7.26');
      expect(session.hardwareModel, 43);
      expect(link.writes, hasLength(1));
      await session.disconnect();
      expect(link.closed, true);
      expect(session.connected, false);
      session.dispose();
    },
  );

  test('PIN pairing accepts six digits including a leading zero; never retransmits', () async {
    final link = FakeLink()..requirePin = true;
    final session = sessionFor(link);
    await session.discover();
    final connection = session.connect(radio);
    await flush();
    expect(session.awaitingPin, true);
    session.submitPin('123');
    expect(session.awaitingPin, true);
    session.submitPin('012345');
    await connection;
    expect(link.pinReceived, '012345');
    expect(session.awaitingPin, false);
    expect(session.connected, true);
    expect(link.writes, hasLength(1));
    await session.disconnect();
    session.dispose();
  });

  test(
    'cancel while PIN is pending closes link without a config or RF write',
    () async {
      final link = FakeLink()..requirePin = true;
      final session = sessionFor(link);
      await session.discover();
      final connection = session.connect(radio);
      await flush();
      await session.disconnect();
      await connection;
      expect(session.active, false);
      expect(session.awaitingPin, false);
      expect(link.writes, isEmpty);
      expect(link.closed, true);
      session.dispose();
    },
  );

  test(
    'stale nonce, missing node and incomplete config never mark connected',
    () async {
      for (final link in [
        FakeLink()..staleNonce = 0,
        FakeLink()..includeNode = false,
        FakeLink()..completeConfig = false,
      ]) {
        final session = sessionFor(
          link,
          timeout: const Duration(milliseconds: 20),
        );
        await session.discover();
        await session.connect(radio);
        expect(session.connected, false);
        expect(session.error, isNotNull);
        expect(link.closed, true);
        expect(link.writes, hasLength(1));
        session.dispose();
      }
    },
  );

  test(
    'notification bursts serialize FIFO reads and disconnect clears ready',
    () async {
      final link = FakeLink()..holdRead = Completer<void>();
      final session = sessionFor(link);
      await session.discover();
      final connection = session.connect(radio);
      await flush();
      for (var i = 0; i < 10; i++) {
        link.data.add(null);
      }
      await flush();
      link.holdRead!.complete();
      link.holdRead = null;
      await connection;
      expect(link.maxReadsInFlight, 1);
      link.lost.add(null);
      await flush();
      expect(session.connected, false);
      expect(link.closed, true);
      expect(link.writes, hasLength(1));
      session.dispose();
    },
  );

  test(
    'malformed device response closes link instead of marking ready',
    () async {
      final link = FakeLink()..malformed = true;
      final session = sessionFor(link);
      await session.discover();
      await session.connect(radio);
      await flush();
      expect(session.connected, false);
      expect(link.closed, true);
      session.dispose();
    },
  );

  testWidgets(
    'pairing PIN appears inside MeshHub and clears after authentication',
    (tester) async {
      final link = FakeLink()..requirePin = true;
      final session = sessionFor(link);
      await session.discover();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeshtasticConnectionPanel(session: session),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pair & connect'));
      await tester.pump();
      expect(find.byKey(const Key('meshtastic-pairing-pin')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('meshtastic-pairing-pin')),
        '012345',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Submit pairing PIN'));
      await tester.tap(find.text('Submit pairing PIN'));
      await tester.pumpAndSettle();
      expect(session.connected, true);
      expect(find.byKey(const Key('meshtastic-pairing-pin')), findsNothing);
      expect(find.text('Hardware: Heltec V3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(session.disconnect);
      session.dispose();
    },
  );
}
