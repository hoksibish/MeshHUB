import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
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
      await tester.tap(find.text('Radios'));
      await tester.pumpAndSettle();
      expect(find.text('Discover MeshCore radios'), findsOneWidget);
      expect(find.text('No radio selected'), findsOneWidget);
      expect(find.text('Direct contact'), findsOneWidget);
      expect(find.textContaining('SIMULATED DATA'), findsNothing);
    },
  );

  testWidgets('inbox labels sample data and separates protocols', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    expect(find.text('MeshHub'), findsOneWidget);
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
