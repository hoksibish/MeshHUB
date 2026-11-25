import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/firmware_manager_screen.dart';
import 'package:meshhub_flutter/firmware_manager_service.dart';

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

    final commands = <List<String>>[];
    final service = FirmwareManagerService(
      libraryPath: scratch.path,
      runTool: (args, limit) async {
        commands.add(args);
        return const FirmwareToolResult(0, 'Chip is ESP32-S3');
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: FirmwareManagerScreen(
        tactical: false,
        radioConnected: () => false,
        service: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Heltec WiFi LoRa 32 V3 · ESP32-S3 USB'), findsOneWidget);
    expect(find.text('MeshCore'), findsOneWidget);
    expect(find.text('Meshtastic'), findsOneWidget);
    expect(find.textContaining('full -merged.bin'), findsOneWidget);
    await tester.tap(find.text('Meshtastic'));
    await tester.pumpAndSettle();
    expect(find.textContaining('full .factory.bin'), findsOneWidget);
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

    await tester.pumpWidget(MaterialApp(
      home: FirmwareManagerScreen(
        tactical: true,
        radioConnected: () => false,
        service: FirmwareManagerService(libraryPath: scratch.path),
      ),
    ));
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
    expect(find.textContaining('Requires separate ERASE confirmation.'),
        findsOneWidget);
  });
}
