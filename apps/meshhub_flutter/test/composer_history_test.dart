import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_flutter/encrypted_message_repository.dart';
import 'package:meshhub_flutter/field_session.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';
import 'package:meshhub_flutter/main.dart';
import 'package:meshhub_flutter/message_history_screen.dart';

import 'channel_feed_test.dart' show openChannels;
import 'encrypted_history_test.dart' show TestHistoryKeyStore;
import 'field_session_test.dart' show FieldTransport;

// Only BLE and key custody are fake. Real composer, session, encoder, response
// parser, AES-GCM storage and archive screen run together; no send override.
void main() {
  const candidate = MeshCoreBleCandidate(
    'synthetic-composer-radio',
    'Synthetic radio',
    MeshCoreCandidateAssessment.serviceUuidKnown,
    true,
  );
  late Directory temp;
  late TestHistoryKeyStore keys;
  late EncryptedMessageRepository repository;
  late FieldTransport device;
  late MeshCoreFieldSession session;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('meshhub-composer-history-');
    keys = TestHistoryKeyStore();
    repository = EncryptedMessageRepository(
      directory: Directory('${temp.path}/vault'),
      keyStore: keys,
    );
    await repository.open();
    device = FieldTransport(candidate.id)
      ..maxChannels = 4
      ..channelNames.addAll({0: 'Public', 2: 'Trail'})
      ..channelSendReply = null;
    session = MeshCoreFieldSession(
      transportFactory: (_) => device,
      messageHistory: repository,
      responseTimeout: const Duration(seconds: 2),
    );
    await session.connect(candidate);
  });
  tearDown(() async {
    await session.disconnect();
    await session.flushHistory();
    session.dispose();
    await repository.close();
    await temp.delete(recursive: true);
  });

  Finder composer(String channel) => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Message $channel',
  );

  Future<void> mountComposer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MeshHubApp(fieldSession: session, history: repository),
    );
    await tester.pumpAndSettle();
    await openChannels(tester);
    await tester.tap(find.text('Trail'));
    await tester.pumpAndSettle();
  }

  Future<void> startSend(WidgetTester tester, String text) async {
    await tester.enterText(composer('Trail'), text);
    await tester.ensureVisible(find.text('Send'));
    // Start the callback on the real clock because it includes filesystem IO.
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    final sends = device.writes.where((f) => f.first == 3).toList();
    expect(sends, hasLength(1));
    // Firmware layout, independently asserted: command/type/actual slot (2,
    // not its list position 1), little-endian seconds and unaltered UTF-8.
    expect(sends.single.take(3), [3, 0, 2]);
    expect(utf8.decode(sends.single.sublist(7)), text);
    final f = sends.single;
    final seconds = f[3] | f[4] << 8 | f[5] << 16 | f[6] << 24;
    expect(
      (seconds - DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).abs(),
      lessThan(3),
    );
    expect(session.sending, isTrue);
    expect(session.messages, isEmpty);
    expect(repository.count, 0);
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Send'),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
  }

  Future<void> settleStorage(WidgetTester tester) async {
    // IO completes on the real event loop, while session continuations and UI
    // callbacks run on the widget clock. Alternate both; awaiting a fake-zone
    // write from runAsync would deadlock instead of testing persistence.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (!session.sending && session.historyPending == 0) break;
    }
    expect(session.sending, isFalse);
    expect(session.historyPending, 0);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(repository.close);
  }

  testWidgets(
    'real composer sends selected slot once and accepted text survives encrypted reopen',
    (tester) async {
      await mountComposer(tester);
      const text = 'Synthetic trail café 🌲';
      await startSend(tester, text);
      device.incoming.add([0x83]); // Queue notification is not a send ACK.
      await tester.pump();
      expect(session.sendCount, 0);
      device.incoming.add([0]);
      await settleStorage(tester);
      expect(session.sendCount, 1);
      expect(session.lastSendOutcome, contains('peer delivery unverified'));
      expect(
        tester.widget<TextField>(composer('Trail')).controller!.text,
        isEmpty,
      );
      expect(find.text(text), findsOneWidget);
      final entry = (await repository.entries()).single;
      expect(entry.message.protocol, MeshProtocol.meshCore);
      expect(entry.message.conversationId, 'meshcore-channel-2');
      expect(entry.conversationIdentity, startsWith('channel:2:'));
      expect(entry.conversationName, 'Trail');
      expect(entry.radioIdentity, startsWith('meshcore:01'));
      expect(
        entry.message.deliveryState,
        MessageDeliveryState.acceptedByLocalRadio,
      );
      await tester.runAsync(() async {
        final bytes = await File('${repository.directory.path}/messages.mhh')
            .readAsBytes();
        expect(utf8.decode(bytes, allowMalformed: true), isNot(contains(text)));
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await session.disconnect();
        await repository.close();
        repository = EncryptedMessageRepository(
          directory: repository.directory,
          keyStore: keys,
        );
        await repository.open();
      });
      await tester.pumpWidget(
        MaterialApp(home: MessageHistoryScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(
        find.textContaining('recipient delivery unverified'),
        findsOneWidget,
      );
      expect(find.text('Send'), findsNothing);
      expect(device.writes.where((f) => f.first == 3), hasLength(1));
      await finish(tester);
    },
  );

  for (final outcome in ['rejected', 'timeout', 'disconnect']) {
    testWidgets('composer $outcome never archives acceptance or replays', (
      tester,
    ) async {
      await mountComposer(tester);
      const text = 'Synthetic unsuccessful attempt';
      await startSend(tester, text);
      if (outcome == 'rejected') {
        device.incoming.add([1, 2]);
      } else if (outcome == 'disconnect') {
        device.drop();
      } else {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)),
        );
        await tester.pump();
      }
      await settleStorage(tester);
      expect(session.sendCount, 0);
      expect(session.messages, isEmpty);
      expect(repository.count, 0);
      if (outcome != 'disconnect') {
        expect(
          tester.widget<TextField>(composer('Trail')).controller!.text,
          text,
        );
      }
      if (outcome != 'rejected') device.incoming.add([0]); // Late ACK.
      await tester.runAsync(() async {
        await session.disconnect();
        await session.connect(candidate);
        await session.retryHistory();
        await session.flushHistory();
      });
      await tester.pumpAndSettle();
      expect(device.writes.where((f) => f.first == 3), hasLength(1));
      expect(repository.count, 0);
      await finish(tester);
    });
  }

  testWidgets(
    'late acceptance does not erase a newer draft in another channel',
    (tester) async {
      await mountComposer(tester);
      await startSend(tester, 'Synthetic pending Trail post');
      await tester.tap(find.text('Public').first);
      await tester.pumpAndSettle();
      await tester.enterText(composer('Public'), 'Synthetic new Public draft');
      device.incoming.add([0]);
      await settleStorage(tester);
      expect(
        tester.widget<TextField>(composer('Public')).controller!.text,
        'Synthetic new Public draft',
      );
      final entry = (await repository.entries()).single;
      expect(entry.conversationName, 'Trail');
      expect(entry.message.conversationId, 'meshcore-channel-2');
      await finish(tester);
    },
  );
  testWidgets('late acceptance preserves an edited draft in the same channel', (
    tester,
  ) async {
    await mountComposer(tester);
    await startSend(tester, 'Synthetic submitted text');
    await tester.enterText(composer('Trail'), 'Synthetic next draft');
    device.incoming.add([0]);
    await settleStorage(tester);
    expect(
      tester.widget<TextField>(composer('Trail')).controller!.text,
      'Synthetic next draft',
    );
    final entry = (await repository.entries()).single;
    expect(entry.message.text, 'Synthetic submitted text');
    expect(device.writes.where((f) => f.first == 3), hasLength(1));
    await finish(tester);
  });
}
