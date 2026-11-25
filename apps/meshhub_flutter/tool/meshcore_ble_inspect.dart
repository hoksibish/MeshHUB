import 'dart:convert';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';

Future<void> main() async {
  final candidates = await const MeshCoreBleScanner(scanBlueZ)
      .scan(const Duration(seconds: 12));
  final serviceCandidates = candidates
      .where(
        (c) =>
            c.isFresh &&
            c.assessment == MeshCoreCandidateAssessment.serviceUuidKnown,
      )
      .toList();
  if (serviceCandidates.length != 1) {
    stdout.writeln(
      jsonEncode({
        'freshServiceCandidates': serviceCandidates.length,
        'uniqueTarget': false,
        'connected': false,
      }),
    );
    return;
  }
  final client = BlueZClient();
  try {
    await client.connect();
    final matches = client.devices
        .where((d) => d.path.value == serviceCandidates.single.id)
        .toList();
    if (matches.length != 1) throw StateError('Selected candidate disappeared');
    final device = matches.single;
    stdout.writeln(
      jsonEncode({
        'freshServiceCandidates': 1,
        'uniqueTarget': true,
        'name': device.name,
        'paired': device.paired,
        'connected': device.connected,
        'servicesResolved': device.servicesResolved,
        'firmwareRead': false,
      }),
    );
  } finally {
    await client.close();
  }
}
