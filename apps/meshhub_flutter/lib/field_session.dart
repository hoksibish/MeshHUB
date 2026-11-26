import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
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
    this.transportFactory,
    FieldRetryScheduler? scheduleRetry,
    this.responseTimeout = const Duration(seconds: 8),
    this.receiveMessages = true,
    this.allowPairing = false,
    this.messageHistory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _scan = scan ?? MeshCoreBleScanner(scanBlueZ).scan,
       _scheduleRetry = scheduleRetry ?? Timer.new;

  static const _duplicateWindow = Duration(seconds: 3);
  static const _maximumRecentFrames = 256;
  final DateTime Function() _clock;
  final FieldScan _scan;
  final Duration responseTimeout;
  final bool receiveMessages;

  /// Only an interactive UI should opt in; read-only CLI probes stay paired-only.
  final bool allowPairing;
  final MessageHistoryRepository? messageHistory;
  final String _messageIdPrefix = _newMessageIdPrefix();
  static String _newMessageIdPrefix() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(16, (_) => random.nextInt(256)));
  }

  final Map<int, String> _channelFingerprints = {};
  final List<_HistoryObservation> _unscopedHistory = [];
  final Map<String, MessageHistoryEntry> _failedHistory = {};
  Future<void> _historyWrites = Future.value();
  String? historyError;
  int historyPending = 0;
  int get unsavedHistoryCount =>
      _failedHistory.length + _unscopedHistory.length;

  Future<void> flushHistory() => _historyWrites;

  Future<void> retryHistory() {
    final repository = messageHistory;
    if (repository == null || _failedHistory.isEmpty) return Future.value();
    final previous = _historyWrites;
    _historyWrites = () async {
      await previous;
      for (final entry in List<MessageHistoryEntry>.of(_failedHistory.values)) {
        await _appendHistoryEntry(repository, entry);
      }
      notifyListeners();
    }();
    return _historyWrites;
  }

  Future<void> _appendHistoryEntry(
    MessageHistoryRepository repository,
    MessageHistoryEntry entry,
  ) async {
    try {
      await repository.append(entry);
      _failedHistory.remove(entry.recordId);
    } catch (_) {
      _failedHistory[entry.recordId] = entry;
    }
    historyError = _failedHistory.isEmpty ? null : 'Some messages could not be saved to encrypted history. They remain in memory; unlock/retry in Settings.';
  }

  String? get _historyRadioIdentity => identity == null
      ? null
      : 'meshcore:${identity!.publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  void _captureHistory(
    RadioMessage message,
    List<int> frame, {
    int? channel,
    String? directPeer,
  }) {
    if (messageHistory == null || message.isSimulated) return;
    final radio = _historyRadioIdentity;
    if (radio == null) {
      historyError =
          'A message could not be saved before radio identity was verified.';
      return;
    }
    final observation = _HistoryObservation(
      message,
      List.of(frame),
      radio,
      channel,
      directPeer,
      _clock().toUtc(),
    );
    if (channel != null && !_channelFingerprints.containsKey(channel)) {
      if (_unscopedHistory.length < 256) {
        _unscopedHistory.add(observation);
      } else {
        historyError = 'Some messages remain in memory because channel identity is unavailable.';
      }
      return;
    }
    _saveObservation(observation);
  }

  void _saveObservation(_HistoryObservation observation) {
    final channel = observation.channel;
    final scope = channel == null
        ? 'direct:${observation.directPeer ?? 'unverified'}'
        : 'channel:$channel:${_channelFingerprints[channel]!}';
    final matching = _channels.where((c) => c.index == channel);
    final name = channel == null
        ? 'Direct message · unverified contact'
        : matching.isEmpty
        ? 'Channel $channel'
        : matching.first.name;
    final repository = messageHistory!;
    final previous = _historyWrites;
    historyPending++;
    _historyWrites = () async {
      await previous;
      try {
        final random = Random.secure();
        final recordId = observation.message.isOutgoing
            ? base64UrlEncode(List.generate(24, (_) => random.nextInt(256)))
            : (await Sha256().hash([
                ...utf8.encode('${observation.radio}|$scope|'),
                ...observation.frame,
              ])).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await _appendHistoryEntry(
          repository,
          MessageHistoryEntry(
            recordId: recordId,
            message: observation.message,
            radioIdentity: observation.radio,
            conversationIdentity: scope,
            conversationName: name,
            recordedAt: observation.recordedAt,
          ),
        );
      } catch (_) {
        historyError = 'A message could not be saved to encrypted history. It remains in memory.';
      } finally {
        historyPending--;
        notifyListeners();
      }
    }();
  }

  final FieldRetryScheduler _scheduleRetry;
  Timer? _retry;
  int _retryFailures = 0;
  int reconnectAttempts = 0;
  final MeshCoreBleTransport Function(String)? transportFactory;
  Completer<String?>? _pairingPin;
  bool get awaitingPairingPin => _pairingPin != null;

  Future<String?> requestPairingPin() async {
    if (!connecting) return null;
    cancelPairingPin();
    final request = Completer<String?>();
    _pairingPin = request;
    status = 'Enter your MeshCore Bluetooth PIN';
    notifyListeners();
    return request.future;
  }

  void submitPairingPin(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin) || _pairingPin == null) return;
    final request = _pairingPin!;
    _pairingPin = null;
    request.complete(pin);
    status = 'Authenticating MeshCore radio';
    notifyListeners();
  }

  void cancelPairingPin() {
    final request = _pairingPin;
    _pairingPin = null;
    if (request == null) return;
    if (!request.isCompleted) request.complete(null);
    notifyListeners();
  }

  final List<RadioMessage> messages = [];
  // Only suppress repeated notifications briefly; bounded for long sessions.
  final Map<String, DateTime> _recentFrames = {};
  List<MeshCoreBleCandidate> candidates = [];
  MeshCoreBleCandidate? selected;
  MeshCoreDeviceInfo? deviceInfo;
  MeshCoreSelfIdentity? identity;
  List<MeshCoreChannel> _channels = const [];
  List<MeshCoreChannel> get channels => _channels;
  bool channelsLoading = false;
  String? channelsError;
  String status = 'No radio selected';
  String? error;
  int receiveCount = 0;
  int sendCount = 0;
  int sendRequestCount = 0;
  int rejectedSendCount = 0;
  int uncertainSendCount = 0;
  String lastSendOutcome = 'No local sends attempted';
  int rejectedFrames = 0;
  int waitingCount = 0;
  bool scanning = false;
  bool connecting = false;
  bool _disconnecting = false;
  bool get busy => connecting || _disconnecting;
  bool sending = false;
  bool _ready = false;
  bool _draining = false;
  bool _waiting = false;
  Future<void> _exchangeTail = Future<void>.value();
  Completer<List<int>?>? _pendingExchange;
  int _epoch = 0;
  MeshCoreBleTransport? _transport;
  StreamSubscription<bool>? _states;
  StreamSubscription<List<int>>? _frames;
  bool get connected => _ready && _transport?.ready == true;
  bool get paired => connected; // Transport refuses unpaired devices.

  Future<void> discover() async {
    if (scanning || busy) return;
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
    if (busy) return;
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
      final transport =
          transportFactory?.call(candidate.id) ??
          MeshCoreBleTransport(
            selectedId: candidate.id,
            allowPairing: allowPairing && !retry,
            requestPin: () =>
                epoch == _epoch ? requestPairingPin() : Future.value(null),
            cancelPin: () {
              if (epoch == _epoch) cancelPairingPin();
            },
          );
      if (transport.selectedId != candidate.id ||
          (transport.allowPairing && (!allowPairing || retry))) {
        throw StateError('Selected device mismatch or pairing not allowed');
      }
      _transport = transport;
      _states = transport.readiness.listen((ready) {
        if (!ready && epoch == _epoch && _ready) {
          _epoch++;
          _abortExchange();
          _ready = false;
          identity = null;
          deviceInfo = null;
          _clearChannels();
          status = 'Disconnected';
          notifyListeners();
          _scheduleReconnect(candidate, _epoch);
        }
      });
      _frames = transport.frames.listen((frame) => _onFrame(frame, epoch));
      await transport.open();
      if (epoch != _epoch) return;
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
      await refreshChannels();
      if (_waiting && receiveMessages) unawaited(_drain(epoch));
    } catch (e) {
      if (epoch != _epoch) return;
      error =
          'Connection failed (${e.runtimeType}). Check the Bluetooth PIN and '
          'disconnect other clients, then try Pair & connect again. If the '
          'radio was reflashed, its old pairing may need removing in Bluetooth settings.';
      status = 'Connection failed';
      await disconnect();
      status = 'Connection failed';
      if (retry) {
        selected = candidate;
        _scheduleReconnect(candidate, _epoch);
      }
      notifyListeners();
    } finally {
      if (epoch == _epoch) connecting = false;
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
    final epoch = _epoch;
    final previous = _exchangeTail;
    final release = Completer<void>();
    _exchangeTail = release.future;
    try {
      await previous;
      if (epoch != _epoch || _transport != transport || !transport.ready) {
        throw StateError('Session changed before command');
      }
      return await _performExchange(transport, command, matches, epoch);
    } finally {
      release.complete();
    }
  }

  Future<List<int>> _performExchange(
    MeshCoreBleTransport transport,
    List<int> command,
    bool Function(List<int>) matches,
    int epoch,
  ) async {
    final pending = Completer<List<int>?>();
    _pendingExchange = pending;
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
      if (epoch != _epoch || _transport != transport || !transport.ready) {
        throw StateError('Session changed during command');
      }
      final reply = await pending.future;
      if (epoch != _epoch || _transport != transport || !transport.ready) {
        throw StateError('Session changed during response');
      }
      if (reply == null) throw TimeoutException('Radio response unavailable');
      return reply;
    } finally {
      timeout.cancel();
      if (identical(_pendingExchange, pending)) _pendingExchange = null;
      await subscription.cancel();
    }
  }

  void _abortExchange() {
    final pending = _pendingExchange;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  void _clearChannels() {
    _channelFingerprints.clear();
    _channels = const [];
    channelsLoading = false;
    channelsError = null;
  }

  /// Query every reported slot; publish only a complete, named snapshot.
  Future<void> refreshChannels() async {
    if (!connected || deviceInfo == null) {
      channelsError = 'Connect to a MeshCore radio first';
      notifyListeners();
      return;
    }
    if (channelsLoading) return;
    final epoch = _epoch;
    final transport = _transport!;
    final count = deviceInfo!.maxChannels;
    channelsLoading = true;
    channelsError = null;
    _channels = const [];
    _channelFingerprints.clear();
    notifyListeners();
    try {
      final found = <MeshCoreChannel>[];
      final fingerprints = <int, String>{};
      for (var index = 0; index < count; index++) {
        if (epoch != _epoch || !connected) return;
        final response = await _exchange(
          transport,
          MeshCoreCompanionCodec.getChannel(index),
          (f) => f.first == 0x12,
        );
        final channel = MeshCoreCompanionCodec.parseChannelInfo(
          response,
          requestedIndex: index,
        );
        if (messageHistory != null) {
          // CHANNEL_INFO bytes 34..49 are used only to derive a non-secret
          // identity fingerprint. Raw channel keys are never persisted.
          final digest = await Sha256().hash(response.sublist(34, 50));
          fingerprints[index] = digest.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
        }
        if (channel.name.isNotEmpty) found.add(channel);
      }
      if (epoch == _epoch && connected) {
        _channels = List.unmodifiable(found);
        _channelFingerprints.addAll(fingerprints);
        final pending = List<_HistoryObservation>.of(_unscopedHistory);
        _unscopedHistory.clear();
        for (final observation in pending) {
          if (observation.radio == _historyRadioIdentity &&
              _channelFingerprints.containsKey(observation.channel)) {
            _saveObservation(observation);
          } else {
            historyError = 'Some messages remain in memory because channel identity could not be verified.';
          }
        }
      }
    } catch (_) {
      if (epoch == _epoch) {
        channelsError = 'Channel discovery failed; retry refresh';
      }
    } finally {
      if (epoch == _epoch) {
        channelsLoading = false;
        notifyListeners();
      }
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
      final now = _clock();
      _recentFrames.removeWhere(
        (_, firstSeen) => now.difference(firstSeen) >= _duplicateWindow,
      );
      if (_recentFrames.containsKey(key)) return;
      if (_recentFrames.length >= _maximumRecentFrames) {
        _recentFrames.remove(_recentFrames.keys.first);
      }
      _recentFrames[key] = now;
      receiveCount++;
      final message = RadioMessage(
        id: 'live-$_messageIdPrefix-$receiveCount',
        conversationId: decoded.origin == MeshCoreTextOrigin.channel
            ? 'meshcore-channel-${decoded.channelIndex}'
            : 'meshcore-direct',
        protocol: MeshProtocol.meshCore,
        sender: decoded.origin == MeshCoreTextOrigin.channel
            ? 'Channel ${decoded.channelIndex} · sender unverified'
            : 'Contact prefix ${decoded.senderKeyPrefix} · unverified',
        text: decoded.text,
        isSimulated: false,
      );
      messages.add(message);
      _captureHistory(
        message,
        frame,
        channel: decoded.channelIndex,
        directPeer: decoded.senderKeyPrefix,
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
      if (epoch == _epoch) {
        status = 'Receive drain interrupted';
        notifyListeners();
      }
    } finally {
      if (epoch == _epoch) _draining = false;
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
    final result = await _sendFrame(frame, channel: true);
    if (result == MeshCoreLocalSendResult.acceptedByRadio) {
      final message = RadioMessage(
        id: 'outgoing-$_messageIdPrefix-$sendCount',
        conversationId: 'meshcore-channel-$channel',
        protocol: MeshProtocol.meshCore,
        sender: 'You · local radio',
        text: text,
        isSimulated: false,
        isOutgoing: true,
        deliveryState: MessageDeliveryState.acceptedByLocalRadio,
      );
      messages.add(message);
      _captureHistory(message, frame, channel: channel);
      notifyListeners();
    }
    return result;
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
    final result = await _sendFrame(frame, channel: false);
    if (result == MeshCoreLocalSendResult.acceptedByRadio) {
      final message = RadioMessage(
        id: 'outgoing-direct-$_messageIdPrefix-$sendCount',
        conversationId: 'meshcore-direct',
        protocol: MeshProtocol.meshCore,
        sender: 'You · local radio',
        text: text,
        isSimulated: false,
        isOutgoing: true,
        deliveryState: MessageDeliveryState.acceptedByLocalRadio,
      );
      messages.add(message);
      _captureHistory(message, frame, directPeer: keyPrefix);
      notifyListeners();
    }
    return result;
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
    sendRequestCount++;
    lastSendOutcome = 'Waiting for local radio response';
    final epoch = _epoch;
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
      if (epoch != _epoch) throw StateError('Session changed during send');
      if (result == MeshCoreLocalSendResult.acceptedByRadio) {
        sendCount++;
        lastSendOutcome = 'Accepted locally · peer delivery unverified';
      } else {
        rejectedSendCount++;
        lastSendOutcome = 'Rejected by local radio';
      }
      status = result == MeshCoreLocalSendResult.acceptedByRadio
          ? 'Accepted by local radio — recipient delivery unverified'
          : 'Rejected by local radio';
      notifyListeners();
      return result;
    } catch (_) {
      uncertainSendCount++;
      lastSendOutcome = 'Uncertain · do not retransmit without peer check';
      if (epoch == _epoch) {
        status = 'Send outcome uncertain — do not retry blindly';
        notifyListeners();
      }
      rethrow;
    } finally {
      if (epoch == _epoch) {
        sending = false;
        notifyListeners();
      }
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
    if (_disconnecting) return;
    _disconnecting = true;
    _retry?.cancel();
    _retry = null;
    _epoch++;
    if (_unscopedHistory.isNotEmpty) {
      historyError = 'Some messages remain in memory because channel identity was not verified before disconnection.';
      _unscopedHistory.clear();
    }
    connecting = false;
    cancelPairingPin();
    _abortExchange();
    _ready = false;
    _recentFrames.clear();
    _waiting = false;
    _draining = false;
    sending = false;
    _clearChannels();
    final transport = _transport;
    _transport = null;
    try {
      await _states?.cancel();
      _states = null;
      await _frames?.cancel();
      _frames = null;
      await transport?.close();
    } finally {
      identity = null;
      deviceInfo = null;
      selected = null;
      status = 'No radio selected';
      _disconnecting = false;
      notifyListeners();
    }
  }
}

class _HistoryObservation {
  const _HistoryObservation(
    this.message,
    this.frame,
    this.radio,
    this.channel,
    this.directPeer,
    this.recordedAt,
  );
  final RadioMessage message;
  final List<int> frame;
  final String radio;
  final int? channel;
  final String? directPeer;
  final DateTime recordedAt;
}
