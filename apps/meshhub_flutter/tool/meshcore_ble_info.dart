import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

/// Read-only Companion handshake. Never prints a PIN, key, address or frame.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Provide exactly one owner-confirmed BLE name.');
    exitCode = 2;
    return;
  }
  final client = BlueZClient();
  String selectedId;
  try {
    await client.connect();
    final matches = client.devices
        .where(
          (d) =>
              d.name == args.single &&
              d.paired &&
              d.uuids.any(
                (uuid) =>
                    uuid.toString().toLowerCase() ==
                    MeshCoreBleTransport.serviceUuid,
              ),
        )
        .toList();
    if (matches.length != 1) {
      stdout.writeln(
        jsonEncode({
          'pairedMeshCoreCandidates': matches.length,
          'handshakeReady': false,
        }),
      );
      exitCode = 3;
      return;
    }
    selectedId = matches.single.path.value;
  } finally {
    await client.close();
  }

  final transport = MeshCoreBleTransport(selectedId: selectedId);
  var stage = 'gatt';
  try {
    await transport.open();
    stage = 'appStart';
    final selfReply = transport.frames
        .firstWhere((frame) => frame.isNotEmpty && frame[0] == 5)
        .timeout(const Duration(seconds: 6));
    await transport.writeFrame(MeshCoreCompanionCodec.appStart('MeshHub'));
    final self = await selfReply;
    final identity = MeshCoreCompanionCodec.parseSelfInfo(self);
    stage = 'deviceQuery';
    final infoReply = transport.frames
        .firstWhere((frame) => frame.isNotEmpty && frame[0] == 13)
        .timeout(const Duration(seconds: 6));
    await transport.writeFrame(MeshCoreCompanionCodec.deviceQuery());
    final info = MeshCoreCompanionCodec.parseDeviceInfo(await infoReply);
    stdout.writeln(
      jsonEncode({
        'gattReady': true,
        'selfInfoReceived': true,
        'fullPublicIdentityRead': identity.publicKey.length == 32,
        'protocolVersion': info.firmwareCode,
        'model': info.model,
        'firmwareVersion': info.version,
        'build': info.build,
        'maxChannels': info.maxChannels,
        'frequencyKHz': identity.radioPreset.frequencyKHz,
        'bandwidthHz': identity.radioPreset.bandwidthHz,
        'spreadingFactor': identity.radioPreset.spreadingFactor,
        'codingRate': identity.radioPreset.codingRate,
        'pinExposed': false,
        'rfSent': false,
        'rfReceived': false,
      }),
    );
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'stage': stage,
        'handshakeReady': false,
        'errorType': error.runtimeType.toString(),
        'rfSent': false,
        'rfReceived': false,
      }),
    );
    exitCode = 4;
  } finally {
    await transport.close();
  }
}
