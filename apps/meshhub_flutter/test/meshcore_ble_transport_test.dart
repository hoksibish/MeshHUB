import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

const service = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const rx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const tx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

class FakeCharacteristic implements MeshCoreGattCharacteristic {
  FakeCharacteristic(this.uuid, this.flags);
  @override
  final String uuid;
  @override
  final Set<String> flags;
  final changes = StreamController<List<int>>.broadcast(sync: true);
  final writes = <List<int>>[];
  final events = <String>[];
  Future<void> Function(List<int>)? onWrite;
  void Function()? onStart;
  @override
  Stream<List<int>> get notifications => changes.stream;
  @override
  Future<void> startNotify() async {
    events.add('notify');
    onStart?.call();
  }

  @override
  Future<void> stopNotify() async => events.add('stop');
  @override
  Future<void> write(List<int> bytes) async {
    events.add('write');
    writes.add(List.of(bytes));
    await onWrite?.call(bytes);
  }
}

class FakeService implements MeshCoreGattService {
  FakeService(this.uuid, this.characteristics);
  @override
  final String uuid;
  @override
  final List<MeshCoreGattCharacteristic> characteristics;
}

class FakeDevice implements MeshCoreBleDevice {
  FakeDevice(this.id) {
    services = [
      FakeService(service, [rxChar, txChar]),
    ];
  }
  @override
  final String id;
  bool pairedValue = true;
  bool connectedValue = false;
  bool resolvedValue = false;
  final changes = StreamController<void>.broadcast(sync: true);
  final rxChar = FakeCharacteristic(rx, {
    'write',
    'encrypt-authenticated-write',
  });
  final txChar = FakeCharacteristic(tx, {
    'notify',
    'read',
    'encrypt-authenticated-read',
  });
  late List<MeshCoreGattService> services;
  final calls = <String>[];
  @override
  bool get paired => pairedValue;
  @override
  bool get connected => connectedValue;
  @override
  bool get servicesResolved => resolvedValue;
  @override
  Stream<void> get stateChanges => changes.stream;
  @override
  List<MeshCoreGattService> get gattServices => services;
  @override
  Future<void> pair() async {
    calls.add('pair');
    pairedValue = true;
  }

  @override
  Future<void> connect() async {
    calls.add('connect');
    connectedValue = true;
    changes.add(null);
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connectedValue = false;
    changes.add(null);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  void resolve() {
    resolvedValue = true;
    changes.add(null);
  }

  void drop() {
    connectedValue = false;
    changes.add(null);
  }
}

void main() {
  late FakeDevice device;
  late MeshCoreBleTransport transport;
  setUp(() {
    device = FakeDevice('/org/bluez/hci0/dev_selected');
    transport = MeshCoreBleTransport(
      selectedId: device.id,
      deviceFactory: (id) async {
        expect(id, device.id);
        return device;
      },
      servicesTimeout: const Duration(milliseconds: 80),
    );
  });

  test(
    'selected paired device waits for services then subscribes before ready',
    () async {
      final opening = transport.open();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(transport.ready, isFalse);
      device.resolve();
      await opening;
      expect(transport.protocol, MeshProtocol.meshCore);
      expect(transport.ready, isTrue);
      expect(device.calls, ['connect']);
      expect(device.txChar.events, ['notify']);
      await transport.close();
      expect(device.txChar.events, ['notify', 'stop']);
    },
  );

  test('notification emitted while enabling is not lost', () async {
    device.resolve();
    final received = <List<int>>[];
    final subscription = transport.frames.listen(received.add);
    device.txChar.onStart = () => device.txChar.changes.add([5, 6]);
    await transport.open();
    expect(received, [
      [5, 6],
    ]);
    await subscription.cancel();
    await transport.close();
  });

  test('close during pending device selection cancels opening', () async {
    final selected = Completer<MeshCoreBleDevice>();
    transport = MeshCoreBleTransport(
      selectedId: device.id,
      deviceFactory: (_) => selected.future,
    );
    final opening = transport.open();
    await transport.close();
    selected.complete(device);
    await expectLater(opening, throwsStateError);
    expect(transport.ready, isFalse);
    expect(device.calls, ['dispose']);
  });

  test('notification setup failure cannot report ready', () async {
    device.resolve();
    device.txChar.onStart = () =>
        device.txChar.changes.addError(StateError('lost'));
    await expectLater(transport.open(), throwsStateError);
    expect(transport.ready, isFalse);
  });

  test(
    'notification stream failure degrades and suppresses later frames',
    () async {
      device.resolve();
      final received = <List<int>>[];
      final subscription = transport.frames.listen(received.add);
      await transport.open();
      device.txChar.changes.addError(StateError('notification lost'));
      expect(transport.ready, isFalse);
      device.txChar.changes.add([9]);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await subscription.cancel();
      await transport.close();
    },
  );

  test(
    'paired device can open when BlueZ exposes basic GATT properties',
    () async {
      device.resolve();
      device.rxChar.flags.remove('encrypt-authenticated-write');
      device.txChar.flags.remove('encrypt-authenticated-read');
      await transport.open();
      expect(transport.ready, isTrue);
      await transport.close();
    },
  );

  test('rejects missing write property and disposes connection', () async {
    device.resolve();
    device.services = [
      FakeService(service, [FakeCharacteristic(rx, {}), device.txChar]),
    ];
    await expectLater(transport.open(), throwsStateError);
    expect(transport.ready, isFalse);
    expect(device.calls, ['connect', 'disconnect', 'dispose']);
    expect(device.txChar.events, isEmpty);
  });

  test(
    'rejects a service mismatch without guessing from device name',
    () async {
      device.resolve();
      device.services = [
        FakeService('other', [device.rxChar, device.txChar]),
      ];
      await expectLater(transport.open(), throwsStateError);
      expect(device.calls, ['connect', 'disconnect', 'dispose']);
    },
  );

  test('times out unresolved services and cleans up', () async {
    await expectLater(transport.open(), throwsA(isA<TimeoutException>()));
    expect(device.calls, ['connect', 'disconnect', 'dispose']);
  });

  test('delivers frames and writes one entire 176-byte request', () async {
    device.resolve();
    await transport.open();
    final received = <List<int>>[];
    final subscription = transport.frames.listen(received.add);
    device.txChar.changes.add([7, 8]);
    await transport.writeFrame(List<int>.filled(176, 42));
    await Future<void>.delayed(Duration.zero);
    expect(received, [
      [7, 8],
    ]);
    expect(device.rxChar.writes, [List<int>.filled(176, 42)]);
    await expectLater(
      transport.writeFrame(List<int>.filled(177, 42)),
      throwsArgumentError,
    );
    await expectLater(transport.writeFrame([]), throwsArgumentError);
    await expectLater(transport.writeFrame([256]), throwsArgumentError);
    expect(device.rxChar.writes.length, 1);
    await subscription.cancel();
    await transport.close();
  });

  test(
    'disconnect during send leaves outcome uncertain without replay',
    () async {
      device.resolve();
      await transport.open();
      device.rxChar.onWrite = (_) async => device.drop();
      await expectLater(transport.writeFrame([4]), throwsStateError);
      expect(device.rxChar.writes, [
        [4],
      ]);
      expect(transport.ready, isFalse);
      await expectLater(transport.writeFrame([4]), throwsStateError);
      await transport.close();
      device.resolve();
      await transport.open();
      expect(device.rxChar.writes, [
        [4],
      ]);
      await transport.close();
    },
  );

  test(
    'old write stays uncertain when connection reopens before it completes',
    () async {
      device.resolve();
      await transport.open();
      final pending = Completer<void>();
      device.rxChar.onWrite = (_) => pending.future;
      final write = transport.writeFrame([3]);
      await Future<void>.delayed(Duration.zero);
      await transport.close();
      await transport.open();
      pending.complete();
      await expectLater(write, throwsStateError);
      expect(device.rxChar.writes, [
        [3],
      ]);
      await transport.close();
    },
  );

  test('does not disconnect a device connected before this session', () async {
    device.connectedValue = true;
    device.resolve();
    await transport.open();
    await transport.close();
    expect(device.calls, ['dispose']);
  });

  test('unpaired device requires explicit pairing permission', () async {
    device.pairedValue = false;
    await expectLater(transport.open(), throwsStateError);
    expect(device.calls, ['dispose']);
    transport = MeshCoreBleTransport(
      selectedId: device.id,
      allowPairing: true,
      deviceFactory: (_) async => device,
      servicesTimeout: const Duration(milliseconds: 80),
    );
    device.resolve();
    await transport.open();
    expect(device.calls, ['dispose', 'pair', 'connect']);
    await transport.close();
  });
}
