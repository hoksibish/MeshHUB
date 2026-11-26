import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'linux_meshcore_ble.dart'
    show BleObservationScan, MeshCoreBleObservation, scanBlueZ;
import 'meshtastic_ble.dart';
import 'meshtastic_connection_protocol.dart';

class MeshtasticSession extends ChangeNotifier {
  MeshtasticSession({
    BleObservationScan? scan,
    MeshtasticBleLink Function()? linkFactory,
    this.handshakeTimeout = const Duration(seconds: 45),
  }) : _scan = scan ?? scanBlueZ,
       _linkFactory = linkFactory ?? BlueZMeshtasticLink.new;

  final BleObservationScan _scan;
  final MeshtasticBleLink Function() _linkFactory;
  final Duration handshakeTimeout;
  List<MeshCoreBleObservation> candidates = [];
  MeshCoreBleObservation? selected;
  bool scanning = false, connecting = false, connected = false;
  bool _disconnecting = false;
  bool get active => connecting || connected || _disconnecting;
  String status = 'Discover a Meshtastic radio to connect.';
  String? error;
  int? nodeNumber, hardwareModel;
  String? firmwareVersion;
  int receivedFrames = 0;
  bool get awaitingPin => _pin != null;
  Completer<String?>? _pin;
  MeshtasticBleLink? _link;
  StreamSubscription<void>? _dataSubscription, _disconnectSubscription;
  Timer? _poll;
  int _generation = 0;
  bool _disposed = false, _draining = false, _drainAgain = false;
  Completer<void>? _handshake;
  int? _nonce;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> discover() async {
    if (scanning || active || _disposed) return;
    scanning = true;
    error = null;
    status = 'Scanning for Meshtastic services...';
    _changed();
    final generation = _generation;
    try {
      final observations = await _scan(const Duration(seconds: 6));
      if (_disposed || generation != _generation) return;
      candidates = observations
          .where(
            (d) => d.uuids.any((u) => u.toLowerCase() == meshtasticServiceUuid),
          )
          .toList();
      status = candidates.isEmpty
          ? 'No Meshtastic services found. Disconnect the phone app and scan again.'
          : 'Select your radio. Cached entries are verified on connection.';
    } catch (_) {
      error = 'Bluetooth scan failed. Check that Bluetooth is enabled.';
    } finally {
      scanning = false;
      _changed();
    }
  }

  Future<String?> _requestPin() async {
    if (!connecting || _disposed) return null;
    cancelPin();
    final request = Completer<String?>();
    _pin = request;
    status = 'Enter the six-digit Bluetooth PIN shown on the node.';
    _changed();
    return request.future;
  }

  void submitPin(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return;
    final request = _pin;
    _pin = null;
    request?.complete(pin);
    status = 'Authenticating with the radio...';
    _changed();
  }

  void cancelPin() {
    final request = _pin;
    if (request == null) return;
    _pin = null;
    if (!request.isCompleted) request.complete(null);
    _changed();
  }

  Future<void> connect(MeshCoreBleObservation candidate) async {
    if (active || scanning || _disposed) return;
    if (!candidates.any((c) => c.id == candidate.id)) {
      throw ArgumentError('Select a discovered Meshtastic radio');
    }
    final generation = ++_generation;
    connecting = true;
    selected = candidate;
    error = null;
    nodeNumber = hardwareModel = null;
    firmwareVersion = null;
    receivedFrames = 0;
    status = 'Connecting / pairing with Meshtastic...';
    _changed();
    final link = _linkFactory();
    _link = link;
    try {
      await link.open(
        candidate.id,
        () => generation == _generation ? _requestPin() : Future.value(null),
        () {
          if (generation == _generation) cancelPin();
        },
      );
      if (generation != _generation || _disposed) return;
      status =
          'Bluetooth connected. Reading Meshtastic device configuration...';
      _changed();
      _nonce = Random.secure().nextInt(0xfffffffe) + 1;
      final handshake = Completer<void>();
      _handshake = handshake;
      // Install an error handler immediately, including for errors while the
      // initial write is still in flight.
      final completed = handshake.future.timeout(handshakeTimeout);
      unawaited(completed.catchError((Object _) {}));
      _dataSubscription = link.dataAvailable.listen(
        (_) => unawaited(_drain(generation, link)),
        onError: (Object _) => _fail(generation),
      );
      _disconnectSubscription = link.disconnected.listen(
        (_) => _fail(generation),
        onError: (Object _) => _fail(generation),
      );
      await link.writeConfigRequest(
        MeshtasticConnectionReport.requestConfig(_nonce!),
      );
      if (generation != _generation) return;
      // Notifications can be coalesced. The fallback poll also recovers an
      // initial wake that arrived before StartNotify/config-request completed.
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_drain(generation, link));
      });
      unawaited(_drain(generation, link));
      await completed;
      if (generation != _generation || _disposed) return;
      connecting = false;
      connected = true;
      status = 'Connected · Meshtastic configuration handshake verified';
      _changed();
    } catch (_) {
      if (generation != _generation || _disposed) return;
      await disconnect();
      error =
          'Meshtastic connection failed. Check the PIN on the node and disconnect '
          'other clients. If the node was reflashed, remove its old pairing in '
          'Bluetooth settings, then discover and pair again.';
      _changed();
    }
  }

  Future<void> _drain(int generation, MeshtasticBleLink link) async {
    if (generation != _generation || _disposed) return;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        // Bound work per wake; timer resumes draining large queues later.
        for (var count = 0; count < 128; count++) {
          final bytes = await link.readFromRadio();
          if (generation != _generation || _disposed) return;
          if (bytes.isEmpty) break;
          final report = MeshtasticConnectionReport.decode(bytes);
          receivedFrames++;
          if (report.rebooted) throw StateError('Meshtastic node rebooted');
          nodeNumber = report.nodeNumber ?? nodeNumber;
          hardwareModel = report.hardwareModel ?? hardwareModel;
          firmwareVersion = report.firmwareVersion ?? firmwareVersion;
          if (report.configCompleteId == _nonce && nodeNumber != null) {
            final handshake = _handshake;
            if (handshake != null && !handshake.isCompleted) {
              handshake.complete();
            }
          }
        }
      } while (_drainAgain && generation == _generation);
      _changed();
    } catch (_) {
      _fail(generation);
    } finally {
      _draining = false;
    }
  }

  void _fail(int generation) {
    if (generation != _generation || _disposed) return;
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(StateError('Meshtastic link lost'));
    }
    unawaited(
      disconnect().then((_) {
        if (_disposed || active) return;
        error = 'Meshtastic link lost or invalid response. Reconnect manually; no messages were sent.';
        _changed();
      }),
    );
  }

  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    _generation++;
    cancelPin();
    _poll?.cancel();
    _poll = null;
    final handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(StateError('Connection cancelled'));
    }
    connected = connecting = false;
    _nonce = null;
    nodeNumber = hardwareModel = null;
    firmwareVersion = null;
    status = 'Disconnected';
    final link = _link;
    _link = null;
    final data = _dataSubscription, lost = _disconnectSubscription;
    _dataSubscription = _disconnectSubscription = null;
    _changed();
    try {
      await data?.cancel();
      await lost?.cancel();
    } finally {
      try {
        await link?.close();
      } finally {
        _disconnecting = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
