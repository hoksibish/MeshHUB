import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';

/// Explicit, one-shot owner-initiated pairing diagnostic. Never accepts a PIN.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Provide exactly one owner-confirmed BLE name.');
    exitCode = 2;
    return;
  }
  final observations = await scanBlueZ(const Duration(seconds: 12));
  final selected = observations
      .where(
        (o) =>
            o.isFresh &&
            o.name == args.single &&
            MeshCoreCandidateAssessment.assess(name: o.name, uuids: o.uuids) ==
                MeshCoreCandidateAssessment.serviceUuidKnown,
      )
      .toList();
  if (selected.length != 1) {
    stdout.writeln(
      jsonEncode({'uniqueConfirmedCandidate': false, 'paired': false}),
    );
    exitCode = 3;
    return;
  }
  final client = BlueZClient();
  try {
    await client.connect();
    final matches = client.devices
        .where((d) => d.path.value == selected.single.id)
        .toList();
    if (matches.length != 1) throw StateError('Selected candidate disappeared');
    final device = matches.single;
    if (!device.paired) {
      try {
        await device.pair().timeout(const Duration(seconds: 25));
      } on TimeoutException {
        await device.cancelPairing();
        throw StateError('Pairing timed out; use local BlueZ UI/agent');
      }
    }
    stdout.writeln(
      jsonEncode({
        'uniqueConfirmedCandidate': true,
        'paired': device.paired,
        'connected': device.connected,
        'firmwareRead': false,
      }),
    );
  } catch (error) {
    // Do not echo D-Bus errors: they can include device identifiers or PIN data.
    stdout.writeln(
      jsonEncode({
        'uniqueConfirmedCandidate': true,
        'paired': false,
        'errorType': error.runtimeType.toString(),
        'firmwareRead': false,
      }),
    );
    exitCode = 4;
  } finally {
    await client.close();
  }
}
