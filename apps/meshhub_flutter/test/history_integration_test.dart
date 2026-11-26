import 'dart:async';
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

import 'encrypted_history_test.dart' show TestHistoryKeyStore, historyEntry;
import 'field_session_test.dart' show FieldTransport;

const radio = MeshCoreBleCandidate(
  'test-radio',
  'Synthetic radio',
  MeshCoreCandidateAssessment.serviceUuidKnown,
  true,
);

List<int> incoming(String text) => [
  17,
  4,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  ...utf8.encode(text),
];

void main() {
  late Directory temp;
  late TestHistoryKeyStore keys;
  late EncryptedMessageRepository repository;
  late FieldTransport device;
  late MeshCoreFieldSession session;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp(
      'meshhub-history-integration-',
    );
    keys = TestHistoryKeyStore();
    repository = EncryptedMessageRepository(
      directory: Directory('${temp.path}/vault'),
      keyStore: keys,
    );
    await repository.open();
    device = FieldTransport(radio.id);
    session = MeshCoreFieldSession(
      messageHistory: repository,
      transportFactory: (_) => device,
      responseTimeout: const Duration(milliseconds: 40),
    );
  });
  tearDown(() async {
    await session.disconnect();
    await session.flushHistory();
    session.dispose();
    await repository.close();
    await temp.delete(recursive: true);
  });

  test('live receive and accepted send are encrypted, durable and retain local-only delivery labels', () async {
    device.channelNames[0] = 'Synthetic channel';
    await session.connect(radio);
    device.incoming.add(incoming('Synthetic incoming message'));
    await session.sendChannel(
      channel: 0,
      text: 'Synthetic outgoing message',
      verified: true,
    );
    await session.flushHistory();
    expect(session.historyError, isNull);
    expect(repository.count, 2);
    final first = await repository.entries();
    expect(first.map((e) => e.message.isOutgoing), [false, true]);
    expect(
      first.last.message.deliveryState,
      MessageDeliveryState.acceptedByLocalRadio,
    );
    expect(first.first.conversationName, 'Synthetic channel');
    final dir = repository.directory;
    await repository.close();
    repository = EncryptedMessageRepository(directory: dir, keyStore: keys);
    await repository.open();
    expect((await repository.entries()).map((e) => e.message.text).toSet(), {
      'Synthetic incoming message',
      'Synthetic outgoing message',
    });
  });

  test('an uncertain send is not archived as accepted and is never automatically retried', () async {
    await session.connect(radio);
    device.channelSendReply = null;
    await expectLater(
      session.sendChannel(
        channel: 0,
        text: 'Uncertain synthetic send',
        verified: true,
      ),
      throwsA(isA<TimeoutException>()),
    );
    await session.flushHistory();
    expect(await repository.entries(), isEmpty);
    expect(device.writes.where((f) => f.first == 3), hasLength(1));
  });

  test('same frame after restart is deduplicated in history without storing channel keys', () async {
    await session.connect(radio);
    final frame = incoming('Synthetic duplicate');
    device.incoming.add(frame);
    await session.flushHistory();
    await session.disconnect();
    await session.connect(radio);
    device.incoming.add(frame);
    await session.flushHistory();
    expect(repository.count, 1);
    final entry = (await repository.entries()).single;
    expect(entry.conversationIdentity, startsWith('channel:0:'));
    expect(
      entry.conversationIdentity,
      isNot(contains(List.filled(16, 'a5').join())),
    );
  });

  test('changing channel keys separates historical conversations even at the same slot', () async {
    await session.connect(radio);
    device.incoming.add(incoming('First channel key'));
    await session.flushHistory();
    device.channelReply = (index) => [
      0x12,
      index,
      ...List.filled(32, 0),
      ...List.filled(16, 0xb6),
    ];
    await session.refreshChannels();
    device.incoming.add(incoming('Second channel key'));
    await session.flushHistory();
    final entries = await repository.entries();
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.message.conversationId).toSet(), hasLength(1));
    expect(entries.map((e) => e.conversationIdentity).toSet(), hasLength(2));
  });

  test(
    'changing radio identity separates history for matching slot names',
    () async {
      await session.connect(radio);
      device.incoming.add(incoming('Radio one'));
      await session.flushHistory();
      await session.disconnect();
      device.identityByte = 2;
      await session.connect(radio);
      device.incoming.add(incoming('Radio two'));
      await session.flushHistory();
      expect(
        (await repository.entries()).map((e) => e.radioIdentity).toSet(),
        hasLength(2),
      );
    },
  );

  test('history opening after keyring recovery retries unsaved messages without RF retransmission', () async {
    final dir = repository.directory;
    await repository.close();
    keys.locked = true;
    repository = EncryptedMessageRepository(directory: dir, keyStore: keys);
    await repository.open();
    session = MeshCoreFieldSession(
      messageHistory: repository,
      transportFactory: (_) => device,
    );
    await session.connect(radio);
    device.incoming.add(incoming('Retained while locked'));
    await session.flushHistory();
    expect(session.unsavedHistoryCount, 1);
    expect(session.historyError, isNotNull);
    final commands = device.writes.length;
    keys.locked = false;
    await repository.open();
    await session.retryHistory();
    expect(session.unsavedHistoryCount, 0);
    expect(session.historyError, isNull);
    expect(repository.count, 1);
    expect(device.writes.length, commands);
  });

  testWidgets(
    'offline history searches saved content and keeps delivery evidence visible',
    (tester) async {
      await tester.runAsync(() async {
        await repository.append(historyEntry('alpha', outgoing: true));
        await repository.append(
          historyEntry('beta', protocol: MeshProtocol.meshtastic),
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: MessageHistoryScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE-MESSAGE-CONTENT-alpha'), findsOneWidget);
      expect(
        find.textContaining('recipient delivery unverified'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('history-search')), 'alpha');
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE-MESSAGE-CONTENT-alpha'), findsOneWidget);
      expect(find.text('PRIVATE-MESSAGE-CONTENT-beta'), findsNothing);
      expect(find.text('Send'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repository.close);
    },
  );

  testWidgets(
    'an unavailable vault is prominently reported without opening a radio',
    (tester) async {
      await tester.runAsync(() async {
        await repository.close();
        keys.locked = true;
        repository = EncryptedMessageRepository(
          directory: Directory('${temp.path}/locked'),
          keyStore: keys,
        );
        await repository.open();
      });
      await tester.pumpWidget(
        MeshHubApp(fieldSession: session, history: repository),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('History needs attention'), findsOneWidget);
      expect(device.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repository.close);
    },
  );

  testWidgets(
    'the app history button opens the archive without a radio connection',
    (tester) async {
      await tester.pumpWidget(
        MeshHubApp(fieldSession: session, history: repository),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Message history'));
      await tester.pumpAndSettle();
      expect(find.text('Encrypted history'), findsOneWidget);
      expect(find.text('No saved messages yet.'), findsOneWidget);
      expect(device.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(repository.close);
    },
  );
}
