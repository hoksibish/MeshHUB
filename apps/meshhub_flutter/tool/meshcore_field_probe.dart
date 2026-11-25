import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:meshhub_flutter/field_session.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

/// Read-only handshake; optional local BLE drop/recovery, never RF or queue drain.
Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && args[1] != '--disconnect-test')) {
    stderr.writeln(
      'Usage: dart run tool/meshcore_field_probe.dart <owner-confirmed-name> [--disconnect-test]',
    );
    exitCode = 2;
    return;
  }
  final disconnectTest = args.length == 2;
  final client = BlueZClient();
  MeshCoreFieldSession? session;
  BlueZDevice? target;
  bool initiallyConnected = false;
  try {
    await client.connect();
    final matches = client.devices
        .where(
          (device) =>
              device.name == args.first &&
              device.paired &&
              device.uuids.any(
                (uuid) =>
                    uuid.toString().toLowerCase() ==
                    MeshCoreBleTransport.serviceUuid,
              ),
        )
        .toList();
    if (matches.length != 1) {
      throw StateError('Expected exactly one paired MeshCore candidate');
    }
    target = matches.single;
    initiallyConnected = target.connected;
    final selected = MeshCoreBleCandidate(
      target.path.value,
      target.name,
      MeshCoreCandidateAssessment.serviceUuidKnown,
      false,
    );
    session = MeshCoreFieldSession(receiveMessages: false);
    await session.connect(selected);
    if (!session.connected ||
        session.deviceInfo == null ||
        session.identity == null) {
      throw StateError('Companion handshake not ready');
    }
    final info = session.deviceInfo!;
    final preset = session.identity!.radioPreset;
    stdout.writeln(
      jsonEncode({
        'stage': 'baseline',
        'ready': session.connected,
        'model': info.model,
        'firmware': info.version,
        'frequencyKHz': preset.frequencyKHz,
        'bandwidthHz': preset.bandwidthHz,
        'sf': preset.spreadingFactor,
        'cr': preset.codingRate,
        'rfSent': false,
        'queueDrained': false,
      }),
    );
    if (disconnectTest) {
      await target.disconnect();
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline) &&
          session.reconnectAttempts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      while (DateTime.now().isBefore(deadline) && !session.connected) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      stdout.writeln(
        jsonEncode({
          'stage': 'after-local-ble-drop',
          'reconnectAttempts': session.reconnectAttempts,
          'companionReady': session.connected,
          'firmwareReadAgain': session.deviceInfo?.version == info.version,
          'rfSent': false,
          'queueDrained': false,
        }),
      );
      if (!session.connected || session.reconnectAttempts == 0) exitCode = 4;
    }
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'stage': 'failed',
        'errorType': error.runtimeType.toString(),
        'rfSent': false,
        'queueDrained': false,
      }),
    );
    exitCode = 3;
  } finally {
    try {
      await session?.disconnect();
    } catch (_) {}
    if (disconnectTest && initiallyConnected && target != null) {
      try {
        if (!target.connected) await target.connect();
        stdout.writeln(
          jsonEncode({'initialOsConnectionRestored': target.connected}),
        );
      } catch (_) {
        stdout.writeln(jsonEncode({'initialOsConnectionRestored': false}));
      }
    }
    await client.close();
  }
}
