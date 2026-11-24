import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';
import 'package:meshhub_flutter/meshcore_reconnect.dart';

class FakeTimer implements Timer {
  FakeTimer(this.fire);
  final void Function() fire;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void elapse() {
    if (!active) return;
    active = false;
    fire();
  }
}

class FakeClock {
  final delays = <Duration>[];
  final timers = <FakeTimer>[];
  Timer schedule(Duration delay, void Function() callback) {
    delays.add(delay);
    final timer = FakeTimer(callback);
    timers.add(timer);
    return timer;
  }

  void elapseLast() => timers.last.elapse();
}

class FakeTransport extends MeshCoreBleTransport {
  FakeTransport(String id) : super(selectedId: id);
  final changes = StreamController<bool>.broadcast(sync: true);
  final responses = StreamController<List<int>>.broadcast(sync: true);
  final writes = <List<int>>[];
  bool connected = false;
  int closes = 0;
  bool failOpen = false;
  bool reply = true;
  bool malformedInfo = false;
  Completer<void>? opening;
  Completer<void>? writePending;

  @override
  bool get ready => connected;
  @override
  Stream<bool> get readiness => changes.stream;
  @override
  Stream<List<int>> get frames => responses.stream;
  @override
  Future<void> open() async {
    if (failOpen) throw StateError('offline');
    await opening?.future;
    connected = true;
    changes.add(true);
  }

  @override
  Future<void> close() async {
    closes++;
    connected = false;
    changes.add(false);
  }

  @override
  Future<void> writeFrame(List<int> bytes) async {
    writes.add(List.of(bytes));
    await writePending?.future;
    if (reply) {
      if (bytes.first == 1) {
        final info = List<int>.filled(58, 0)..[0] = 5;
        info[4] = 1;
        responses.add(info);
      } else if (bytes.first == 22) {
        final info = List<int>.filled(80, 0)..[0] = 13;
        info[1] = 3;
        responses.add(info);
      }
    }
  }

  void drop() {
    connected = false;
    changes.add(false);
  }
}

Future<void> drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('unexpected drop retries selected paired device after bounded delays and re-handshakes', () async {
    final clock = FakeClock();
    final sessions = <FakeTransport>[];
    final controller = MeshCoreReconnectController(
      selectedId: '/org/bluez/hci0/dev_explicit',
      transportFactory: (id) {
        expect(id, '/org/bluez/hci0/dev_explicit');
        final session = FakeTransport(id);
        sessions.add(session);
        return session;
      },
      schedule: clock.schedule,
    );
    await controller.start();
    expect(controller.state, MeshCoreReconnectState.ready);
    expect(sessions.single.writes.map((frame) => frame.first), [1, 22]);
    sessions.single.drop();
    await drain();
    expect(controller.state, MeshCoreReconnectState.waiting);
    expect(clock.delays, [const Duration(seconds: 1)]);
    clock.elapseLast();
    await drain();
    expect(sessions.length, 2);
    expect(controller.state, MeshCoreReconnectState.ready);
    expect(sessions.last.writes.map((frame) => frame.first), [1, 22]);
    await controller.stop();
  });

  test(
    'repeated failures cap delay and successful handshake resets it',
    () async {
      final clock = FakeClock();
      var failuresLeft = 7;
      final sessions = <FakeTransport>[];
      final controller = MeshCoreReconnectController(
        selectedId: 'selected',
        schedule: clock.schedule,
        transportFactory: (id) {
          final session = FakeTransport(id)..failOpen = failuresLeft-- > 0;
          sessions.add(session);
          return session;
        },
      );
      await controller.start();
      for (var i = 0; i < 7; i++) {
        expect(controller.state, MeshCoreReconnectState.waiting);
        clock.elapseLast();
        await drain();
      }
      expect(clock.delays, [
        for (final seconds in [1, 2, 4, 8, 16, 32, 32])
          Duration(seconds: seconds),
      ]);
      expect(controller.state, MeshCoreReconnectState.ready);
      sessions.last.drop();
      await drain();
      expect(clock.delays.last, const Duration(seconds: 1));
      await controller.stop();
    },
  );

  test('explicit stop cancels retry and never reopens or sends', () async {
    final clock = FakeClock();
    var count = 0;
    final controller = MeshCoreReconnectController(
      selectedId: 'selected',
      schedule: clock.schedule,
      transportFactory: (id) {
        count++;
        return FakeTransport(id)..failOpen = true;
      },
    );
    await controller.start();
    expect(count, 1);
    await controller.stop();
    clock.elapseLast();
    await drain();
    expect(controller.state, MeshCoreReconnectState.stopped);
    expect(controller.readyTransport, isNull);
    expect(count, 1);
  });

  test(
    'disconnect mid-handshake retries without treating GATT as ready',
    () async {
      final clock = FakeClock();
      final sessions = <FakeTransport>[];
      final controller = MeshCoreReconnectController(
        selectedId: 'selected',
        schedule: clock.schedule,
        transportFactory: (id) {
          final session = FakeTransport(id)..reply = sessions.isNotEmpty;
          sessions.add(session);
          return session;
        },
      );
      final starting = controller.start();
      await drain();
      expect(controller.state, MeshCoreReconnectState.initializing);
      expect(controller.readyTransport, isNull);
      sessions.first.drop();
      await starting;
      expect(controller.state, MeshCoreReconnectState.waiting);
      clock.elapseLast();
      await drain();
      expect(controller.state, MeshCoreReconnectState.ready);
      await controller.stop();
    },
  );

  test(
    'stop while opening discards stale connection and never schedules',
    () async {
      final clock = FakeClock();
      final opening = Completer<void>();
      late FakeTransport session;
      final controller = MeshCoreReconnectController(
        selectedId: 'selected',
        schedule: clock.schedule,
        transportFactory: (id) =>
            session = FakeTransport(id)..opening = opening,
      );
      final starting = controller.start();
      await controller.stop();
      opening.complete();
      await starting;
      await drain();
      expect(controller.state, MeshCoreReconnectState.stopped);
      expect(clock.delays, isEmpty);
      expect(session.closes, 1);
    },
  );

  test('reconnect never replays an uncertain outbound write', () async {
    final clock = FakeClock();
    final sessions = <FakeTransport>[];
    final controller = MeshCoreReconnectController(
      selectedId: 'selected',
      schedule: clock.schedule,
      transportFactory: (id) {
        final session = FakeTransport(id);
        sessions.add(session);
        return session;
      },
    );
    await controller.start();
    // The caller owns this outbound frame; its outcome becomes uncertain.
    await controller.readyTransport!.writeFrame([2, 99]);
    sessions.first.drop();
    await drain();
    clock.elapseLast();
    await drain();
    expect(controller.state, MeshCoreReconnectState.ready);
    expect(sessions.first.writes.last, [2, 99]);
    expect(sessions.last.writes.map((frame) => frame.first), [1, 22]);
    await controller.stop();
  });
}
