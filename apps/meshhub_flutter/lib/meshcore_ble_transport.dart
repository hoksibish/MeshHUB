import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:meshhub_domain/meshhub_domain.dart';

/// Low-level boundary: all IDs are BlueZ object paths, never name heuristics.
abstract interface class MeshCoreBleDevice {
  String get id;
  bool get paired;
  bool get connected;
  bool get servicesResolved;
  Stream<void> get stateChanges;
  List<MeshCoreGattService> get gattServices;
  Future<void> pair();
  Future<void> connect();
  Future<void> disconnect();
  Future<void> dispose();
}

abstract interface class MeshCoreGattService {
  String get uuid;
  List<MeshCoreGattCharacteristic> get characteristics;
}

abstract interface class MeshCoreGattCharacteristic {
  String get uuid;
  Set<String> get flags;
  Stream<List<int>> get notifications;
  Future<void> startNotify();
  Future<void> stopNotify();
  Future<void> write(List<int> bytes);
}

typedef MeshCoreBleDeviceFactory = Future<MeshCoreBleDevice> Function(
  String id,
);

/// A local GATT write is not RF delivery; errors during writes are uncertain.
class MeshCoreBleTransport implements RadioTransport {
  MeshCoreBleTransport({
    required this.selectedId,
    MeshCoreBleDeviceFactory? deviceFactory,
    this.allowPairing = false,
    this.servicesTimeout = const Duration(seconds: 15),
  }) : _deviceFactory = deviceFactory ?? openSelectedBlueZDevice {
    if (selectedId.isEmpty) throw ArgumentError.value(selectedId, 'selectedId');
  }

  static const serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const rxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const txUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const maxFrameBytes = 176;

  final String selectedId;
  final bool allowPairing;
  final Duration servicesTimeout;
  final MeshCoreBleDeviceFactory _deviceFactory;
  final _frames = StreamController<List<int>>.broadcast();
  final _states = StreamController<bool>.broadcast();
  MeshCoreBleDevice? _device;
  MeshCoreGattCharacteristic? _rx;
  MeshCoreGattCharacteristic? _tx;
  StreamSubscription<void>? _deviceSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  bool _notifyStarted = false;
  bool _receiving = false;
  bool _opening = false;
  int _generation = 0;
  bool _ready = false;
  bool _ownsConnection = false;
  Future<void> _lastWrite = Future<void>.value();

  @override
  MeshProtocol get protocol => MeshProtocol.meshCore;
  @override
  Stream<List<int>> get frames => _frames.stream;
  Stream<bool> get readiness => _states.stream;

  /// GATT notification readiness only; caller must perform Companion handshake.
  bool get ready => _ready;

  void _setReady(bool value) {
    if (_ready == value) return;
    _ready = value;
    _states.add(value);
  }

  @override
  Future<void> open() async {
    if (_opening || _device != null) throw StateError('Transport already open');
    _opening = true;
    final generation = _generation;
    void checkOpen() {
      if (generation != _generation) throw StateError('Opening cancelled');
    }

    try {
      final device = await _deviceFactory(selectedId);
      _device = device;
      checkOpen();
      if (device.id != selectedId) throw StateError('Selected device mismatch');
      _deviceSubscription = device.stateChanges.listen(
        (_) {
          if (!device.connected) {
            _receiving = false;
            _setReady(false);
          }
        },
        onError: (Object _) {
          _receiving = false;
          _setReady(false);
        },
      );
      if (!device.paired) {
        if (!allowPairing) throw StateError('Selected device is not paired');
        // BlueZ/OS agent owns the user interaction; never collect or log a PIN.
        await device.pair();
        checkOpen();
        if (!device.paired) throw StateError('Pairing not confirmed');
      }
      if (!device.connected) {
        _ownsConnection = true;
        await device.connect();
      }
      checkOpen();
      if (!device.connected) throw StateError('Connection not confirmed');
      if (!device.servicesResolved) {
        await device.stateChanges
            .firstWhere((_) => !device.connected || device.servicesResolved)
            .timeout(servicesTimeout);
      }
      checkOpen();
      if (!device.connected) {
        throw StateError('Device disconnected during setup');
      }
      if (!device.servicesResolved) throw StateError('Services not resolved');
      final services = device.gattServices
          .where((s) => s.uuid.toLowerCase() == serviceUuid)
          .toList();
      if (services.length != 1) {
        throw StateError('Expected one MeshCore GATT service');
      }
      MeshCoreGattCharacteristic unique(String uuid) {
        final matches = services.single.characteristics
            .where((c) => c.uuid.toLowerCase() == uuid)
            .toList();
        if (matches.length != 1) {
          throw StateError('Missing or ambiguous MeshCore characteristic');
        }
        return matches.single;
      }

      final rx = unique(rxUuid);
      final tx = unique(txUuid);
      // BlueZ reports characteristic properties, not the ESP32's access
      // permissions. Pairing is required above; encrypted MITM access is
      // enforced by the device when notifications and writes are attempted.
      if (!rx.flags.contains('write') ||
          !tx.flags.containsAll({'notify', 'read'})) {
        throw StateError('MeshCore GATT characteristic properties mismatch');
      }
      _rx = rx;
      _tx = tx;
      _receiving = true;
      _notificationSubscription = tx.notifications.listen(
        (bytes) {
          if (_receiving &&
              _tx == tx &&
              device.connected &&
              bytes.isNotEmpty &&
              bytes.length <= maxFrameBytes) {
            _frames.add(List<int>.unmodifiable(bytes));
          }
        },
        onError: (Object _) {
          _receiving = false;
          _setReady(false);
        },
      );
      await tx.startNotify();
      _notifyStarted = true;
      checkOpen();
      if (!_receiving) {
        throw StateError('Notification stream failed during setup');
      }
      if (!device.connected) {
        throw StateError('Device disconnected during notification setup');
      }
      _setReady(true);
    } catch (_) {
      await close();
      rethrow;
    } finally {
      _opening = false;
    }
  }

  @override
  Future<void> writeFrame(List<int> bytes) async {
    if (bytes.isEmpty ||
        bytes.length > maxFrameBytes ||
        bytes.any((b) => b < 0 || b > 255)) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Frame must contain 1..176 octets',
      );
    }
    if (!_ready || _device?.connected != true) {
      throw StateError('Transport not ready');
    }
    final frame = List<int>.unmodifiable(bytes);
    final generation = _generation;
    final device = _device;
    final rx = _rx;
    final previous = _lastWrite;
    final completion = Completer<void>();
    _lastWrite = completion.future;
    try {
      await previous;
      if (generation != _generation || !_ready || device?.connected != true) {
        throw StateError('Transport not ready');
      }
      // Exactly one whole-frame request. No retry: an interrupted send is uncertain.
      await rx!.write(frame);
      if (generation != _generation || !_ready || device?.connected != true) {
        throw StateError('Write outcome uncertain after disconnect');
      }
    } finally {
      completion.complete();
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    _receiving = false;
    _setReady(false);
    final device = _device;
    final ownsConnection = _ownsConnection;
    _ownsConnection = false;
    _device = null;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    final tx = _tx;
    _tx = null;
    _rx = null;
    try {
      if (_notifyStarted) await tx?.stopNotify();
    } finally {
      _notifyStarted = false;
      await _deviceSubscription?.cancel();
      _deviceSubscription = null;
      if (device != null) {
        try {
          if (ownsConnection && device.connected) await device.disconnect();
        } finally {
          await device.dispose();
        }
      }
    }
  }
}

/// Opens only the exact OS object selected by the caller; no scanning or fallback.
Future<MeshCoreBleDevice> openSelectedBlueZDevice(String id) async {
  final client = BlueZClient();
  try {
    await client.connect();
    final matches = client.devices.where((d) => d.path.value == id).toList();
    if (matches.length != 1) {
      throw StateError('Selected BlueZ device not found');
    }
    return _BlueZDeviceSession(client, matches.single);
  } catch (_) {
    await client.close();
    rethrow;
  }
}

class _BlueZDeviceSession implements MeshCoreBleDevice {
  _BlueZDeviceSession(this.client, this.device);
  final BlueZClient client;
  final BlueZDevice device;
  @override
  String get id => device.path.value;
  @override
  bool get paired => device.paired;
  @override
  bool get connected => device.connected;
  @override
  bool get servicesResolved => device.servicesResolved;
  @override
  Stream<void> get stateChanges => device.propertiesChanged.map((_) {});
  @override
  List<MeshCoreGattService> get gattServices =>
      device.gattServices.map(_BlueZService.new).toList();
  @override
  Future<void> pair() => device.pair();
  @override
  Future<void> connect() => device.connect();
  @override
  Future<void> disconnect() => device.disconnect();
  @override
  Future<void> dispose() => client.close();
}

class _BlueZService implements MeshCoreGattService {
  _BlueZService(this.service);
  final BlueZGattService service;
  @override
  String get uuid => service.uuid.toString();
  @override
  List<MeshCoreGattCharacteristic> get characteristics =>
      service.characteristics.map(_BlueZCharacteristic.new).toList();
}

class _BlueZCharacteristic implements MeshCoreGattCharacteristic {
  _BlueZCharacteristic(this.characteristic);
  final BlueZGattCharacteristic characteristic;
  @override
  String get uuid => characteristic.uuid.toString();
  @override
  Set<String> get flags => characteristic.flags
      .map(
        (flag) => switch (flag) {
          BlueZGattCharacteristicFlag.write => 'write',
          BlueZGattCharacteristicFlag.notify => 'notify',
          BlueZGattCharacteristicFlag.read => 'read',
          BlueZGattCharacteristicFlag.encryptAuthenticatedWrite =>
            'encrypt-authenticated-write',
          BlueZGattCharacteristicFlag.encryptAuthenticatedRead =>
            'encrypt-authenticated-read',
          _ => flag.name,
        },
      )
      .toSet();
  @override
  Stream<List<int>> get notifications => characteristic.propertiesChanged
      .where((names) => names.contains('Value'))
      .map((_) => List<int>.of(characteristic.value));
  @override
  Future<void> startNotify() => characteristic.startNotify();
  @override
  Future<void> stopNotify() => characteristic.stopNotify();
  @override
  Future<void> write(List<int> bytes) => characteristic.writeValue(
    bytes,
    type: BlueZGattCharacteristicWriteType.request,
  );
}
