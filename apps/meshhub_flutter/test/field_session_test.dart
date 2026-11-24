import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/field_session.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

class FieldFakeTimer implements Timer {
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
}

class FieldTransport extends MeshCoreBleTransport {
  FieldTransport(String id) : super(selectedId: id);
  final incoming = StreamController<List<int>>.broadcast(sync: true);
  final states = StreamController<bool>.broadcast(sync: true);
  final writes = <List<int>>[];
  bool online = false;
  bool failSend = false;
  Completer<void>? holdSend;
  @override
  bool get ready => online;
  @override
  Stream<bool> get readiness => states.stream;
  @override
  Stream<List<int>> get frames => incoming.stream;
  @override
  Future<void> open() async {
    online = true;
    states.add(true);
  }

  @override
  Future<void> close() async {
    online = false;
    states.add(false);
  }

  @override
  Future<void> writeFrame(List<int> frame) async {
    if (!online) throw StateError('offline');
    writes.add(List.of(frame));
    if (failSend && (frame.first == 2 || frame.first == 3)) {
      throw StateError('simulated write failure');
    }
    if (frame.first == 2 || frame.first == 3) await holdSend?.future;
    if (frame[0] == 1) {
      final info = List<int>.filled(58, 0)..[0] = 5;
      info[4] = 1;
      info.setRange(48, 52, [189, 228, 13, 0]);
      info.setRange(52, 56, [36, 244, 0, 0]);
      info[56] = 7;
      info[57] = 5;
      incoming.add(info);
    } else if (frame[0] == 22) {
      final info = List<int>.filled(80, 0)..[0] = 13;
      info[1] = 14;
      info[3] = 40;
      info.setRange(20, 29, 'Heltec V3'.codeUnits);
      info.setRange(60, 67, 'v1.18.0'.codeUnits);
      incoming.add(info);
    } else if (frame[0] == 10) {
      incoming.add([10]);
    } else if (frame[0] == 3) {
      incoming.add([0]);
    } else if (frame[0] == 2) {
      incoming.add([6, ...List<int>.filled(9, 0)]);
    }
  }

  void drop() {
    online = false;
    states.add(false);
  }
}

void main() {
  const candidate = MeshCoreBleCandidate(
    'selected-path',
    'My Heltec',
    MeshCoreCandidateAssessment.serviceUuidKnown,
    true,
  );
  late FieldTransport device;
  late MeshCoreFieldSession session;
  setUp(() {
    device = FieldTransport(candidate.id);
    session = MeshCoreFieldSession(
      scan: (_) async => [candidate],
      transportFactory: (id) {
        expect(id, candidate.id);
        return device;
      },
    );
  });
  tearDown(() async {
    await session.disconnect();
  });

  test(
    'explicit discovery and connect read real metadata, never send RF',
    () async {
      await session.discover();
      expect(session.candidates.single.name, 'My Heltec');
      await session.connect(candidate);
      expect(session.connected, true);
      expect(session.deviceInfo?.model, 'Heltec V3');
      expect(session.deviceInfo?.version, 'v1.18.0');
      expect(session.identity?.radioPreset.frequencyKHz, 910525);
      expect(device.writes.map((e) => e.first), [1, 22]);
    },
  );

  test(
    'waiting push drains to in-memory inbox once, without simulation',
    () async {
      await session.connect(candidate);
      final msg = [
        17,
        4,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        ...'Field hello'.codeUnits,
      ];
      device.incoming.add([0x83]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      device.incoming.add(msg);
      device.incoming.add(msg);
      expect(session.messages.length, 1);
      expect(session.messages.single.text, 'Field hello');
      expect(session.messages.single.isSimulated, false);
      expect(device.writes.last.first, 10);
      expect(session.receiveCount, 1);
    },
  );

  test(
    'send remains blocked until preset and destination are explicitly verified',
    () async {
      await session.connect(candidate);
      await expectLater(
        session.sendChannel(channel: 0, text: 'test', verified: false),
        throwsStateError,
      );
      expect(device.writes.length, 2);
      final result = await session.sendChannel(
        channel: 0,
        text: 'test',
        verified: true,
      );
      expect(result.name, 'acceptedByRadio');
      expect(session.sendCount, 1);
      expect(device.writes.last.first, 3);
    },
  );

  test(
    'direct send validates selected contact prefix and explicit confirmation',
    () async {
      await session.connect(candidate);
      await expectLater(
        session.sendDirect(
          keyPrefix: 'aabbccddeeff',
          text: 'test',
          verified: false,
        ),
        throwsStateError,
      );
      await expectLater(
        session.sendDirect(keyPrefix: 'INVALID', text: 'test', verified: true),
        throwsArgumentError,
      );
      expect(device.writes.length, 2);
      final result = await session.sendDirect(
        keyPrefix: 'aabbccddeeff',
        text: 'test',
        verified: true,
      );
      expect(result.name, 'acceptedByRadio');
      expect(device.writes.last.first, 2);
    },
  );

  test('unexpected physical-style drop reopens exact device and re-handshakes without send replay', () async {
    await session.disconnect();
    void Function()? fire;
    Duration? delay;
    session = MeshCoreFieldSession(
      scan: (_) async => [candidate],
      transportFactory: (id) {
        expect(id, candidate.id);
        return device;
      },
      scheduleRetry: (duration, callback) {
        delay = duration;
        fire = callback;
        return FieldFakeTimer();
      },
    );
    await session.connect(candidate);
    device.drop();
    expect(session.connected, false);
    expect(delay, const Duration(seconds: 1));
    fire!();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(session.connected, true);
    expect(session.reconnectAttempts, 1);
    expect(device.writes.map((e) => e.first), [1, 22, 1, 22]);
  });

  test(
    'a disconnect removes readiness without replaying a prepared send',
    () async {
      await session.connect(candidate);
      device.drop();
      await Future<void>.delayed(Duration.zero);
      expect(session.connected, false);
      expect(device.writes.map((e) => e.first), [1, 22]);
    },
  );

  test(
    'concurrent send is rejected instead of duplicating RF commands',
    () async {
      await session.connect(candidate);
      device.holdSend = Completer<void>();
      final first = session.sendChannel(
        channel: 0,
        text: 'test',
        verified: true,
      );
      await expectLater(
        session.sendChannel(channel: 0, text: 'test', verified: true),
        throwsStateError,
      );
      device.holdSend!.complete();
      await first;
      expect(device.writes.where((f) => f.first == 3).length, 1);
    },
  );

  test(
    'read-only probe observes waiting push without draining a real queue',
    () async {
      await session.disconnect();
      session = MeshCoreFieldSession(
        scan: (_) async => [candidate],
        transportFactory: (_) => device,
        receiveMessages: false,
      );
      await session.connect(candidate);
      device.incoming.add([0x83]);
      await Future<void>.delayed(Duration.zero);
      expect(session.waitingCount, 1);
      expect(device.writes.map((f) => f.first), [1, 22]);
    },
  );

  test(
    'failed write cancels pending response rather than leaking timeout',
    () async {
      await session.disconnect();
      session = MeshCoreFieldSession(
        scan: (_) async => [candidate],
        transportFactory: (_) => device,
        responseTimeout: const Duration(milliseconds: 20),
      );
      await session.connect(candidate);
      device.failSend = true;
      await expectLater(
        session.sendChannel(channel: 0, text: 'test', verified: true),
        throwsStateError,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(session.status, contains('uncertain'));
    },
  );
}
