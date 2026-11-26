import 'dart:async';

import 'package:bluez/bluez.dart';

import 'ble_pairing.dart';

const meshtasticServiceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const meshtasticToRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const meshtasticFromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
const meshtasticFromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

typedef MeshtasticPinRequest = BlePinRequest;

abstract interface class MeshtasticBleLink {
  Stream<void> get dataAvailable;
  Stream<void> get disconnected;
  Future<void> open(
    String deviceId,
    MeshtasticPinRequest requestPin,
    void Function() cancelPrompt,
  );
  Future<void> writeConfigRequest(List<int> bytes);
  Future<List<int>> readFromRadio();
  Future<void> close();
}

/// Meshtastic GATT has a read FIFO and a separate wake notification, unlike
/// MeshCore's UART service. No raw MeshCore frame ever enters this transport.
class BlueZMeshtasticLink implements MeshtasticBleLink {
  BlueZClient? _client;
  BlueZDevice? _device;
  BlePinAgent? _agent;
  BlueZGattCharacteristic? _toRadio, _fromRadio, _fromNum;
  StreamSubscription<List<String>>? _stateSubscription, _valueSubscription;
  final _data = StreamController<void>.broadcast();
  final _lost = StreamController<void>.broadcast();
  bool _closed = false, _notify = false, _ownsConnection = false;
  bool _pairing = false;

  @override
  Stream<void> get dataAvailable => _data.stream;
  @override
  Stream<void> get disconnected => _lost.stream;

  void _checkOpen() {
    if (_closed) throw StateError('Meshtastic connection cancelled');
  }

  @override
  Future<void> open(
    String deviceId,
    MeshtasticPinRequest requestPin,
    void Function() cancelPrompt,
  ) async {
    if (_client != null || _closed) throw StateError('Link already used');
    final client = BlueZClient();
    _client = client;
    await client.connect().timeout(const Duration(seconds: 10));
    _checkOpen();
    final devices = client.devices.where((d) => d.path.value == deviceId);
    if (devices.length != 1) throw StateError('Selected radio is unavailable');
    final device = devices.single;
    _device = device;
    // Refuse unrelated devices before requesting authentication. Discovery UUIDs
    // may be cached; exact service/characteristics are verified again below.
    if (!device.uuids.any((u) => u.toString() == meshtasticServiceUuid)) {
      throw StateError('Selected device has no Meshtastic service');
    }
    if (!device.paired) {
      final agent = BlePinAgent(deviceId, requestPin, cancelPrompt);
      _agent = agent;
      await client.registerAgent(
        agent,
        capability: BlueZAgentCapability.keyboardOnly,
      );
      _checkOpen();
      _ownsConnection = !device.connected;
      _pairing = true;
      try {
        await device.pair().timeout(const Duration(seconds: 90));
      } finally {
        _pairing = false;
        cancelPrompt();
      }
      _checkOpen();
      if (!device.paired) throw StateError('Pairing was not confirmed');
    }
    if (!device.connected) {
      _ownsConnection = true;
      await device.connect().timeout(const Duration(seconds: 20));
    }
    _checkOpen();
    // Polling properties avoids missing ServicesResolved between a snapshot
    // and subscribing. BlueZ updates these from its property signal stream.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (device.connected && !device.servicesResolved) {
      _checkOpen();
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Meshtastic service discovery timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _checkOpen();
    if (!device.connected) throw StateError('Radio disconnected during setup');
    final services = device.gattServices.where(
      (s) => s.uuid.toString() == meshtasticServiceUuid,
    );
    if (services.length != 1) {
      throw StateError('Meshtastic service not resolved');
    }
    BlueZGattCharacteristic characteristic(
      String uuid,
      BlueZGattCharacteristicFlag flag,
    ) {
      final matches = services.single.characteristics.where(
        (c) => c.uuid.toString() == uuid,
      );
      if (matches.length != 1 || !matches.single.flags.contains(flag)) {
        throw StateError('Meshtastic GATT characteristics do not match');
      }
      return matches.single;
    }

    _toRadio = characteristic(
      meshtasticToRadioUuid,
      BlueZGattCharacteristicFlag.write,
    );
    _fromRadio = characteristic(
      meshtasticFromRadioUuid,
      BlueZGattCharacteristicFlag.read,
    );
    final fromNum = characteristic(
      meshtasticFromNumUuid,
      BlueZGattCharacteristicFlag.notify,
    );
    _fromNum = fromNum;
    _stateSubscription = device.propertiesChanged.listen((_) {
      if (!device.connected && !_closed) _lost.add(null);
    });
    _valueSubscription = fromNum.propertiesChanged.listen((names) {
      if (!_closed && names.contains('Value')) _data.add(null);
    });
    await fromNum.startNotify().timeout(const Duration(seconds: 10));
    _notify = true;
    _checkOpen();
    if (!device.connected) throw StateError('Radio disconnected during setup');
  }

  @override
  Future<void> writeConfigRequest(List<int> bytes) async {
    _checkOpen();
    // This boundary only permits ToRadio.want_config_id, never mesh packets.
    if (bytes.length < 2 || bytes.length > 6 || bytes.first != 0x18) {
      throw ArgumentError('Only a local configuration request is allowed');
    }
    for (var index = 1; index < bytes.length; index++) {
      final byte = bytes[index];
      final last = index == bytes.length - 1;
      if (byte < 0 ||
          byte > 255 ||
          (byte < 128) != last ||
          (index == 5 && byte > 15)) {
        throw ArgumentError('Malformed configuration nonce');
      }
    }
    await _toRadio!
        .writeValue(bytes, type: BlueZGattCharacteristicWriteType.request)
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<List<int>> readFromRadio() async {
    _checkOpen();
    return _fromRadio!.readValue().timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _agent?.release();
    // Always close the bus, even if an unplugged radio rejects cleanup calls.
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    await attempt(() async => _valueSubscription?.cancel());
    await attempt(() async => _stateSubscription?.cancel());
    if (_pairing && _device != null) await attempt(_device!.cancelPairing);
    if (_notify && _fromNum != null) await attempt(_fromNum!.stopNotify);
    if (_ownsConnection && _device?.connected == true) {
      await attempt(_device!.disconnect);
    }
    if (_agent != null && _client != null) {
      await attempt(_client!.unregisterAgent);
    }
    if (_client != null) await attempt(_client!.close);
    await _data.close();
    await _lost.close();
  }
}
