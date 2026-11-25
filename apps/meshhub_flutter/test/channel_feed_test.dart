import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_flutter/field_session.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/main.dart';
import 'package:meshhub_flutter/meshcore_ble_transport.dart';

class ChannelRadio extends MeshCoreBleTransport {
  ChannelRadio() : super(selectedId: 'fixture-radio');

  final incoming = StreamController<List<int>>.broadcast(sync: true);
  final states = StreamController<bool>.broadcast(sync: true);
  final writes = <List<int>>[];
  bool online = false;

  @override
  bool get ready => online;
  @override
  Stream<bool> get readiness => states.stream;
  @override
  Stream<List<int>> get frames => incoming.stream;

  @override
  Future<void> open() async {
    online = true;
    states.add(true);
  }

  @override
  Future<void> close() async {
    online = false;
    states.add(false);
  }

  @override
  Future<void> writeFrame(List<int> command) async {
    writes.add(List.of(command));
    if (command.first == 1) {
      final info = List<int>.filled(58, 0)..[0] = 5;
      info[4] = 1;
      info.setRange(48, 52, [189, 228, 13, 0]);
      info.setRange(52, 56, [36, 244, 0, 0]);
      info[56] = 7;
      info[57] = 5;
      incoming.add(info);
    } else if (command.first == 22) {
      final info = List<int>.filled(80, 0)..[0] = 13;
      info[1] = 14;
      info[3] = 3;
      incoming.add(info);
    } else if (command.first == 31) {
      final name = switch (command[1]) {
        0 => 'Public',
        2 => 'Trail',
        _ => '',
      };
      final data = List<int>.filled(50, 0)
        ..[0] = 18
        ..[1] = command[1];
      data.setRange(2, 2 + name.length, name.codeUnits);
      if (name.isNotEmpty) data[34] = 0x71;
      incoming.add(data);
    } else if (command.first == 3) {
      incoming.add([0]);
    }
  }

  void receive({required int channel, required String text}) {
    incoming.add([17, 4, 0, 0, channel, 0, 0, 1, 0, 0, 0, ...text.codeUnits]);
  }
}

void main() {
  const candidate = MeshCoreBleCandidate(
    'fixture-radio',
    'Synthetic radio',
    MeshCoreCandidateAssessment.serviceUuidKnown,
    true,
  );
  late ChannelRadio radio;
  late MeshCoreFieldSession session;
  setUp(() async {
    radio = ChannelRadio();
    session = MeshCoreFieldSession(transportFactory: (_) => radio);
    await session.connect(candidate);
    await session.refreshChannels();
  });
  tearDown(() async {
    await session.disconnect();
    session.dispose();
  });

  testWidgets(
    'shows only radio-configured channels, opens a live channel feed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MeshHubApp(fieldSession: session));
      await tester.pumpAndSettle();
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Trail'), findsOneWidget);
      expect(find.text('Unused'), findsNothing);
      expect(find.textContaining('0x71'), findsNothing);

      await tester.tap(find.text('Trail'));
      await tester.pumpAndSettle();
      expect(find.text('Post to Trail'), findsOneWidget);
      expect(find.text('Radio connected'), findsOneWidget);
      expect(find.textContaining('cannot verify repeater coverage'), findsOneWidget);
      expect(find.textContaining('slot 2'), findsWidgets);
      radio.receive(channel: 2, text: 'Peer hello');
      await tester.pump();
      expect(find.text('Peer hello'), findsOneWidget);
      expect(find.textContaining('sender unverified'), findsOneWidget);
      expect(find.textContaining('LIVE · received'), findsOneWidget);
    },
  );

  testWidgets('inline channel post requires a fresh destination confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MeshHubApp(fieldSession: session));
    await tester.tap(find.text('Trail'));
    await tester.pumpAndSettle();
    final send = find.text('Post once to selected channel');
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: send, matching: find.byType(FilledButton)).first,
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, 'Test post');
    final confirmation = find.textContaining('I verified RF region');
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    expect(radio.writes.where((w) => w.first == 3), isEmpty);
    await tester.ensureVisible(send);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: send, matching: find.byType(FilledButton)).first,
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(send);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      radio.writes.where((w) => w.first == 3).length,
      1,
      reason:
          'status=${session.status}, commands=${radio.writes.map((w) => w.first).toList()}',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(radio.writes.where((w) => w.first == 3).single[2], 2);
    expect(find.text('Test post'), findsOneWidget);
    expect(find.textContaining('peer delivery unverified'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: send, matching: find.byType(FilledButton)).first,
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('rejected channel text leaves the draft and reports an error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MeshHubApp(fieldSession: session));
    await tester.tap(find.text('Trail'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'é' * 67);
    final confirmation = find.textContaining('I verified RF region');
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    final send = find.text('Post once to selected channel');
    await tester.ensureVisible(send);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: send, matching: find.byType(FilledButton)).first,
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(send);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Send rejected or uncertain'), findsOneWidget);
    expect(radio.writes.where((w) => w.first == 3), isEmpty);
    expect(find.text('é' * 67), findsOneWidget);
  });
}
