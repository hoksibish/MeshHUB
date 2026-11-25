import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Offline USB flashing is currently verified for Heltec V3 ESP32-S3 only.
/// Full MeshCore merged and Meshtastic factory images can be used; release
/// versions are parsed, not restricted to a fixed list.
enum FirmwareFamily { meshCore, meshtastic }

extension FirmwareFamilyLabel on FirmwareFamily {
  String get label => this == FirmwareFamily.meshCore ? 'MeshCore' : 'Meshtastic';
}

class FirmwarePackage {
  const FirmwarePackage({
    required this.family,
    required this.role,
    required this.version,
    required this.format,
  });

  final FirmwareFamily family;
  final String role;
  final String version;
  final String format;

  String get flashOffset => '0x0';
  String get displayName => '${family.label} · $role · $version';
}

class OfflineFirmwareImage {
  const OfflineFirmwareImage({
    required this.path,
    required this.sourceName,
    required this.sha256,
    required this.bytes,
    required this.package,
  });

  final String path;
  final String sourceName;
  final String sha256;
  final int bytes;
  final FirmwarePackage package;
}

class FirmwareToolResult {
  const FirmwareToolResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

typedef FirmwareToolRunner = Future<FirmwareToolResult> Function(
  List<String> arguments,
  Duration limit,
);

/// No web access, automatic downloads or device writes occur on construction.
/// The default runner invokes esptool using an argument array (never a shell).
class FirmwareManagerService {
  FirmwareManagerService({String? libraryPath, FirmwareToolRunner? runTool})
    : libraryPath = libraryPath ?? _defaultLibraryPath(),
      _runTool = runTool ?? _runEsptool;

  static const maxImageSize = 16 * 1024 * 1024;
  static const minImageSize = 64 * 1024;

  final String libraryPath;
  final FirmwareToolRunner _runTool;

  static String _defaultLibraryPath() {
    final home = Platform.environment['HOME'];
    if (!Platform.isLinux || home == null || home.isEmpty) {
      throw UnsupportedError('Offline firmware manager requires Linux');
    }
    return '$home/.local/share/meshhub/firmware';
  }

  static bool validPort(String port) {
    if (RegExp(r'^/dev/tty(USB|ACM)[0-9]+$').hasMatch(port)) return true;
    return RegExp(r'^/dev/serial/by-id/[A-Za-z0-9._:+-]+$').hasMatch(port);
  }

  static bool _firmwareNameMatches(String name) {
    final normalized = name.toLowerCase();
    return RegExp(r'^.*heltec[_-]?v3.*companion.*merged\.bin$')
        .hasMatch(normalized);
  }

  /// Filename matching is only a first guard, not proof of publisher origin.
  /// A local SHA256 is an integrity fingerprint, NOT an authenticity signature.
  Future<OfflineFirmwareImage> inspectFile(
    String path, {
    String? expectedSha256,
  }) async {
    final input = path.trim();
    if (input.isEmpty || !_firmwareNameMatches(input.split('/').last)) {
      throw const FormatException(
        'Choose a Heltec V3 MeshCore Companion -merged.bin firmware image.',
      );
    }
    final file = File(input);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < minImageSize ||
        stat.size > maxImageSize) {
      throw const FormatException(
        'Firmware must be a regular .bin image between 64 KiB and 16 MiB.',
      );
    }
    final handle = await file.open();
    late final List<int> prefix;
    try {
      prefix = await handle.read(8);
    } finally {
      await handle.close();
    }
    // ESP32-S3 image format header. This is NOT a cryptographic signature or
    // complete validation of the firmware's declared board or application.
    if (prefix.length < 8 ||
        prefix[0] != 0xe9 ||
        prefix[1] < 1 ||
        prefix[1] > 16) {
      throw const FormatException('No valid ESP32 image header at offset 0.');
    }
    final checksum = await _calculateSha256(file.path);
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final wanted = expectedSha256.trim().toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(wanted) || wanted != checksum) {
        throw const FormatException(
          'SHA-256 does not match the independently provided checksum.',
        );
      }
    }
    return OfflineFirmwareImage(
      path: file.absolute.path,
      sourceName: file.uri.pathSegments.last,
      sha256: checksum,
      bytes: stat.size,
    );
  }

  Future<String> _calculateSha256(String path) async {
    final result = await Process.run('sha256sum', ['--', path]);
    if (result.exitCode != 0) {
      throw StateError('Unable to calculate SHA-256 for this firmware file.');
    }
    final match = RegExp(r'^[0-9a-fA-F]{64}')
        .firstMatch(result.stdout.toString());
    if (match == null) throw StateError('SHA-256 tool returned no digest.');
    return match.group(0)!.toLowerCase();
  }

  /// Copies firmware bytes only; no radio keys, identity or message contents.
  Future<OfflineFirmwareImage> saveOffline(OfflineFirmwareImage image) async {
    final checked = await inspectFile(image.path, expectedSha256: image.sha256);
    final directory = Directory(libraryPath);
    await directory.create(recursive: true);
    final filePath = '${directory.path}/${checked.sha256}.bin';
    if (File(checked.path).absolute.path != File(filePath).absolute.path) {
      await File(checked.path).copy(filePath);
    }
    final saved = await _verifyStoredImage(
      filePath,
      checked.sourceName,
      checked.sha256,
      checked.bytes,
    );
    final manifest = File('${directory.path}/${checked.sha256}.json');
    await manifest.writeAsString(
      jsonEncode({
        'target': FirmwareTarget.heltecV3MeshCoreCompanion.name,
        'sourceName': checked.sourceName,
        'sha256': checked.sha256,
        'bytes': checked.bytes,
      }),
      flush: true,
    );
    return saved;
  }

  Future<OfflineFirmwareImage> _verifyStoredImage(
    String path,
    String sourceName,
    String checksum,
    int expectedBytes,
  ) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != expectedBytes ||
        await _calculateSha256(path) != checksum) {
      throw const FormatException(
        'Stored image failed integrity verification.',
      );
    }
    return OfflineFirmwareImage(
      path: file.absolute.path,
      sourceName: sourceName,
      sha256: checksum,
      bytes: expectedBytes,
    );
  }

  /// Integrity check every cached image before exposing it in the UI.
  Future<List<OfflineFirmwareImage>> savedImages() async {
    final directory = Directory(libraryPath);
    if (!await directory.exists()) return [];
    final results = <OfflineFirmwareImage>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final manifest = jsonDecode(await entity.readAsString());
        if (manifest is! Map<String, dynamic> ||
            manifest['target'] !=
                FirmwareTarget.heltecV3MeshCoreCompanion.name) {
          continue;
        }
        final sha = manifest['sha256'];
        final name = manifest['sourceName'];
        final bytes = manifest['bytes'];
        if (sha is! String ||
            name is! String ||
            bytes is! int ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
            !_firmwareNameMatches(name) ||
            entity.path.split('/').last != '$sha.json') {
          continue;
        }
        results.add(
          await _verifyStoredImage(
            '${directory.path}/$sha.bin',
            name,
            sha,
            bytes,
          ),
        );
      } catch (_) {
        // A broken or tampered offline package is never offered for flashing.
      }
    }
    results.sort((a, b) => a.sourceName.compareTo(b.sourceName));
    return results;
  }

  /// Read-only connection proof against an actual ESP32-S3 over USB.
  Future<void> checkUsb(String port) async {
    if (!Platform.isLinux) {
      throw UnsupportedError('USB flashing is currently Linux-only.');
    }
    if (!validPort(port)) {
      throw const FormatException(
        'Use /dev/ttyACM*, /dev/ttyUSB* or /dev/serial/by-id/…',
      );
    }
    final result = await _runTool([
      '--chip',
      'esp32s3',
      '--port',
      port,
      'flash-id',
    ], const Duration(seconds: 40));
    if (result.exitCode != 0 ||
        !result.output.toUpperCase().contains('ESP32-S3')) {
      throw StateError(
        'USB preflight did not confirm an ESP32-S3. No flash attempted.',
      );
    }
  }

  /// Destructive device write: caller must obtain explicit user confirmation.
  /// Rechecks the selected image and the USB chip immediately before writing.
  /// Deliberately never runs erase-flash, changes RF settings, or auto-retries.
  Future<void> flashMergedImage({
    required OfflineFirmwareImage image,
    required String port,
    required bool userConfirmed,
    bool Function()? mayWrite,
  }) async {
    if (!userConfirmed) {
      throw StateError('Explicit firmware flashing confirmation is required.');
    }
    // Offline cache uses digest-named files; imported files use board names.
    // Revalidate the expected digest and, for cached images, the manifest.
    final file = File(image.path);
    if (!await file.exists() ||
        (await file.length()) != image.bytes ||
        await _calculateSha256(file.path) != image.sha256) {
      throw const FormatException('Firmware file changed since inspection.');
    }
    if (!_firmwareNameMatches(image.sourceName)) {
      throw const FormatException('Unsupported firmware filename or target.');
    }
    final handle = await file.open();
    try {
      final prefix = await handle.read(2);
      if (prefix.length < 2 ||
          prefix[0] != 0xe9 ||
          prefix[1] < 1 ||
          prefix[1] > 16) {
        throw const FormatException('Invalid ESP32 image header.');
      }
    } finally {
      await handle.close();
    }
    await checkUsb(port);
    if (mayWrite != null && !mayWrite()) {
      throw StateError('Bluetooth session became active. No flash attempted.');
    }
    final result = await _runTool([
      '--chip',
      'esp32s3',
      '--port',
      port,
      '--baud',
      '115200',
      'write-flash',
      '0x0',
      file.absolute.path,
    ], Duration(seconds: 120 + (image.bytes ~/ 8000)));
    if (result.exitCode != 0) {
      throw StateError(
        'Flashing did not complete (exit ${result.exitCode}). '
        'Do not assume the device is usable; inspect it before retrying.',
      );
    }
  }

  static Future<FirmwareToolResult> _runEsptool(
    List<String> arguments,
    Duration limit,
  ) async {
    Process process;
    try {
      process = await Process.start('esptool', arguments);
    } on ProcessException {
      throw StateError(
        'esptool is unavailable. Install it locally before flashing.',
      );
    }
    process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    int code;
    try {
      code = await process.exitCode.timeout(
        limit,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Firmware tool timed out.');
        },
      );
    } finally {
      if (process.kill(ProcessSignal.sigterm)) {
        // Ignore if process already exited; no second write attempt.
      }
    }
    final text = (await output) + (await errors);
    return FirmwareToolResult(code, text);
  }
}
