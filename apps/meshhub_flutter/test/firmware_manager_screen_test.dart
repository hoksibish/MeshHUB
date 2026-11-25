import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/firmware_manager_screen.dart';
import 'package:meshhub_flutter/firmware_manager_service.dart';
import 'package:meshhub_flutter/firmware_hardware_catalog.dart';

FirmwareBoardCatalog fixtureCatalog() => FirmwareBoardCatalog.parse('''
{
  "schema": 1,
  "boards": [
    {
      "id": "meshcore-heltec-v3",
      "family": "meshCore",
      "name": "Heltec v3",
      "architecture": "esp32",
      "chip": "esp32s3",
      "method": "esptool",
      "patterns": [{"role": "Companion BLE", "pattern": "Heltec_v3", "format": "merged"}]
    },
    {
      "id": "meshtastic-heltec-v3",
      "family": "meshtastic",
      "name": "Heltec V3",
      "architecture": "esp32-s3",
      "chip": "esp32s3",
      "method": "esptool",
      "patterns": [{"role": "Meshtastic node", "pattern": "firmware-heltec-v3", "format": "factory"}]
    }
  ]
}
''');

void main() {
  late Directory scratch;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('firmware-ui-test-');
  });
  tearDown(() async {
    await scratch.delete(recursive: true);
  });

  testWidgets('firmware family selection updates formats without flashing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalog = fixtureCatalog();
    final commands = <List<String>>[];
    final service = FirmwareManagerService(
      libraryPath: scratch.path,
      runTool: (args, limit) async {
        commands.add(args);
        return const FirmwareToolResult(0, 'Chip is ESP32-S3');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FirmwareManagerScreen(
          tactical: false,
          radioConnected: () => false,
          service: service,
          boardCatalog: catalog,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heltec v3'), findsWidgets);
    expect(find.text('MeshCore'), findsOneWidget);
    expect(find.text('Meshtastic'), findsOneWidget);
    expect(find.textContaining('USB esptool supported'), findsOneWidget);
    await tester.tap(find.text('Meshtastic'));
    await tester.pumpAndSettle();
    expect(find.text('Heltec V3'), findsWidgets);
    expect(find.text('Inspect image'), findsOneWidget);
    expect(commands, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Flash firmware'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Flash firmware'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('full erase is opt-in and disabled by default', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalog = fixtureCatalog();
    await tester.pumpWidget(
      MaterialApp(
        home: FirmwareManagerScreen(
          tactical: true,
          radioConnected: () => false,
          service: FirmwareManagerService(libraryPath: scratch.path),
          boardCatalog: catalog,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final erase = find.byKey(const Key('firmware-erase-first'));
    await tester.scrollUntilVisible(
      erase,
      350,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.widget<CheckboxListTile>(erase).value, false);
    await tester.tap(erase);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(erase).value, true);
    expect(
      find.textContaining('Requires separate ERASE confirmation.'),
      findsOneWidget,
    );
  });
}
