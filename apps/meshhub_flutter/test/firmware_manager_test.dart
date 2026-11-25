import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/firmware_manager_service.dart';

void main() {
  late Directory temp;
  late File firmware;
  late List<List<String>> commands;
  late FirmwareManagerService manager;
  var chipFound = true;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('meshhub-firmware-test-');
    firmware = File(
      '${temp.path}/Heltec_v3_companion_radio_ble-v1.18.0-merged.bin',
    );
    final bytes = List<int>.filled(128 * 1024, 0xff);
    bytes[0] = 0xe9;
    bytes[1] = 2;
    await firmware.writeAsBytes(bytes);
    commands = [];
    chipFound = true;
    manager = FirmwareManagerService(
      libraryPath: '${temp.path}/offline',
      runTool: (args, limit) async {
        commands.add(List<String>.of(args));
        if (args.contains('flash-id')) {
          return FirmwareToolResult(
            chipFound ? 0 : 1,
            chipFound ? 'Chip is ESP32-S3 (fake)' : 'Not connected',
          );
        }
        return const FirmwareToolResult(0, 'Hash of data verified');
      },
    );
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('inspects exact merged target and hashes entirely offline', () async {
    final inspection = await manager.inspectFile(firmware.path);
    expect(inspection.sourceName, contains('Heltec_v3_companion'));
    expect(inspection.bytes, 128 * 1024);
    expect(inspection.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(commands, isEmpty);
    expect(FirmwareManagerService.validPort('/dev/ttyACM0'), true);
    expect(FirmwareManagerService.validPort('/dev/serial/by-id/usb-X_23'), true);
    expect(FirmwareManagerService.validPort('/tmp/ttyUSB0;rm -rf /'), false);
  });

  test('rejects wrong board, non-merged image, mismatched digest and header', () async {
    final wrongBoard = File('${temp.path}/heltec_v4_companion-merged.bin');
    await firmware.copy(wrongBoard.path);
    await expectLater(
      manager.inspectFile(wrongBoard.path),
      throwsFormatException,
    );
    final nonMerged = File('${temp.path}/Heltec_v3_companion.bin');
    await firmware.copy(nonMerged.path);
    await expectLater(
      manager.inspectFile(nonMerged.path),
      throwsFormatException,
    );
    await expectLater(
      manager.inspectFile(
        firmware.path,
        expectedSha256: List<String>.filled(64, '0').join(),
      ),
      throwsFormatException,
    );
    final bad = await firmware.readAsBytes();
    bad[0] = 0;
    await firmware.writeAsBytes(bad);
    await expectLater(
      manager.inspectFile(firmware.path),
      throwsFormatException,
    );
    expect(commands, isEmpty);
  });

  test('imported image is cached, listed, and reverified before use', () async {
    final image = await manager.inspectFile(firmware.path);
    final saved = await manager.saveOffline(image);
    expect(saved.sha256, image.sha256);
    expect(saved.path, isNot(firmware.path));
    expect((await manager.savedImages()).single.sourceName, image.sourceName);
    await File(saved.path).writeAsBytes([0xe9, 2, 0, 0]);
    expect(await manager.savedImages(), isEmpty);
    expect(commands, isEmpty);
  });

  test('no USB write without explicit confirmation', () async {
    final image = await manager.inspectFile(firmware.path);
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: false,
      ),
      throwsStateError,
    );
    expect(commands, isEmpty);
  });

  test('read-only preflight enforces recognized ESP32-S3 and serial port', () async {
    await expectLater(
      manager.checkUsb('/dev/ttyACM0;reboot'),
      throwsFormatException,
    );
    expect(commands, isEmpty);

    chipFound = false;
    await expectLater(
      manager.checkUsb('/dev/ttyACM0'),
      throwsStateError,
    );
    expect(commands.length, 1);
    expect(commands.single.last, 'flash-id');
    expect(commands.where((args) => args.contains('write-flash')), isEmpty);
  });

  test('explicit flash verifies image/chip and runs one guarded write', () async {
    final image = await manager.inspectFile(firmware.path);
    await manager.flashMergedImage(
      image: image,
      port: '/dev/ttyACM0',
      userConfirmed: true,
    );
    expect(commands, hasLength(2));
    expect(commands.first, [
      '--chip', 'esp32s3', '--port', '/dev/ttyACM0', 'flash-id',
    ]);
    expect(commands.last, [
      '--chip', 'esp32s3',
      '--port', '/dev/ttyACM0',
      '--baud', '115200',
      'write-flash', '0x0', firmware.absolute.path,
    ]);
    expect(commands.where((args) => args.contains('erase-flash')), isEmpty);
    expect(commands.where((args) => args.contains('write-flash')), hasLength(1));
  });

  test('tampering after inspection blocks write before chip probe', () async {
    final image = await manager.inspectFile(firmware.path);
    final bytes = await firmware.readAsBytes();
    bytes[1000] = 0;
    await firmware.writeAsBytes(bytes);
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
      ),
      throwsFormatException,
    );
    expect(commands, isEmpty);
  });
}
