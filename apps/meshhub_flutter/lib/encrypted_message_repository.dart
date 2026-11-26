import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:meshhub_domain/meshhub_domain.dart';

import 'history_key_store.dart';

/// Small, bounded authenticated vault. Only ciphertext ever reaches disk,
/// including temporary files. A process lock prevents stale concurrent writers.
class EncryptedMessageRepository implements MessageHistoryRepository {
  EncryptedMessageRepository({
    required this.directory,
    required this.keyStore,
    this.maxEntries = 10000,
    this.maxBytes = 16 * 1024 * 1024,
  });

  factory EncryptedMessageRepository.production() {
    final root = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'];
    if ((root == null || !root.startsWith('/')) &&
        (home == null || !home.startsWith('/'))) {
      throw const HistoryException(
        'No private application data directory is available.',
      );
    }
    return EncryptedMessageRepository(
      directory: Directory(
        '${root != null && root.startsWith('/') ? root : '$home/.local/share'}/meshhub/history',
      ),
      keyStore: const SecretServiceHistoryKeyStore(),
    );
  }

  final Directory directory;
  final HistoryKeyStore keyStore;
  final int maxEntries, maxBytes;
  static final _header = utf8.encode('MeshHubHistory/AES256GCM/1\n');
  final _cipher = AesGcm.with256bits();
  final _changes = StreamController<void>.broadcast();
  List<MessageHistoryEntry> _entries = [];
  SecretKey? _key;
  RandomAccessFile? _lock;
  bool _ready = false, _opening = false, _closing = false, _closed = false;
  Future<void> _writes = Future.value();
  String? error;
  bool get ready => _ready;
  int get count => _entries.length;
  File get file => File('${directory.path}/messages.mhh');
  @override
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_closed) _changes.add(null);
  }

  Future<void> _permissions(String path, String mode) async {
    final result = await Process.run('chmod', [mode, '--', path]);
    if (result.exitCode != 0) {
      throw const HistoryException(
        'Private history permissions could not be set.',
      );
    }
  }

  Future<void> _rejectLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const HistoryException('History paths must not be symbolic links.');
    }
  }

  Future<void> open() async {
    if (_ready || _opening || _closed || _closing) return;
    _opening = true;
    error = null;
    _changed();
    try {
      await _rejectLink(directory.path);
      await directory.create(recursive: true);
      await _permissions(directory.path, '700');
      await _rejectLink(file.path);
      final lockFile = File('${directory.path}/writer.lock');
      await _rejectLink(lockFile.path);
      _lock = await lockFile.open(mode: FileMode.append);
      await _permissions(lockFile.path, '600');
      try {
        await _lock!.lock(FileLock.exclusive);
      } catch (_) {
        throw const HistoryException(
          'Encrypted history is open in another MeshHub window.',
        );
      }
      final exists = await file.exists();
      _key = await keyStore.read();
      if (_key == null) {
        if (exists) {
          throw const HistoryException(
            'The key for existing history is missing or locked. The file was not changed.',
          );
        }
        final generated = await _cipher.newSecretKey();
        try {
          await keyStore.write(generated);
        } finally {
          generated.destroy();
        }
        _key = await keyStore.read();
        if (_key == null) {
          throw const HistoryException(
            'The history key could not be recovered from the keyring.',
          );
        }
      }
      if (exists) {
        if (await file.length() > maxBytes) {
          throw const HistoryException(
            'History exceeds the supported size. The file was not changed.',
          );
        }
        final bytes = await file.readAsBytes();
        if (bytes.length < _header.length + 28 ||
            !List.generate(
              _header.length,
              (i) => bytes[i] == _header[i],
            ).every((v) => v)) {
          throw const HistoryException(
            'History format is unsupported or damaged. The file was not changed.',
          );
        }
        final box = SecretBox.fromConcatenation(
          bytes.sublist(_header.length),
          nonceLength: 12,
          macLength: 16,
        );
        final plaintext = await _cipher.decrypt(
          box,
          secretKey: _key!,
          aad: _header,
        );
        final decoded = jsonDecode(utf8.decode(plaintext));
        if (decoded is! Map<String, dynamic> ||
            decoded['schema'] != 1 ||
            decoded['entries'] is! List) {
          throw const FormatException('Invalid history schema');
        }
        final rows = decoded['entries'] as List;
        if (rows.length > maxEntries) {
          throw const FormatException('History entry limit');
        }
        _entries = rows.map((e) => _decode(e)).toList();
        if (_entries.map((e) => e.recordId).toSet().length != _entries.length) {
          throw const FormatException('Duplicate history records');
        }
        await _permissions(file.path, '600');
      } else {
        await _persist([]);
      }
      _ready = true;
    } catch (failure) {
      _entries = [];
      error = failure is HistoryException ? failure.message : 'Encrypted history could not be opened or authenticated. Existing files were not changed.';
      await _release();
    } finally {
      _opening = false;
      _changed();
    }
  }

  static Map<String, dynamic> _encode(MessageHistoryEntry e) => {
    'recordId': e.recordId,
    'radio': e.radioIdentity,
    'conversation': e.conversationIdentity,
    'name': e.conversationName,
    'at': e.recordedAt.toUtc().toIso8601String(),
    'id': e.message.id,
    'conversationId': e.message.conversationId,
    'protocol': e.message.protocol.name,
    'sender': e.message.sender,
    'text': e.message.text,
    'outgoing': e.message.isOutgoing,
    'delivery': e.message.deliveryState.name,
  };

  static MessageHistoryEntry _decode(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid history entry');
    }
    String text(String key, int max) {
      final v = value[key];
      if (v is! String || v.length > max || (key != 'text' && v.isEmpty)) {
        throw const FormatException('Invalid history field');
      }
      return v;
    }

    if (value['outgoing'] is! bool) {
      throw const FormatException('Invalid direction');
    }
    return MessageHistoryEntry(
      recordId: text('recordId', 256),
      radioIdentity: text('radio', 256),
      conversationIdentity: text('conversation', 512),
      conversationName: text('name', 256),
      recordedAt: DateTime.parse(text('at', 64)).toUtc(),
      message: RadioMessage(
        id: text('id', 256),
        conversationId: text('conversationId', 256),
        protocol: MeshProtocol.values.byName(text('protocol', 32)),
        sender: text('sender', 256),
        text: text('text', 4096),
        isSimulated: false,
        isOutgoing: value['outgoing'] as bool,
        deliveryState: MessageDeliveryState.values.byName(text('delivery', 64)),
      ),
    );
  }

  Future<void> _persist(List<MessageHistoryEntry> entries) async {
    final plaintext = utf8.encode(
      jsonEncode({'schema': 1, 'entries': entries.map(_encode).toList()}),
    );
    if (plaintext.length + _header.length + 28 > maxBytes) {
      throw const HistoryException(
        'Encrypted history is full. New messages remain in memory; no old history was deleted.',
      );
    }
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: _key!,
      aad: _header,
    );
    final temporary = File(
      '${directory.path}/.write-${base64UrlEncode(box.nonce).replaceAll('=', '')}',
    );
    try {
      await temporary.create(exclusive: true);
      await _permissions(temporary.path, '600');
      await temporary.writeAsBytes([
        ..._header,
        ...box.concatenation(),
      ], flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> append(MessageHistoryEntry entry) {
    if (_closing || _closed) {
      return Future.error(const HistoryException('History is closed.'));
    }
    final previous = _writes;
    final operation = () async {
      await previous;
      if (!_ready) {
        throw HistoryException(error ?? 'Encrypted history is unavailable.');
      }
      if (entry.message.isSimulated) {
        throw const HistoryException(
          'Simulated messages cannot enter real history.',
        );
      }
      _decode(_encode(entry)); // Apply the same schema bounds before writing.
      final existing = _entries.where((e) => e.recordId == entry.recordId);
      if (existing.isNotEmpty) {
        final old = existing.single;
        if (old.radioIdentity != entry.radioIdentity ||
            old.conversationIdentity != entry.conversationIdentity ||
            old.message.protocol != entry.message.protocol ||
            old.message.text != entry.message.text ||
            old.message.isOutgoing != entry.message.isOutgoing ||
            old.message.deliveryState != entry.message.deliveryState) {
          throw const HistoryException(
            'History record identity collision. Existing history was not changed.',
          );
        }
        return;
      }
      if (_entries.length >= maxEntries) {
        throw const HistoryException(
          'History is full. New messages remain in memory; no old history was deleted.',
        );
      }
      final next = [..._entries, entry];
      await _persist(next);
      _entries = next;
      error = null;
      _changed();
    }();
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation.catchError((Object failure) {
      error = failure is HistoryException ? failure.message : 'Message history could not be saved. The message remains in memory.';
      _changed();
      throw HistoryException(error!);
    });
  }

  @override
  Future<List<MessageHistoryEntry>> entries() async {
    if (!_ready) {
      throw HistoryException(error ?? 'Encrypted history is unavailable.');
    }
    return List.unmodifiable(_entries);
  }

  @override
  Future<List<RadioMessage>> forProtocol(MeshProtocol protocol) async =>
      List.unmodifiable(
        (await entries())
            .where((e) => e.message.protocol == protocol)
            .map((e) => e.message),
      );

  @override
  Future<void> flush() => _writes;

  Future<void> _release() async {
    _ready = false;
    _key?.destroy();
    _key = null;
    final lock = _lock;
    _lock = null;
    if (lock != null) {
      try {
        await lock.unlock();
      } catch (_) {}
      await lock.close();
    }
  }

  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    await _writes;
    // open() can be waiting for a user keyring unlock; don't race its IO.
    while (_opening) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _release();
    _entries = [];
    _closed = true;
    await _changes.close();
  }
}
