import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/main.dart';

void main() {
  testWidgets('inbox labels sample data and separates protocols', (
    tester,
  ) async {
    await tester.pumpWidget(const MeshHubApp());
    expect(find.text('MeshHub'), findsOneWidget);
    expect(find.textContaining('SIMULATED'), findsWidgets);
    expect(find.text('MeshCore example'), findsOneWidget);
    expect(find.text('Meshtastic example'), findsOneWidget);

    await tester.tap(find.text('MeshCore').last);
    await tester.pumpAndSettle();
    expect(find.text('MeshCore example'), findsOneWidget);
    expect(find.text('Meshtastic example'), findsNothing);
  });
}
