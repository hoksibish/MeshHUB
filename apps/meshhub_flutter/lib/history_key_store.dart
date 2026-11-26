import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dbus/dbus.dart';

class HistoryException implements Exception {
  const HistoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class HistoryKeyStore {
  Future<SecretKey?> read();
  Future<void> write(SecretKey key);
}

/// Only this app's dedicated key is requested. Never logs tool output or puts
/// the key in command arguments, files or environment variables.
class SecretServiceHistoryKeyStore implements HistoryKeyStore {
  const SecretServiceHistoryKeyStore({
    this.purpose = 'encrypted-message-history-v1',
  });
  final String purpose;
  List<String> get _attributes => [
    'application',
    'org.meshhub.MeshHub',
    'purpose',
    purpose,
  ];

  Future<void> _checkPersistentCollection() async {
    if (!Platform.isLinux) {
      throw const HistoryException(
        'Encrypted history currently requires Linux Secret Service.',
      );
    }
    final bus = DBusClient.session();
    try {
      final service = DBusRemoteObject(
        bus,
        name: 'org.freedesktop.secrets',
        path: DBusObjectPath('/org/freedesktop/secrets'),
      );
      final result = await service
          .callMethod('org.freedesktop.Secret.Service', 'ReadAlias', [
            const DBusString('default'),
          ], replySignature: DBusSignature('o'))
          .timeout(const Duration(seconds: 5));
      final path = (result.returnValues.single as DBusObjectPath).value;
      if (path == '/' || path.endsWith('/session')) {
        throw const HistoryException(
          'A persistent default keyring is required for encrypted history.',
        );
      }
    } on HistoryException {
      rethrow;
    } catch (_) {
      throw const HistoryException(
        'The Linux keyring is unavailable. History remains in memory.',
      );
    } finally {
      await bus.close();
    }
  }

  Future<(int, String)> _run(List<String> args, {String? input}) async {
    Process? process;
    try {
      process = await Process.start('secret-tool', args);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      if (input != null) process.stdin.write(input);
      await process.stdin.close();
      final code = await process.exitCode.timeout(const Duration(seconds: 45));
      final text = await output;
      await errors;
      if (text.length > 128) throw const FormatException('Invalid key length');
      return (code, text.trim());
    } catch (_) {
      process?.kill();
      throw const HistoryException(
        'Could not access the history key. Unlock the Linux keyring and retry.',
      );
    }
  }

  @override
  Future<SecretKey?> read() async {
    await _checkPersistentCollection();
    final (code, value) = await _run(['lookup', ..._attributes]);
    if (code == 1 && value.isEmpty) return null;
    if (code != 0) {
      throw const HistoryException('The history key could not be read.');
    }
    try {
      final bytes = base64Decode(value);
      if (bytes.length != 32) {
        throw const FormatException('Invalid history key');
      }
      return SecretKeyData(bytes, overwriteWhenDestroyed: true);
    } catch (_) {
      throw const HistoryException(
        'The stored history key is invalid. Existing history was not changed.',
      );
    }
  }

  @override
  Future<void> write(SecretKey key) async {
    await _checkPersistentCollection();
    final bytes = await key.extractBytes();
    if (bytes.length != 32) {
      throw ArgumentError('A 256-bit history key is required');
    }
    final (code, _) = await _run([
      'store',
      '--collection=default',
      '--label=MeshHub encrypted message history',
      ..._attributes,
    ], input: base64Encode(bytes));
    if (code != 0) {
      throw const HistoryException(
        'Could not save the history key in the Linux keyring.',
      );
    }
  }
}
