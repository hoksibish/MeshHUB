import 'dart:async';

import 'package:meshhub_domain/meshcore_protocol.dart';

import 'meshcore_ble_transport.dart';

/// Scheduling is injectable so retry behavior can be exercised without time.
typedef MeshCoreRetryScheduler = Timer Function(
  Duration delay,
  void Function() callback,
);

enum MeshCoreReconnectState {
  stopped,
  connecting,
  initializing,
  ready,
  waiting,
}

/// One explicitly selected, already paired BlueZ device. No discovery,
/// pairing, outbound queue, or automatic replay is performed here.
class MeshCoreReconnectController {
  MeshCoreReconnectController({
    required this.selectedId,
    MeshCoreBleTransport Function(String selectedId)? transportFactory,
    MeshCoreRetryScheduler? schedule,
    this.handshakeTimeout = const Duration(seconds: 10),
  }) : _transportFactory =
           transportFactory ?? ((id) => MeshCoreBleTransport(selectedId: id)),
       _schedule = schedule ?? Timer.new {
    if (selectedId.isEmpty) throw ArgumentError('Selected device required');
    if (handshakeTimeout <= Duration.zero) {
      throw ArgumentError('Handshake timeout must be positive');
    }
  }

  final String selectedId;
  final Duration handshakeTimeout;
  final MeshCoreBleTransport Function(String) _transportFactory;
  final MeshCoreRetryScheduler _schedule;
  MeshCoreReconnectState state = MeshCoreReconnectState.stopped;
  MeshCoreBleTransport? _transport;
  StreamSubscription<bool>? _readiness;
  StreamSubscription<List<int>>? _frames;
  Completer<List<int>>? _pending;
  int? _expected;
  Timer? _retry;
  int _failures = 0;
  int _generation = 0;

  /// Null until GATT notifications and both read-only responses are verified.
  /// Callers own any outbound operation and must resolve uncertain sends;
  /// this controller has no send or replay API.
  MeshCoreBleTransport? get readyTransport =>
      state == MeshCoreReconnectState.ready ? _transport : null;

  Future<void> start() async {
    if (state != MeshCoreReconnectState.stopped) {
      throw StateError('Already started');
    }
    state = MeshCoreReconnectState.connecting;
    _failures = 0;
    await _attempt(_generation);
  }

  Future<void> stop() async {
    if (state == MeshCoreReconnectState.stopped) return;
    state = MeshCoreReconnectState.stopped;
    _generation++;
    _retry?.cancel();
    _retry = null;
    _cancelPending();
    await _release();
  }

  void _cancelPending() {
    final pending = _pending;
    _pending = null;
    _expected = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Handshake interrupted'));
    }
  }

  Future<void> _release() async {
    final transport = _transport;
    _transport = null;
    await _readiness?.cancel();
    _readiness = null;
    await _frames?.cancel();
    _frames = null;
    await transport?.close();
  }

  Future<void> _attempt(int generation) async {
    if (generation != _generation || state == MeshCoreReconnectState.stopped) {
      return;
    }
    state = MeshCoreReconnectState.connecting;
    try {
      final transport = _transportFactory(selectedId);
      if (transport.selectedId != selectedId || transport.allowPairing) {
        throw StateError('Expected exact selected, already paired transport');
      }
      _transport = transport;
      _readiness = transport.readiness.listen(
        (ready) {
          if (!ready && generation == _generation) {
            _cancelPending();
            if (state == MeshCoreReconnectState.ready) {
              _retryAfterFailure(generation);
            }
          }
        },
        onError: (Object _) {
          if (generation == _generation) {
            _cancelPending();
            if (state == MeshCoreReconnectState.ready) {
              _retryAfterFailure(generation);
            }
          }
        },
      );
      await transport.open();
      if (generation != _generation) return;
      if (!transport.ready) throw StateError('GATT notifications not ready');
      state = MeshCoreReconnectState.initializing;
      _frames = transport.frames.listen((frame) {
        if (frame.isNotEmpty &&
            frame.first == _expected &&
            _pending != null &&
            !_pending!.isCompleted) {
          _pending!.complete(frame);
        }
      }, onError: (Object _) => _cancelPending());
      final self = await _request(
        transport,
        MeshCoreCompanionCodec.appStart('MeshHub'),
        5,
      );
      MeshCoreCompanionCodec.parseSelfInfo(self);
      final info = await _request(
        transport,
        MeshCoreCompanionCodec.deviceQuery(),
        13,
      );
      MeshCoreCompanionCodec.parseDeviceInfo(info);
      if (generation != _generation || !transport.ready) {
        throw StateError('Handshake interrupted');
      }
      _failures = 0;
      state = MeshCoreReconnectState.ready;
    } catch (_) {
      if (generation == _generation &&
          state != MeshCoreReconnectState.stopped) {
        _retryAfterFailure(generation);
      }
    }
  }

  Future<List<int>> _request(
    MeshCoreBleTransport transport,
    List<int> command,
    int responseType,
  ) async {
    _expected = responseType;
    final pending = Completer<List<int>>();
    _pending = pending;
    try {
      await transport.writeFrame(command);
      return await pending.future.timeout(handshakeTimeout);
    } finally {
      if (identical(_pending, pending)) {
        _pending = null;
        _expected = null;
      }
    }
  }

  void _retryAfterFailure(int generation) {
    if (generation != _generation ||
        state == MeshCoreReconnectState.waiting ||
        state == MeshCoreReconnectState.stopped) {
      return;
    }
    state = MeshCoreReconnectState.waiting;
    _cancelPending();
    // 1, 2, 4, ... 32 seconds; never grow beyond the cap.
    final delay = Duration(seconds: 1 << (_failures < 5 ? _failures : 5));
    _failures++;
    unawaited(_release().catchError((Object _) {}));
    _retry = _schedule(delay, () {
      _retry = null;
      if (generation == _generation &&
          state == MeshCoreReconnectState.waiting) {
        unawaited(_attempt(generation));
      }
    });
  }
}
