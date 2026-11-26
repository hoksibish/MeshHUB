import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/field_session.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/meshcore_pairing_prompt.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

import 'field_session_test.dart' show FieldTransport;
import 'meshcore_ble_transport_test.dart' show FakeDevice;

const candidate = MeshCoreBleCandidate(
  'selected-path',
  'Test MeshCore',
  MeshCoreCandidateAssessment.serviceUuidKnown,
  true,
);

class PairingFieldTransport extends FieldTransport {
  PairingFieldTransport(this.requestPin) : super(candidate.id);
  final Future<String?> Function() requestPin;
  @override
  Future<void> open() async {
    final pin = await requestPin();
    if (pin == null) throw StateError('Cancelled');
    if (pin != '012345') throw StateError('Wrong synthetic PIN');
    await super.open();
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'fresh MeshCore session waits for PIN before any Companion command',
    () async {
      late MeshCoreFieldSession session;
      late PairingFieldTransport transport;
      session = MeshCoreFieldSession(
        transportFactory: (_) {
          transport = PairingFieldTransport(session.requestPairingPin);
          return transport;
        },
      );
      final connection = session.connect(candidate);
      await flush();
      expect(session.awaitingPairingPin, true);
      expect(session.connected, false);
      expect(transport.writes, isEmpty);
      session.submitPairingPin('123');
      expect(session.awaitingPairingPin, true);
      session.submitPairingPin('012345');
      await connection;
      expect(session.connected, true);
      expect(session.awaitingPairingPin, false);
      expect(
        transport.writes.where((f) => f.first == 2 || f.first == 3),
        isEmpty,
      );
      await session.disconnect();
      session.dispose();
    },
  );

  test(
    'cancelling PIN entry makes no commands and ignores a late PIN',
    () async {
      late MeshCoreFieldSession session;
      late PairingFieldTransport transport;
      session = MeshCoreFieldSession(
        transportFactory: (_) {
          transport = PairingFieldTransport(session.requestPairingPin);
          return transport;
        },
      );
      final connection = session.connect(candidate);
      await flush();
      await session.disconnect();
      session.submitPairingPin('012345');
      await connection;
      expect(session.awaitingPairingPin, false);
      expect(session.connecting, false);
      expect(session.connected, false);
      expect(transport.writes, isEmpty);
      expect(session.error, isNull);
      session.dispose();
    },
  );

  test(
    'wrong PIN clears prompt, leaves disconnected and permits manual retry',
    () async {
      late MeshCoreFieldSession session;
      final transports = <PairingFieldTransport>[];
      session = MeshCoreFieldSession(
        transportFactory: (_) {
          final transport = PairingFieldTransport(session.requestPairingPin);
          transports.add(transport);
          return transport;
        },
      );
      var connection = session.connect(candidate);
      await flush();
      session.submitPairingPin('654321');
      await connection;
      expect(session.connected, false);
      expect(session.connecting, false);
      expect(session.awaitingPairingPin, false);
      expect(session.error, isNotNull);
      expect(transports.single.writes, isEmpty);
      connection = session.connect(candidate);
      await flush();
      session.submitPairingPin('012345');
      await connection;
      expect(session.connected, true);
      await session.disconnect();
      session.dispose();
    },
  );

  test(
    'bonded MeshCore device skips pairing even when manual pairing is enabled',
    () async {
      final device = FakeDevice(candidate.id)..resolve();
      final transport = MeshCoreBleTransport(
        selectedId: candidate.id,
        allowPairing: true,
        deviceFactory: (_) async => device,
      );
      await transport.open();
      expect(transport.ready, true);
      expect(device.calls, isNot(contains('pair')));
      await transport.close();
    },
  );

  test('automatic reconnect never opens an interactive PIN flow', () async {
    final device = FakeDevice(candidate.id)..pairedValue = false;
    final transport = MeshCoreBleTransport(
      selectedId: candidate.id,
      allowPairing: true,
      deviceFactory: (_) async => device,
    );
    final session = MeshCoreFieldSession(
      allowPairing: true,
      transportFactory: (_) => transport,
    );
    await session.connect(candidate, retry: true);
    expect(device.calls, isEmpty);
    expect(session.awaitingPairingPin, false);
    expect(session.connected, false);
    await session.disconnect();
    session.dispose();
  });

  test(
    'default read-only field session refuses interactive pairing transports',
    () async {
      final device = FakeDevice(candidate.id)..pairedValue = false;
      final transport = MeshCoreBleTransport(
        selectedId: candidate.id,
        allowPairing: true,
        deviceFactory: (_) async => device,
      );
      final session = MeshCoreFieldSession(transportFactory: (_) => transport);
      await session.connect(candidate);
      expect(device.calls, isEmpty);
      expect(session.awaitingPairingPin, false);
      expect(session.connected, false);
      await session.disconnect();
      session.dispose();
    },
  );

  testWidgets('MeshCore PIN is entered inside Hub and submission clears it', (
    tester,
  ) async {
    final session = MeshCoreFieldSession()..connecting = true;
    final pinResponse = session.requestPairingPin();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeshCorePairingPrompt(session: session),
          ),
        ),
      ),
    );
    await tester.pump();
    final pin = find.byKey(const Key('meshcore-pairing-pin'));
    expect(tester.widget<TextField>(pin).obscureText, true);
    await tester.enterText(pin, '012345');
    await tester.pump();
    await tester.tap(find.text('Submit MeshCore PIN'));
    await tester.pumpAndSettle();
    expect(await pinResponse, '012345');
    expect(session.awaitingPairingPin, false);
    expect(tester.widget<TextField>(pin).controller!.text, isEmpty);
    await tester.runAsync(session.disconnect);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
