import 'dart:convert';
import 'dart:io';

import 'package:bluez/bluez.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Provide the owner-confirmed BLE name.');
    exitCode = 2;
    return;
  }
  final client = BlueZClient();
  try {
    await client.connect();
    final matches = client.devices.where((d) => d.name == args.single).toList();
    if (matches.length != 1) {
      stdout.writeln(
        jsonEncode({'uniqueTarget': false, 'matches': matches.length}),
      );
      exitCode = 3;
      return;
    }
    final device = matches.single;
    final services = device.gattServices
        .where(
          (s) =>
              s.uuid.toString().toLowerCase() ==
              '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
        )
        .toList();
    stdout.writeln(
      jsonEncode({
        'uniqueTarget': true,
        'paired': device.paired,
        'connected': device.connected,
        'servicesResolved': device.servicesResolved,
        'meshCoreServiceCount': services.length,
        'meshCoreCharacteristicCount': services.length == 1
            ? services.single.characteristics.length
            : 0,
        'characteristics': services.length == 1
            ? services.single.characteristics
                  .map(
                    (c) => {
                      'uuid': c.uuid.toString(),
                      'flags': c.flags.map((f) => f.name).toList(),
                    },
                  )
                  .toList()
            : [],
        'firmwareRead': false,
      }),
    );
  } finally {
    await client.close();
  }
}
