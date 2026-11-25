import 'dart:async';

import 'package:bluez/bluez.dart';

/// BlueZ's known service UUIDs and names are candidates, not identity proof.
/// The UUID list may be cached from a prior discovery rather than advertised now.
enum MeshCoreCandidateAssessment {
  serviceUuidKnown,
  nameHintOnly,
  unrelated;

  static const serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  static MeshCoreCandidateAssessment assess({
    required String name,
    required Iterable<String> uuids,
  }) {
    if (uuids.any((uuid) => uuid.toLowerCase() == serviceUuid)) {
      return serviceUuidKnown;
    }
    if (name.toLowerCase().startsWith('meshcore-') ||
        name.toLowerCase().contains('heltec')) {
      return nameHintOnly;
    }
    return unrelated;
  }
}

/// A scan observation is unverified; an OS identifier is not a MeshCore identity.
final class MeshCoreBleObservation {
  const MeshCoreBleObservation(
    this.id,
    this.name,
    this.uuids, {
    this.isFresh = true,
  });
  final String id;
  final String name;
  final List<String> uuids;

  /// False for BlueZ cached state not updated during this scan.
  final bool isFresh;
}

final class MeshCoreBleCandidate {
  const MeshCoreBleCandidate(this.id, this.name, this.assessment, this.isFresh);
  final String id;
  final String name;
  final MeshCoreCandidateAssessment assessment;
  final bool isFresh;
}

typedef BleObservationScan = Future<List<MeshCoreBleObservation>> Function(
  Duration duration,
);

/// Reduces raw advertisements to unverified candidates without connecting.
final class MeshCoreBleScanner {
  const MeshCoreBleScanner(this._scan);
  final BleObservationScan _scan;

  Future<List<MeshCoreBleCandidate>> scan(Duration duration) async {
    final byId = <String, MeshCoreBleCandidate>{};
    for (final observation in await _scan(duration)) {
      final assessment = MeshCoreCandidateAssessment.assess(
        name: observation.name,
        uuids: observation.uuids,
      );
      if (assessment == MeshCoreCandidateAssessment.unrelated) continue;
      final prior = byId[observation.id];
      if (prior == null ||
          (!prior.isFresh && observation.isFresh) ||
          (prior.isFresh == observation.isFresh &&
              prior.assessment == MeshCoreCandidateAssessment.nameHintOnly &&
              assessment == MeshCoreCandidateAssessment.serviceUuidKnown)) {
        byId[observation.id] = MeshCoreBleCandidate(
          observation.id,
          observation.name,
          assessment,
          observation.isFresh,
        );
      }
    }
    return List.unmodifiable(byId.values);
  }
}

/// Read-only Linux BLE scan. Returns observations, not verified identities.
/// Does not pair, connect, send frames, or persist device identifiers.
Future<List<MeshCoreBleObservation>> scanBlueZ(Duration duration) async {
  if (duration <= Duration.zero) {
    throw ArgumentError.value(duration, 'duration', 'Must be positive');
  }
  final client = BlueZClient();
  final propertySubscriptions = <StreamSubscription<List<String>>>[];
  StreamSubscription<BlueZDevice>? addedSubscription;
  BlueZAdapter? adapter;
  var discovering = false;
  final observed = <String, MeshCoreBleObservation>{};

  void observe(BlueZDevice device, {bool isFresh = true}) {
    final id = device.path.value;
    observed[id] = MeshCoreBleObservation(
      id,
      device.name.isNotEmpty ? device.name : device.alias,
      device.uuids.map((uuid) => uuid.toString()).toList(),
      isFresh: isFresh,
    );
  }

  void watch(BlueZDevice device) {
    propertySubscriptions.add(
      device.propertiesChanged.listen((_) => observe(device)),
    );
  }

  return withBleCleanup(
    () async {
      await client.connect();
      if (client.adapters.isEmpty) throw StateError('No Bluetooth adapter');
      final selectedAdapter = client.adapters.first;
      adapter = selectedAdapter;
      if (!selectedAdapter.powered) {
        throw StateError('Bluetooth adapter is off');
      }
      for (final device in client.devices) {
        if (device.adapter.address == selectedAdapter.address) {
          observe(device, isFresh: false);
          watch(device);
        }
      }
      addedSubscription = client.deviceAdded.listen((device) {
        if (device.adapter.address != selectedAdapter.address) return;
        observe(device);
        watch(device);
      });
      await selectedAdapter.setDiscoveryFilter(transport: 'le');
      await selectedAdapter.startDiscovery();
      discovering = true;
      await Future<void>.delayed(duration);
      return List.unmodifiable(observed.values);
    },
    () => finishBleDiscovery(
      stop: discovering ? adapter!.stopDiscovery : null,
      cancelAdded: addedSubscription?.cancel,
      cancelProperties: propertySubscriptions.map((s) => s.cancel),
      closeClient: client.close,
    ),
  );
}

/// Preserves a scan error even if resource cleanup independently fails.
Future<T> withBleCleanup<T>(
  Future<T> Function() operation,
  Future<void> Function() cleanup,
) async {
  Object? originalError;
  StackTrace? originalTrace;
  T? result;
  try {
    result = await operation();
  } catch (error, trace) {
    originalError = error;
    originalTrace = trace;
  }
  try {
    await cleanup();
  } catch (error, trace) {
    if (originalError == null) Error.throwWithStackTrace(error, trace);
  }
  if (originalError != null) {
    Error.throwWithStackTrace(originalError, originalTrace!);
  }
  return result as T;
}

/// Always releases D-Bus resources, preserving the first cleanup error.
Future<void> finishBleDiscovery({
  Future<void> Function()? stop,
  Future<void> Function()? cancelAdded,
  required Iterable<Future<void> Function()> cancelProperties,
  required Future<void> Function() closeClient,
}) async {
  Object? firstError;
  StackTrace? firstTrace;
  Future<void> attempt(Future<void> Function()? action) async {
    if (action == null) return;
    try {
      await action();
    } catch (error, trace) {
      firstError ??= error;
      firstTrace ??= trace;
    }
  }

  await attempt(stop);
  await attempt(cancelAdded);
  for (final cancel in cancelProperties) {
    await attempt(cancel);
  }
  await attempt(closeClient);
  if (firstError != null) Error.throwWithStackTrace(firstError!, firstTrace!);
}
