import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/main.dart';

void main() {
  testWidgets(
    'radio panel offers explicit discovery without implicit RF send',
    (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MeshHubApp());
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Radios & Bluetooth'));
      await tester.pumpAndSettle();
      expect(find.text('Discover MeshCore radios'), findsOneWidget);
      expect(find.text('No radio selected'), findsOneWidget);
      expect(find.text('Direct test message'), findsOneWidget);
      expect(find.textContaining('SIMULATED DATA'), findsNothing);
    },
  );

  testWidgets('inbox exposes a channel feed without invented radio channels', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Channels'), findsWidgets);
    expect(find.textContaining('Connect a MeshCore radio'), findsOneWidget);
    expect(find.text('Public'), findsNothing);
    expect(find.text('Send once (local radio acceptance only)'), findsNothing);
  });

  testWidgets('channel heading remains readable on the dark surface', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    final heading = find.text('Channels').last;
    final context = tester.element(heading);
    final expected = Theme.of(context).colorScheme.onSurface;
    expect(tester.widget<Text>(heading).style?.color, expected);
  });

  testWidgets('inbox labels sample data and separates protocols', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    expect(find.text('MeshHub'), findsOneWidget);
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    expect(find.text('MeshCore example'), findsNothing);
    await tester.tap(find.text('Show simulated examples'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SIMULATED'), findsWidgets);
    expect(find.text('MeshCore example'), findsOneWidget);
    expect(find.text('Meshtastic example'), findsOneWidget);

    await tester.tap(find.text('MeshCore').last);
    await tester.pumpAndSettle();
    expect(find.text('MeshCore example'), findsOneWidget);
    expect(find.text('Meshtastic example'), findsNothing);
  });
}
