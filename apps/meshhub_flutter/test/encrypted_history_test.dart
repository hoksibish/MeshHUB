import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_flutter/encrypted_message_repository.dart';
import 'package:meshhub_flutter/history_key_store.dart';

class TestHistoryKeyStore implements HistoryKeyStore {
  List<int>? stored;
  bool locked = false, rejectWrites = false;
  int writes = 0;
  @override
  Future<SecretKey?> read() async {
    if (locked) throw const HistoryException('Synthetic locked keyring');
    return stored == null
        ? null
        : SecretKeyData(List.of(stored!), overwriteWhenDestroyed: true);
  }

  @override
  Future<void> write(SecretKey key) async {
    if (rejectWrites) {
      throw const HistoryException('Synthetic keyring write failure');
    }
    writes++;
    stored = List.of(await key.extractBytes());
  }
}

MessageHistoryEntry historyEntry(
  String id, {
  MeshProtocol protocol = MeshProtocol.meshCore,
  bool simulated = false,
  bool outgoing = false,
  String radio = 'SYNTHETIC-RADIO-IDENTITY',
}) => MessageHistoryEntry(
  recordId: id,
  radioIdentity: radio,
  conversationIdentity: 'SYNTHETIC-CHANNEL-FINGERPRINT',
  conversationName: 'PRIVATE-CHANNEL-NAME',
  recordedAt: DateTime.utc(2026, 11, 25, 12, 30),
  message: RadioMessage(
    id: 'message-$id',
    conversationId: 'channel-0',
    protocol: protocol,
    sender: 'PRIVATE-SENDER',
    text: 'PRIVATE-MESSAGE-CONTENT-$id',
    isSimulated: simulated,
    isOutgoing: outgoing,
    deliveryState: outgoing
        ? MessageDeliveryState.acceptedByLocalRadio
        : MessageDeliveryState.receivedByRadio,
  ),
);

void main() {
  late Directory temp;
  late TestHistoryKeyStore keys;
  late EncryptedMessageRepository repository;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('meshhub-encrypted-test-');
    keys = TestHistoryKeyStore();
    repository = EncryptedMessageRepository(
      directory: Directory('${temp.path}/history'),
      keyStore: keys,
    );
  });
  tearDown(() async {
    await repository.close();
    await temp.delete(recursive: true);
  });

  Future<void> reopen() async {
    final directory = repository.directory;
    await repository.close();
    repository = EncryptedMessageRepository(
      directory: directory,
      keyStore: keys,
    );
    await repository.open();
  }

  test('real AES-GCM ciphertext restores messages and contains no plaintext metadata or key', () async {
    await repository.open();
    expect(repository.ready, true);
    await repository.append(historyEntry('one', outgoing: true));
    final raw = await repository.file.readAsBytes();
    final rendered = utf8.decode(raw, allowMalformed: true);
    for (final marker in [
      'PRIVATE-MESSAGE',
      'PRIVATE-SENDER',
      'PRIVATE-CHANNEL',
      'SYNTHETIC-RADIO',
      'SYNTHETIC-CHANNEL',
      base64Encode(keys.stored!),
    ]) {
      expect(rendered, isNot(contains(marker)));
    }
    final entities = await repository.directory.list().toList();
    expect(entities.map((e) => e.path.split('/').last).toSet(), {
      'messages.mhh',
      'writer.lock',
    });
    expect((await repository.file.stat()).mode & 0x1ff, 0x180); // 0600
    expect((await repository.directory.stat()).mode & 0x1ff, 0x1c0); // 0700
    await reopen();
    expect(repository.ready, true);
    final saved = (await repository.entries()).single;
    expect(saved.message.text, 'PRIVATE-MESSAGE-CONTENT-one');
    expect(
      saved.message.deliveryState,
      MessageDeliveryState.acceptedByLocalRadio,
    );
    expect(saved.recordedAt, DateTime.utc(2026, 11, 25, 12, 30));
    expect(saved.radioIdentity, 'SYNTHETIC-RADIO-IDENTITY');
    expect(keys.writes, 1);
  });

  test('each committed snapshot uses a fresh nonce and duplicate record IDs are idempotent', () async {
    await repository.open();
    await repository.append(historyEntry('one'));
    final first = await repository.file.readAsBytes();
    await repository.append(historyEntry('one'));
    expect(await repository.file.readAsBytes(), first);
    await repository.append(historyEntry('two'));
    final second = await repository.file.readAsBytes();
    final offset = utf8.encode('MeshHubHistory/AES256GCM/1\n').length;
    expect(
      second.sublist(offset, offset + 12),
      isNot(first.sublist(offset, offset + 12)),
    );
  });

  test(
    'modified ciphertext or tag fails authentication and is never overwritten',
    () async {
      await repository.open();
      await repository.append(historyEntry('one'));
      final changed = await repository.file.readAsBytes();
      changed[changed.length - 1] ^= 1;
      await repository.file.writeAsBytes(changed);
      await reopen();
      expect(repository.ready, false);
      expect(repository.error, isNotNull);
      expect(await repository.file.readAsBytes(), changed);
      await expectLater(
        repository.append(historyEntry('two')),
        throwsA(isA<HistoryException>()),
      );
      expect(await repository.file.readAsBytes(), changed);
    },
  );

  test(
    'wrong key fails authentication without replacing existing history',
    () async {
      await repository.open();
      await repository.append(historyEntry('one'));
      final original = await repository.file.readAsBytes();
      keys.stored = List.filled(32, 0x5a);
      await reopen();
      expect(repository.ready, false);
      expect(await repository.file.readAsBytes(), original);
    },
  );

  test(
    'missing key for existing ciphertext never creates a replacement key',
    () async {
      await repository.open();
      await repository.append(historyEntry('one'));
      final original = await repository.file.readAsBytes();
      final writes = keys.writes;
      keys.stored = null;
      await reopen();
      expect(repository.ready, false);
      expect(keys.writes, writes);
      expect(await repository.file.readAsBytes(), original);
    },
  );

  test(
    'locked/unavailable keyring fails closed with no plaintext fallback',
    () async {
      keys.locked = true;
      await repository.open();
      expect(repository.ready, false);
      expect(await repository.file.exists(), false);
      await expectLater(
        repository.append(historyEntry('one')),
        throwsA(isA<HistoryException>()),
      );
      expect(await repository.file.exists(), false);
      keys.locked = false;
      await repository.open();
      expect(repository.ready, true);
    },
  );

  test('keyring refusing a new key does not create a vault', () async {
    keys.rejectWrites = true;
    await repository.open();
    expect(repository.ready, false);
    expect(await repository.file.exists(), false);
  });

  test(
    'serialized concurrent appends survive restart without lost updates',
    () async {
      await repository.open();
      await Future.wait(
        List.generate(
          24,
          (i) => repository.append(historyEntry('parallel-$i')),
        ),
      );
      await repository.flush();
      await reopen();
      expect(
        (await repository.entries()).map((e) => e.recordId).toSet(),
        List.generate(24, (i) => 'parallel-$i').toSet(),
      );
    },
  );

  test('history preserves protocol and radio scopes instead of merging matching channel IDs', () async {
    await repository.open();
    await repository.append(historyEntry('core'));
    await repository.append(historyEntry('other-radio', radio: 'OTHER-RADIO'));
    await repository.append(
      historyEntry('mt', protocol: MeshProtocol.meshtastic),
    );
    await reopen();
    expect(await repository.forProtocol(MeshProtocol.meshCore), hasLength(2));
    expect(await repository.forProtocol(MeshProtocol.meshtastic), hasLength(1));
    expect((await repository.entries()).map((e) => e.radioIdentity).toSet(), {
      'SYNTHETIC-RADIO-IDENTITY',
      'OTHER-RADIO',
    });
  });

  test(
    'a record ID collision cannot hide a different radio or protocol',
    () async {
      await repository.open();
      await repository.append(historyEntry('same-id'));
      final original = await repository.file.readAsBytes();
      await expectLater(
        repository.append(historyEntry('same-id', radio: 'OTHER-RADIO')),
        throwsA(isA<HistoryException>()),
      );
      expect(repository.count, 1);
      expect(await repository.file.readAsBytes(), original);
    },
  );

  test('simulated messages are excluded from real history', () async {
    await repository.open();
    final original = await repository.file.readAsBytes();
    await expectLater(
      repository.append(historyEntry('sample', simulated: true)),
      throwsA(isA<HistoryException>()),
    );
    expect(await repository.entries(), isEmpty);
    expect(await repository.file.readAsBytes(), original);
  });

  test(
    'retention limit reports full without silently deleting old history',
    () async {
      await repository.close();
      repository = EncryptedMessageRepository(
        directory: Directory('${temp.path}/small'),
        keyStore: keys,
        maxEntries: 2,
      );
      await repository.open();
      await repository.append(historyEntry('one'));
      await repository.append(historyEntry('two'));
      final original = await repository.file.readAsBytes();
      await expectLater(
        repository.append(historyEntry('three')),
        throwsA(isA<HistoryException>()),
      );
      expect(await repository.entries(), hasLength(2));
      expect(await repository.file.readAsBytes(), original);
    },
  );

  test(
    'malformed envelope is preserved, never treated as an empty history',
    () async {
      await repository.directory.create();
      await repository.file.writeAsBytes([1, 2, 3, 4]);
      await repository.open();
      expect(repository.ready, false);
      expect(await repository.file.readAsBytes(), [1, 2, 3, 4]);
      expect(keys.writes, 0);
    },
  );

  test(
    'symlinked history directory is rejected before touching the target',
    () async {
      final target = await Directory('${temp.path}/elsewhere').create();
      await Link(repository.directory.path).create(target.path);
      await repository.open();
      expect(repository.ready, false);
      expect(await target.list().toList(), isEmpty);
    },
  );

  test('another process holding the writer lock blocks opening', () async {
    await repository.directory.create();
    final path = '${repository.directory.path}/writer.lock';
    final process = await Process.start('python3', [
      '-c',
      'import fcntl,sys; f=open(sys.argv[1],"a"); fcntl.lockf(f,fcntl.LOCK_EX); print("locked",flush=True); sys.stdin.read(1)',
      path,
    ]);
    await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    try {
      await repository.open();
      expect(repository.ready, false);
      expect(keys.writes, 0);
    } finally {
      process.stdin.write('x');
      await process.stdin.close();
      await process.exitCode;
    }
  });
}
