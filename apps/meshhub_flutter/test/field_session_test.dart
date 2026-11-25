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
  // Null simulates no local-radio ACK, which must never trigger a replay.
  List<int>? channelSendReply = const [0];
  Completer<void>? holdSend;
  Completer<void>? holdChannel;
  int maxChannels = 2;
  final channelNames = <int, String>{};
  List<int>? Function(int)? channelReply;
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
      info[3] = maxChannels;
      info.setRange(20, 29, 'Heltec V3'.codeUnits);
      info.setRange(60, 67, 'v1.18.0'.codeUnits);
      incoming.add(info);
    } else if (frame[0] == 10) {
      incoming.add([10]);
    } else if (frame[0] == 0x1f) {
      await holdChannel?.future;
      if (online) {
        final reply =
            channelReply?.call(frame[1]) ??
            [
              0x12,
              frame[1],
              ...List<int>.generate(
                32,
                (i) => i < (channelNames[frame[1]] ?? '').codeUnits.length
                    ? (channelNames[frame[1]] ?? '').codeUnits[i]
                    : 0,
              ),
              ...List<int>.filled(16, 0xa5),
            ];
        incoming.add(reply);
      }
    } else if (frame[0] == 3) {
      if (channelSendReply != null) incoming.add(channelSendReply!);
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
    'automatic discovery reads sparse slots and never sends or exposes secrets',
    () async {
      device.maxChannels = 4;
      device.channelNames.addAll({0: 'Town', 3: 'Field'});
      await session.connect(candidate);
      expect(device.writes, [
        [1, ...List<int>.filled(7, 0), ...'MeshHub'.codeUnits],
        [22, 3],
        [0x1f, 0],
        [0x1f, 1],
        [0x1f, 2],
        [0x1f, 3],
      ]);
      expect(session.channels.map((c) => '${c.index}:${c.name}'), [
        '0:Town',
        '3:Field',
      ]);
      expect(session.channelsLoading, false);
      expect(session.channelsError, isNull);
      expect(session.channels.toString(), isNot(contains('165')));
      expect(() => session.channels.clear(), throwsUnsupportedError);
    },
  );

  test('malformed or mismatched channel reply reports error and clears old snapshot', () async {
    device.maxChannels = 2;
    device.channelNames[0] = 'Old';
    await session.connect(candidate);
    expect(session.channels.single.name, 'Old');
    device.channelReply = (index) => [
      0x12,
      index + 1,
      ...List<int>.filled(48, 0),
    ];
    await session.refreshChannels();
    expect(session.channels, isEmpty);
    expect(session.channelsError, isNotNull);
    expect(session.channelsError, isNot(contains('165')));
    device.channelReply = (_) => [0x12, 0];
    await session.refreshChannels();
    expect(session.channelsError, isNotNull);
  });

  test('disconnect during refresh clears snapshot and prevents subsequent channel writes', () async {
    device.maxChannels = 3;
    device.channelNames[0] = 'Old';
    await session.connect(candidate);
    device.holdChannel = Completer<void>();
    final refresh = session.refreshChannels();
    await Future<void>.delayed(Duration.zero);
    expect(session.channelsLoading, true);
    final written = device.writes.length;
    await session.disconnect();
    device.holdChannel!.complete();
    await refresh;
    expect(device.writes.length, written);
    expect(session.channels, isEmpty);
    expect(session.channelsLoading, false);
    expect(session.channelsError, isNull);
  });

  test('channel refresh serializes with send and does not replay queued send on disconnect', () async {
    device.maxChannels = 1;
    await session.connect(candidate);
    device.holdChannel = Completer<void>();
    final refresh = session.refreshChannels();
    await Future<void>.delayed(Duration.zero);
    final send = session.sendChannel(
      channel: 0,
      text: 'do not replay',
      verified: true,
    );
    expect(device.writes.where((f) => f.first == 3), isEmpty);
    await session.disconnect();
    device.holdChannel!.complete();
    await refresh;
    await expectLater(send, throwsStateError);
    expect(device.writes.where((f) => f.first == 3), isEmpty);
  });

  test('waiting drain queues behind channel refresh without consuming its response', () async {
    device.maxChannels = 1;
    device.holdChannel = Completer<void>();
    final connection = session.connect(candidate);
    await Future<void>.delayed(Duration.zero);
    device.incoming.add([0x83]);
    expect(device.writes.map((f) => f.first), [1, 22, 0x1f]);
    device.holdChannel!.complete();
    await connection;
    await Future<void>.delayed(Duration.zero);
    expect(device.writes.map((f) => f.first), [1, 22, 0x1f, 10]);
    expect(session.channelsError, isNull);
  });

  test(
    'physical drop clears channel names and never replays uncertain send',
    () async {
      device.maxChannels = 1;
      device.channelNames[0] = 'Known';
      await session.connect(candidate);
      device.holdSend = Completer<void>();
      final send = session.sendChannel(
        channel: 0,
        text: 'uncertain',
        verified: true,
      );
      await Future<void>.delayed(Duration.zero);
      device.drop();
      expect(session.channels, isEmpty);
      expect(session.channelsLoading, false);
      device.holdSend!.complete();
      await expectLater(send, throwsStateError);
      expect(device.writes.where((f) => f.first == 3).length, 1);
      expect(session.sendCount, 0);
    },
  );

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
      expect(device.writes.map((e) => e.first), [1, 22, 0x1f, 0x1f]);
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

  test('exact duplicate is suppressed briefly but allowed later', () async {
    await session.disconnect();
    var now = DateTime.utc(2026, 11, 24);
    session = MeshCoreFieldSession(
      scan: (_) async => [candidate],
      transportFactory: (_) => device,
      clock: () => now,
    );
    await session.connect(candidate);
    final message = [
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
      ...'Repeated message'.codeUnits,
    ];
    device.incoming.add(message);
    device.incoming.add(message);
    expect(session.receiveCount, 1);
    now = now.add(const Duration(seconds: 4));
    device.incoming.add(message);
    expect(session.receiveCount, 2);
    expect(session.messages.length, 2);
  });

  test('dedupe cache is reset across explicit disconnect', () async {
    await session.connect(candidate);
    final message = [
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
      ...'After reconnect'.codeUnits,
    ];
    device.incoming.add(message);
    expect(session.receiveCount, 1);
    await session.disconnect();
    await session.connect(candidate);
    device.incoming.add(message);
    expect(session.receiveCount, 2);
  });

  test(
    'send remains blocked until preset and destination are explicitly verified',
    () async {
      await session.connect(candidate);
      await expectLater(
        session.sendChannel(channel: 0, text: 'test', verified: false),
        throwsStateError,
      );
      expect(device.writes.length, 4);
      final result = await session.sendChannel(
        channel: 0,
        text: 'test',
        verified: true,
      );
      expect(result.name, 'acceptedByRadio');
      expect(session.sendCount, 1);
      expect(session.messages.single.isOutgoing, true);
      expect(session.messages.single.conversationId, 'meshcore-channel-0');
      expect(session.messages.single.isSimulated, false);
      expect(
        session.messages.single.deliveryState.name,
        'acceptedByLocalRadio',
      );
      expect(device.writes.last.first, 3);
    },
  );

  test('local acceptance is counted without claiming peer delivery', () async {
    await session.connect(candidate);
    final first = await session.sendChannel(
      channel: 0,
      text: 'first',
      verified: true,
    );
    final second = await session.sendChannel(
      channel: 0,
      text: 'second',
      verified: true,
    );
    expect(first.name, 'acceptedByRadio');
    expect(second.name, 'acceptedByRadio');
    expect(session.sendRequestCount, 2);
    expect(session.sendCount, 2);
    expect(session.rejectedSendCount, 0);
    expect(session.uncertainSendCount, 0);
    expect(session.messages.map((m) => m.text), ['first', 'second']);
    expect(session.messages.every((m) => m.isOutgoing), true);
    expect(session.lastSendOutcome, contains('peer delivery unverified'));
    expect(device.writes.where((f) => f.first == 3).length, 2);
  });

  test('radio-rejected ACK does not create an outgoing message', () async {
    await session.connect(candidate);
    device.channelSendReply = [1, 0];
    final result = await session.sendChannel(
      channel: 0,
      text: 'reject me',
      verified: true,
    );
    expect(result.name, 'rejectedByRadio');
    expect(session.sendRequestCount, 1);
    expect(session.sendCount, 0);
    expect(session.rejectedSendCount, 1);
    expect(session.uncertainSendCount, 0);
    expect(session.messages, isEmpty);
    expect(session.lastSendOutcome, 'Rejected by local radio');
    expect(device.writes.where((f) => f.first == 3).length, 1);
  });

  test('missing ACK remains uncertain and never causes an automatic resend', () async {
    await session.disconnect();
    session = MeshCoreFieldSession(
      scan: (_) async => [candidate],
      transportFactory: (_) => device,
      responseTimeout: const Duration(milliseconds: 20),
    );
    await session.connect(candidate);
    device.channelSendReply = null;
    await expectLater(
      session.sendChannel(channel: 0, text: 'no ack', verified: true),
      throwsA(isA<TimeoutException>()),
    );
    expect(session.sendRequestCount, 1);
    expect(session.sendCount, 0);
    expect(session.rejectedSendCount, 0);
    expect(session.uncertainSendCount, 1);
    expect(session.messages, isEmpty);
    expect(session.lastSendOutcome, contains('Uncertain'));
    expect(session.status, contains('do not retry blindly'));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(device.writes.where((f) => f.first == 3).length, 1);
  });

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
      expect(device.writes.length, 4);
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
    expect(device.writes.map((e) => e.first), [
      1,
      22,
      0x1f,
      0x1f,
      1,
      22,
      0x1f,
      0x1f,
    ]);
  });

  test(
    'a disconnect removes readiness without replaying a prepared send',
    () async {
      await session.connect(candidate);
      device.drop();
      await Future<void>.delayed(Duration.zero);
      expect(session.connected, false);
      expect(device.writes.map((e) => e.first), [1, 22, 0x1f, 0x1f]);
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
      expect(device.writes.map((f) => f.first), [1, 22, 0x1f, 0x1f]);
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
