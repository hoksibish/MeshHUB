import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/main.dart';
import 'package:meshhub_flutter/tactical_hud.dart';

/// Tap the Channels destination, not the identically named page heading.
Future<void> openChannels(WidgetTester tester) async {
  final navigation = find.byType(NavigationRail).evaluate().isNotEmpty
      ? find.byType(NavigationRail)
      : find.byType(NavigationBar);
  final destination = find.descendant(
    of: navigation,
    matching: find.text('Channels'),
  );
  expect(destination, findsOneWidget);
  await tester.tap(destination);
  await tester.pumpAndSettle();
}

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
      await tester.scrollUntilVisible(
        find.text('Direct test message'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Direct test message'), findsOneWidget);
      expect(find.textContaining('SIMULATED DATA'), findsNothing);
    },
  );

  testWidgets('inbox exposes a channel feed without invented radio channels', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    await openChannels(tester);
    expect(find.text('Channels'), findsWidgets);
    expect(find.textContaining('Connect a MeshCore radio'), findsOneWidget);
    expect(find.text('Public'), findsNothing);
    expect(find.text('Send once (local radio acceptance only)'), findsNothing);
  });

  testWidgets('channel heading remains readable on the dark surface', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    await openChannels(tester);
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
    await openChannels(tester);
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
  testWidgets('all three themes use distinct scaffold and rail surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.pumpAndSettle();

    Color background() {
      final context = tester.element(find.byType(Scaffold).first);
      return Theme.of(context).scaffoldBackgroundColor;
    }

    final dark = background();
    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('light').last);
    await tester.pumpAndSettle();
    final light = background();
    expect(light, isNot(dark));
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tactical').last);
    await tester.pumpAndSettle();
    final tactical = background();
    expect(tactical, isNot(dark));
    expect(tactical, isNot(light));
  });

  testWidgets('tactical HUD renders command panels and channel modules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tactical').last);
    await tester.pumpAndSettle();

    expect(find.byType(TacticalHudBackdrop), findsOneWidget);
    expect(find.byType(TacticalHudMetric), findsNWidgets(3));
    expect(find.byType(TacticalHudLinkScope), findsOneWidget);
    expect(find.text('OPERATIONS // OVERVIEW'), findsOneWidget);
    expect(find.text('MESHHUB / MESSAGES'), findsOneWidget);

    await openChannels(tester);
    expect(find.text('CHANNEL ARRAY'), findsOneWidget);
    expect(find.byType(TacticalHudBackdrop), findsOneWidget);
  });

  testWidgets('tactical status strip fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tactical').last);
    await tester.pumpAndSettle();

    expect(find.byType(TacticalHudBackdrop), findsOneWidget);
    expect(find.text('MESSAGES'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await openChannels(tester);
    expect(find.text('CHANNEL ARRAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'nodes screen shows verified-state placeholders without fake telemetry',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MeshHubApp());
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Nodes'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Node inventory'), findsOneWidget);
      expect(
        find.textContaining('No live node inventory source'),
        findsOneWidget,
      );
      expect(find.text('Verified node inventory'), findsOneWidget);
      expect(
        find.textContaining('empty inventory here does not mean'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tactical Nodes and Radios retain compact console navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tactical').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Nodes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NODE MONITOR'), findsOneWidget);
    expect(find.byType(TacticalHudPanel), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Radios'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('COMMUNICATIONS CONSOLE'), findsOneWidget);
    expect(find.text('Discover MeshCore radios'), findsOneWidget);
    expect(find.text('CONNECTION'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light and dark maintain readable radio chrome', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Radios'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Radios & Bluetooth'), findsOneWidget);
    final darkTheme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(darkTheme.brightness, Brightness.dark);
    expect(
      darkTheme.colorScheme.onSurface,
      isNot(darkTheme.colorScheme.surface),
    );

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('light').last);
    await tester.pumpAndSettle();
    final lightTheme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(lightTheme.brightness, Brightness.light);
    expect(
      lightTheme.colorScheme.onSurface,
      isNot(lightTheme.colorScheme.surface),
    );
    expect(find.text('Discover MeshCore radios'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('firmware manager opens from Radios without a device write', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MeshHubApp());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Radios'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Firmware Manager'), findsOneWidget);
    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();
    expect(find.text('Firmware Manager'), findsWidgets);
    expect(find.text('Import firmware file'), findsOneWidget);
    expect(find.text('Inspect image'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Flash firmware'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    final flash = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Flash firmware'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(flash.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
