import 'dart:async';

import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';

import 'linux_meshcore_ble.dart';
import 'meshcore_ble_transport.dart';

typedef FieldScan = Future<List<MeshCoreBleCandidate>> Function(
  Duration duration,
);
typedef FieldRetryScheduler = Timer Function(Duration, void Function());

/// Lightweight observation boundary usable from Flutter and a Dart CLI probe.
class FieldSessionNotifier {
  final _listeners = <void Function()>[];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void dispose() => _listeners.clear();
}

/// Volatile M1 field session. No plaintext, identity, PIN or OS path is written to disk.
class MeshCoreFieldSession extends FieldSessionNotifier {
  MeshCoreFieldSession({
    FieldScan? scan,
    MeshCoreBleTransport Function(String)? transportFactory,
    FieldRetryScheduler? scheduleRetry,
    this.responseTimeout = const Duration(seconds: 8),
    this.receiveMessages = true,
  }) : _scan = scan ?? MeshCoreBleScanner(scanBlueZ).scan,
       _scheduleRetry = scheduleRetry ?? Timer.new,
       _transportFactory =
           transportFactory ?? ((id) => MeshCoreBleTransport(selectedId: id));

  final FieldScan _scan;
  final Duration responseTimeout;
  final bool receiveMessages;
  final FieldRetryScheduler _scheduleRetry;
  Timer? _retry;
  int _retryFailures = 0;
  int reconnectAttempts = 0;
  final MeshCoreBleTransport Function(String) _transportFactory;
  final List<RadioMessage> messages = [];
  final Set<String> _seenFrames = {};
  List<MeshCoreBleCandidate> candidates = [];
  MeshCoreBleCandidate? selected;
  MeshCoreDeviceInfo? deviceInfo;
  MeshCoreSelfIdentity? identity;
  String status = 'No radio selected';
  String? error;
  int receiveCount = 0;
  int sendCount = 0;
  int rejectedFrames = 0;
  int waitingCount = 0;
  bool scanning = false;
  bool connecting = false;
  bool sending = false;
  bool _ready = false;
  bool _draining = false;
  bool _waiting = false;
  int _epoch = 0;
  MeshCoreBleTransport? _transport;
  StreamSubscription<bool>? _states;
  StreamSubscription<List<int>>? _frames;
  bool get connected => _ready && _transport?.ready == true;
  bool get paired => connected; // Transport refuses unpaired devices.

  Future<void> discover() async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();
    try {
      candidates = await _scan(const Duration(seconds: 5));
      status = candidates.isEmpty
          ? 'No MeshCore candidates found'
          : 'Select a MeshCore radio';
    } catch (e) {
      error =
          'Discovery failed (${e.runtimeType}). Check Bluetooth power and permission.';
      status = 'Scan failed';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> connect(
    MeshCoreBleCandidate candidate, {
    bool retry = false,
  }) async {
    if (connecting) return;
    if (candidate.id.isEmpty ||
        candidate.assessment == MeshCoreCandidateAssessment.unrelated) {
      throw ArgumentError('Select a MeshCore candidate');
    }
    await disconnect();
    if (retry) {
      reconnectAttempts++;
    } else {
      _retryFailures = 0;
    }
    final epoch = _epoch;
    selected = candidate;
    status = 'Connecting';
    error = null;
    connecting = true;
    notifyListeners();
    try {
      final transport = _transportFactory(candidate.id);
      if (transport.selectedId != candidate.id || transport.allowPairing) {
        throw StateError('Selected device mismatch or pairing not allowed');
      }
      _transport = transport;
      _states = transport.readiness.listen((ready) {
        if (!ready && epoch == _epoch && _ready) {
          _ready = false;
          identity = null;
          deviceInfo = null;
          status = 'Disconnected';
          notifyListeners();
          _scheduleReconnect(candidate, epoch);
        }
      });
      _frames = transport.frames.listen((frame) => _onFrame(frame, epoch));
      await transport.open();
      final self = await _query(
        transport,
        MeshCoreCompanionCodec.appStart('MeshHub'),
        5,
      );
      final info = await _query(
        transport,
        MeshCoreCompanionCodec.deviceQuery(),
        13,
      );
      if (epoch != _epoch || !transport.ready) {
        throw StateError('Handshake interrupted');
      }
      identity = MeshCoreCompanionCodec.parseSelfInfo(self);
      deviceInfo = MeshCoreCompanionCodec.parseDeviceInfo(info);
      _ready = true;
      _retryFailures = 0;
      status = 'Companion ready';
      notifyListeners();
      if (_waiting && receiveMessages) unawaited(_drain(epoch));
    } catch (e) {
      error =
          'Connection failed (${e.runtimeType}). Pair locally in the OS, then retry.';
      status = 'Connection failed';
      await disconnect();
      status = 'Connection failed';
      if (retry) {
        selected = candidate;
        _scheduleReconnect(candidate, _epoch);
      }
      notifyListeners();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<List<int>> _query(
    MeshCoreBleTransport transport,
    List<int> command,
    int response,
  ) => _exchange(transport, command, (f) => f.first == response);

  /// Subscribe before writing, and cancel both subscription and timer even
  /// when BlueZ rejects a write. A late timeout must never become an unhandled
  /// async error after the write already failed.
  Future<List<int>> _exchange(
    MeshCoreBleTransport transport,
    List<int> command,
    bool Function(List<int>) matches,
  ) async {
    final pending = Completer<List<int>?>();
    final subscription = transport.frames.listen(
      (frame) {
        if (!pending.isCompleted && frame.isNotEmpty && matches(frame)) {
          pending.complete(frame);
        }
      },
      onError: (Object _) {
        if (!pending.isCompleted) pending.complete(null);
      },
      onDone: () {
        if (!pending.isCompleted) pending.complete(null);
      },
    );
    final timeout = Timer(responseTimeout, () {
      if (!pending.isCompleted) pending.complete(null);
    });
    try {
      await transport.writeFrame(command);
      final reply = await pending.future;
      if (reply == null) throw TimeoutException('Radio response unavailable');
      return reply;
    } finally {
      timeout.cancel();
      await subscription.cancel();
    }
  }

  void _onFrame(List<int> frame, int epoch) {
    if (epoch != _epoch || frame.isEmpty) return;
    if (frame.first == 0x83) {
      waitingCount++;
      _waiting = true;
      notifyListeners();
      if (connected && receiveMessages) unawaited(_drain(epoch));
      return;
    }
    if (!receiveMessages || (frame.first != 16 && frame.first != 17)) return;
    try {
      final decoded = MeshCoreCompanionCodec.parseIncomingText(
        frame,
        maxChannels: deviceInfo?.maxChannels ?? 40,
      );
      final key = frame.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      if (!_seenFrames.add(key)) return;
      receiveCount++;
      messages.add(
        RadioMessage(
          id: 'live-$receiveCount',
          conversationId: decoded.origin == MeshCoreTextOrigin.channel
              ? 'meshcore-channel-${decoded.channelIndex}'
              : 'meshcore-direct',
          protocol: MeshProtocol.meshCore,
          sender: decoded.origin == MeshCoreTextOrigin.channel
              ? 'Channel ${decoded.channelIndex} · sender unverified'
              : 'Contact prefix ${decoded.senderKeyPrefix} · unverified',
          text: decoded.text,
          isSimulated: false,
        ),
      );
      notifyListeners();
    } catch (_) {
      rejectedFrames++;
      notifyListeners();
    }
  }

  Future<void> _drain(int epoch) async {
    if (_draining || !connected || epoch != _epoch) return;
    _draining = true;
    _waiting = false;
    try {
      // Bounded queue drain, one whole command per message; never log payloads.
      for (var i = 0; i < 32 && connected && epoch == _epoch; i++) {
        final reply = await _exchange(_transport!, [
          10,
        ], (f) => f.first == 10 || f.first == 16 || f.first == 17);
        if (reply.first == 10) break;
      }
    } catch (_) {
      status = 'Receive drain interrupted';
      notifyListeners();
    } finally {
      _draining = false;
      if (_waiting && connected && epoch == _epoch) unawaited(_drain(epoch));
    }
  }

  Future<MeshCoreLocalSendResult> sendChannel({
    required int channel,
    required String text,
    required bool verified,
  }) async {
    _requireVerified(verified);
    final frame = MeshCoreCompanionCodec.encodeChannelText(
      target: ConversationTarget(
        id: channel.toString(),
        protocol: MeshProtocol.meshCore,
      ),
      maxChannels: deviceInfo!.maxChannels,
      timestampSeconds: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      text: text,
    );
    return _sendFrame(frame, channel: true);
  }

  Future<MeshCoreLocalSendResult> sendDirect({
    required String keyPrefix,
    required String text,
    required bool verified,
  }) async {
    _requireVerified(verified);
    final frame = MeshCoreCompanionCodec.encodeDirectText(
      target: ConversationTarget(
        id: keyPrefix,
        protocol: MeshProtocol.meshCore,
      ),
      timestampSeconds: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      text: text,
    );
    return _sendFrame(frame, channel: false);
  }

  void _requireVerified(bool verified) {
    final preset = identity?.radioPreset;
    if (!verified ||
        !connected ||
        deviceInfo == null ||
        preset == null ||
        preset.frequencyKHz == 0 ||
        preset.bandwidthHz == 0) {
      throw StateError(
        'Verify RF region, preset, destination and a reachable peer first',
      );
    }
  }

  Future<MeshCoreLocalSendResult> _sendFrame(
    List<int> frame, {
    required bool channel,
  }) async {
    if (sending) throw StateError('Another send is already in progress');
    sending = true;
    final transport = _transport!;
    status = 'Send outcome uncertain until radio responds';
    notifyListeners();
    try {
      final response = await _exchange(
        transport,
        frame,
        (f) => f.first == 1 || f.first == (channel ? 0 : 6),
      );
      final result = MeshCoreCompanionCodec.parseSendResponse(
        response,
        channel: channel,
      );
      if (result == MeshCoreLocalSendResult.acceptedByRadio) sendCount++;
      status = result == MeshCoreLocalSendResult.acceptedByRadio
          ? 'Accepted by local radio — recipient delivery unverified'
          : 'Rejected by local radio';
      notifyListeners();
      return result;
    } catch (_) {
      status = 'Send outcome uncertain — do not retry blindly';
      notifyListeners();
      rethrow;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void _scheduleReconnect(MeshCoreBleCandidate candidate, int epoch) {
    if (_retry != null || epoch != _epoch) return;
    final delay = Duration(
      seconds: 1 << (_retryFailures < 5 ? _retryFailures : 5),
    );
    _retryFailures++;
    status = 'Disconnected · retry in ${delay.inSeconds}s';
    notifyListeners();
    _retry = _scheduleRetry(delay, () {
      _retry = null;
      if (epoch == _epoch && !connected && !connecting) {
        unawaited(connect(candidate, retry: true));
      }
    });
  }

  Future<void> disconnect() async {
    _retry?.cancel();
    _retry = null;
    _epoch++;
    _ready = false;
    _waiting = false;
    final transport = _transport;
    _transport = null;
    await _states?.cancel();
    _states = null;
    await _frames?.cancel();
    _frames = null;
    await transport?.close();
    identity = null;
    deviceInfo = null;
    selected = null;
    status = 'No radio selected';
    notifyListeners();
  }
}
