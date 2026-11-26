import 'dart:io';

import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_flutter/encrypted_message_repository.dart';
import 'package:meshhub_flutter/history_key_store.dart';

/// Exercises only MeshHub's dedicated key and disposable synthetic ciphertext.
/// The key stays in the OS keyring for the actual app; no secret is printed.
Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'meshhub-keyring-probe-',
  );
  var vault = EncryptedMessageRepository(
    directory: directory,
    keyStore: const SecretServiceHistoryKeyStore(),
  );
  try {
    await vault.open();
    if (!vault.ready) {
      throw HistoryException(vault.error ?? 'Keyring unavailable');
    }
    await vault.append(
      MessageHistoryEntry(
        recordId: 'synthetic-keyring-probe',
        radioIdentity: 'synthetic-probe-radio',
        conversationIdentity: 'synthetic-probe-channel',
        conversationName: 'Synthetic probe',
        recordedAt: DateTime.utc(2026, 1, 1),
        message: const RadioMessage(
          id: 'synthetic-probe',
          conversationId: 'synthetic-probe',
          protocol: MeshProtocol.meshCore,
          sender: 'Synthetic sender',
          text: 'Disposable encrypted keyring test',
          isSimulated: false,
        ),
      ),
    );
    await vault.close();
    vault = EncryptedMessageRepository(
      directory: directory,
      keyStore: const SecretServiceHistoryKeyStore(),
    );
    await vault.open();
    if (!vault.ready ||
        (await vault.entries()).single.message.text !=
            'Disposable encrypted keyring test') {
      throw const HistoryException('Synthetic keyring round trip failed');
    }
    stdout.writeln(
      'PASS: persistent OS keyring + AES-256-GCM + restart readback. No keys or message contents printed.',
    );
  } catch (error) {
    stderr.writeln(
      error is HistoryException
          ? error.message
          : 'History keyring probe failed.',
    );
    exitCode = 1;
  } finally {
    await vault.close();
    await directory.delete(recursive: true);
  }
}
