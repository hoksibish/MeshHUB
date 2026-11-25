import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/firmware_manager_service.dart';
import 'package:meshhub_flutter/firmware_hardware_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    expect(
      FirmwareManagerService.validPort('/dev/serial/by-id/usb-X_23'),
      true,
    );
    expect(FirmwareManagerService.validPort('/tmp/ttyUSB0;rm -rf /'), false);
  });

  test(
    'rejects wrong board, non-merged image, mismatched digest and header',
    () async {
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
    },
  );

  test('imported image is cached, listed, and reverified before use', () async {
    final image = await manager.inspectFile(firmware.path);
    final saved = await manager.saveOffline(image);
    expect(saved.sha256, image.sha256);
    expect(saved.path, isNot(firmware.path));
    expect((await manager.savedImages()).single.sourceName, image.sourceName);
    expect((await manager.saveOffline(saved)).sha256, saved.sha256);
    await File(saved.path).writeAsBytes([0xe9, 2, 0, 0]);
    expect(await manager.savedImages(), isEmpty);
    expect(commands, isEmpty);
  });

  test('recognizes MeshCore roles and all release versions', () {
    final fixtures = <String, String>{
      'Heltec_v3_companion_radio_ble-v1.18.0-81dbae5-merged.bin':
          'Companion BLE',
      'Heltec_v3_companion_radio_usb-v1.21.7-merged.bin': 'Companion USB',
      'Heltec_v3_repeater-v2.5.0-abcd123-merged.bin': 'Repeater',
      'Heltec_v3_room_server-v1.19.7-merged.bin': 'Room Server',
      'Heltec_v3_sensor-v1.20.0-alpha-merged.bin': 'Sensor',
    };
    for (final item in fixtures.entries) {
      final parsed = FirmwareManagerService.recognizePackage(item.key);
      expect(parsed?.family, FirmwareFamily.meshCore);
      expect(parsed?.role, item.value);
      expect(parsed?.flashOffset, '0x0');
    }
  });

  test('recognizes Meshtastic factory releases without version lock-in', () {
    for (final name in [
      'firmware-heltec-v3-2.7.19.bb3d6d5.factory.bin',
      'firmware-heltec-v3-2.8.3.d0f4096.factory.bin',
      'firmware-heltec_v3-2.6.0.factory.bin',
    ]) {
      final parsed = FirmwareManagerService.recognizePackage(name);
      expect(parsed?.family, FirmwareFamily.meshtastic);
      expect(parsed?.role, 'Meshtastic node');
      expect(parsed?.flashOffset, '0x0');
    }
    for (final name in [
      'firmware-heltec-v4-2.8.0.factory.bin',
      'firmware-heltec-v3-2.8.0.bin',
      'firmware-heltec-v3-2.8.0-ota.bin',
      'firmware-esp32s3-2.8.0.zip',
      'Heltec_v3_companion_radio_ble-v1.20.0.bin',
      'Heltec_v4_repeater-v1.20.0-merged.bin',
      'Heltec_v3_mystery_role-v1.20.0-merged.bin',
    ]) {
      expect(
        FirmwareManagerService.recognizePackage(name),
        isNull,
        reason: name,
      );
    }
  });

  test('inspects Meshtastic factory image and rejects wrong family', () async {
    final factory = File(
      '${temp.path}/firmware-heltec-v3-2.8.3.d0f4096.factory.bin',
    );
    await firmware.copy(factory.path);
    final image = await manager.inspectFile(
      factory.path,
      expectedFamily: FirmwareFamily.meshtastic,
    );
    expect(image.package.role, 'Meshtastic node');
    expect(image.package.version, '2.8.3.d0f4096');
    await expectLater(
      manager.inspectFile(
        factory.path,
        expectedFamily: FirmwareFamily.meshCore,
      ),
      throwsFormatException,
    );
    await expectLater(
      manager.inspectFile(
        firmware.path,
        expectedFamily: FirmwareFamily.meshtastic,
      ),
      throwsFormatException,
    );
    expect(commands, isEmpty);
  });

  test('offline library retains both firmware ecosystems', () async {
    final meshcore = await manager.inspectFile(firmware.path);
    await manager.saveOffline(meshcore);
    final factory = File(
      '${temp.path}/firmware-heltec-v3-2.8.3.d0f4096.factory.bin',
    );
    final bytes = await firmware.readAsBytes();
    bytes[201] = 0xaa;
    await factory.writeAsBytes(bytes);
    final meshtastic = await manager.inspectFile(factory.path);
    await manager.saveOffline(meshtastic);
    final images = await manager.savedImages();
    expect(images, hasLength(2));
    expect(images.map((i) => i.package.family).toSet(), {
      FirmwareFamily.meshCore,
      FirmwareFamily.meshtastic,
    });
    expect(images.map((i) => i.package.role).toSet(), {
      'Companion BLE',
      'Meshtastic node',
    });
  });

  test('Meshtastic factory flash uses full image offset 0x0', () async {
    final factory = File(
      '${temp.path}/firmware-heltec-v3-2.8.3.d0f4096.factory.bin',
    );
    await firmware.copy(factory.path);
    final image = await manager.inspectFile(factory.path);
    await manager.flashMergedImage(
      image: image,
      port: '/dev/ttyACM0',
      userConfirmed: true,
    );
    expect(commands, hasLength(2));
    expect(
      commands.last,
      containsAllInOrder(['write-flash', '0x0', factory.absolute.path]),
    );
    expect(commands.where((args) => args.contains('erase-flash')), isEmpty);
  });

  test('full erase must be explicitly confirmed separately', () async {
    final image = await manager.inspectFile(firmware.path);
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
        eraseFirst: true,
        eraseConfirmed: false,
      ),
      throwsStateError,
    );
    expect(commands, isEmpty);
    await manager.flashMergedImage(
      image: image,
      port: '/dev/ttyACM0',
      userConfirmed: true,
      eraseFirst: true,
      eraseConfirmed: true,
    );
    expect(commands.map((args) => args.last), [
      'flash-id',
      'erase-flash',
      firmware.absolute.path,
    ]);
    expect(
      commands.where((args) => args.contains('erase-flash')),
      hasLength(1),
    );
  });

  test('BLE activation after erase prevents any firmware write', () async {
    final image = await manager.inspectFile(firmware.path);
    var checks = 0;
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
        eraseFirst: true,
        eraseConfirmed: true,
        mayWrite: () => checks++ == 0,
      ),
      throwsStateError,
    );
    expect(commands, hasLength(2));
    expect(commands.last, contains('erase-flash'));
    expect(commands.where((args) => args.contains('write-flash')), isEmpty);
  });

  test(
    'offline catalog includes both firmware ecosystems and exact models',
    () async {
      final catalog = await FirmwareBoardCatalog.load();
      expect(catalog.forFamily('meshCore').length, greaterThan(50));
      expect(catalog.forFamily('meshtastic').length, greaterThan(90));
      expect(catalog.byId('meshcore-heltec-v3')?.chip, 'esp32s3');
      expect(catalog.byId('meshtastic-heltec-v3')?.chip, 'esp32s3');
      expect(catalog.byId('meshtastic-tbeam')?.chip, 'esp32');
      expect(catalog.byId('meshtastic-rak4631')?.offersUf2, true);
      expect(catalog.byId('meshtastic-rak4631')?.supportsUsbFlash, false);
      expect(catalog.byId('meshcore-heltec-t114')?.supportsUsbFlash, false);
    },
  );

  test('board profile controls allowed firmware and MCU preflight', () async {
    final catalog = await FirmwareBoardCatalog.load();
    final heltec3 = catalog.byId('meshcore-heltec-v3')!;
    final heltec4 = catalog.byId('meshcore-heltec-v4')!;
    final image = await manager.inspectFile(
      firmware.path,
      board: heltec3,
      expectedFamily: FirmwareFamily.meshCore,
    );
    expect(image.package.boardId, heltec3.id);
    expect(image.package.supportsDirectUsb, true);
    await expectLater(
      manager.inspectFile(firmware.path, board: heltec4),
      throwsFormatException,
    );
    expect(commands, isEmpty);
    await manager.flashMergedImage(
      image: image,
      port: '/dev/ttyACM0',
      userConfirmed: true,
    );
    expect(commands.first, [
      '--chip',
      'esp32s3',
      '--port',
      '/dev/ttyACM0',
      'flash-id',
    ]);
  });

  test('nRF UF2 images can be saved for guided offline installation', () async {
    final catalog = await FirmwareBoardCatalog.load();
    final rak = catalog.byId('meshtastic-rak4631')!;
    final uf2 = File('${temp.path}/firmware-rak4631-2.8.3.d0f4096.uf2');
    final blocks = List<int>.filled(128 * 1024, 0);
    blocks.setRange(0, 8, [0x55, 0x46, 0x32, 0x0a, 0x57, 0x51, 0x5d, 0x9e]);
    await uf2.writeAsBytes(blocks);
    final inspected = await manager.inspectFile(
      uf2.path,
      board: rak,
      expectedFamily: FirmwareFamily.meshtastic,
    );
    expect(inspected.package.imageKind, 'uf2');
    expect(inspected.package.supportsDirectUsb, false);
    final cached = await manager.saveOffline(inspected);
    expect(cached.package.boardId, rak.id);
    expect((await manager.savedImages()).single.package.boardId, rak.id);
    await expectLater(
      manager.flashMergedImage(
        image: inspected,
        port: '/dev/ttyACM0',
        userConfirmed: true,
      ),
      throwsFormatException,
    );
    expect(commands, isEmpty);
  });

  test('wrong firmware magic is rejected on a selected UF2 board', () async {
    final rak = (await FirmwareBoardCatalog.load()).byId('meshtastic-rak4631')!;
    final file = File('${temp.path}/firmware-rak4631-2.8.3.d0f4096.uf2');
    await firmware.copy(file.path);
    await expectLater(
      manager.inspectFile(file.path, board: rak),
      throwsFormatException,
    );
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

  test(
    'read-only preflight enforces recognized ESP32-S3 and serial port',
    () async {
      await expectLater(
        manager.checkUsb('/dev/ttyACM0;reboot'),
        throwsFormatException,
      );
      expect(commands, isEmpty);

      chipFound = false;
      await expectLater(manager.checkUsb('/dev/ttyACM0'), throwsStateError);
      expect(commands.length, 1);
      expect(commands.single.last, 'flash-id');
      expect(commands.where((args) => args.contains('write-flash')), isEmpty);
    },
  );

  test(
    'explicit flash verifies image/chip and runs one guarded write',
    () async {
      final image = await manager.inspectFile(firmware.path);
      await manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
      );
      expect(commands, hasLength(2));
      expect(commands.first, [
        '--chip',
        'esp32s3',
        '--port',
        '/dev/ttyACM0',
        'flash-id',
      ]);
      expect(commands.last, [
        '--chip',
        'esp32s3',
        '--port',
        '/dev/ttyACM0',
        '--baud',
        '115200',
        'write-flash',
        '0x0',
        firmware.absolute.path,
      ]);
      expect(commands.where((args) => args.contains('erase-flash')), isEmpty);
      expect(
        commands.where((args) => args.contains('write-flash')),
        hasLength(1),
      );
    },
  );

  test('failed full erase stops before firmware write', () async {
    final image = await manager.inspectFile(firmware.path);
    manager = FirmwareManagerService(
      libraryPath: '${temp.path}/offline',
      runTool: (args, limit) async {
        commands.add(List<String>.of(args));
        if (args.contains('flash-id')) {
          return const FirmwareToolResult(0, 'Chip is ESP32-S3');
        }
        return const FirmwareToolResult(1, 'erase unsuccessful');
      },
    );
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
        eraseFirst: true,
        eraseConfirmed: true,
      ),
      throwsStateError,
    );
    expect(commands, hasLength(2));
    expect(commands.last, contains('erase-flash'));
    expect(commands.where((args) => args.contains('write-flash')), isEmpty);
  });

  test('active Bluetooth state blocks a write after USB preflight', () async {
    final image = await manager.inspectFile(firmware.path);
    await expectLater(
      manager.flashMergedImage(
        image: image,
        port: '/dev/ttyACM0',
        userConfirmed: true,
        mayWrite: () => false,
      ),
      throwsStateError,
    );
    expect(commands, hasLength(1));
    expect(commands.single.last, 'flash-id');
    expect(commands.where((args) => args.contains('write-flash')), isEmpty);
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
