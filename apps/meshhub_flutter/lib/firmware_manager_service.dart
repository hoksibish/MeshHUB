import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firmware_hardware_catalog.dart';

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
    this.boardId = 'meshcore-heltec-v3',
    this.chip = 'esp32s3',
    this.method = 'esptool',
    this.imageKind = 'merged',
  });

  final FirmwareFamily family;
  final String role;
  final String version;
  final String format;
  final String boardId;
  final String? chip;
  final String method;
  final String imageKind;

  bool get supportsDirectUsb => method == 'esptool' && chip != null &&
      (imageKind == 'merged' || imageKind == 'factory');

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

  /// Match only supported Heltec V3 firmware formats. The filename itself is
  /// NOT proof of authenticity or of the board/role encoded in the image.
  static FirmwarePackage? recognizePackage(
    String filename, {
    FirmwareBoard? board,
  }) {
    if (board != null) {
      final variant = board.match(filename);
      if (variant == null) return null;
      final family = board.family == 'meshCore'
          ? FirmwareFamily.meshCore
          : FirmwareFamily.meshtastic;
      final versionMatch = RegExp(
        r'v?\d+(?:[._-]\d+)*(?:[._+-][a-zA-Z0-9]+)*',
      ).firstMatch(filename);
      final version = versionMatch?.group(0) ?? 'release file';
      return FirmwarePackage(
        family: family,
        role: variant.role,
        version: version,
        format: switch (variant.format) {
          'merged' => 'Merged ESP32 full image',
          'factory' => 'Factory ESP32 full image',
          'uf2' => 'UF2 bootloader image',
          _ => 'nRF52 DFU archive',
        },
        boardId: board.id,
        chip: board.chip,
        method: board.method,
        imageKind: variant.format,
      );
    }

    final name = filename.toLowerCase();
    final meshtastic = RegExp(
      r'^firmware[-_]heltec[-_]v3[-_](.+)\.factory\.bin$',
    ).firstMatch(name);
    if (meshtastic != null) {
      final version = meshtastic.group(1)!;
      if (!RegExp(r'^[a-z0-9][a-z0-9._+-]{0,95}$').hasMatch(version)) {
        return null;
      }
      return FirmwarePackage(
        family: FirmwareFamily.meshtastic,
        role: 'Meshtastic node',
        version: version,
        format: 'Factory ESP32-S3 image',
      );
    }

    final core = RegExp(
      r'^heltec[-_]v3[-_](.+)-merged\.bin$',
    ).firstMatch(name);
    if (core == null) return null;
    final stem = core.group(1)!;
    final separator = RegExp(r'-v[0-9]').firstMatch(stem);
    final roleToken = (separator == null
            ? stem
            : stem.substring(0, separator.start))
        .replaceAll('-', '_');
    final version = separator == null
        ? 'unspecified'
        : stem.substring(separator.start + 1);
    if (!RegExp(r'^[a-z0-9][a-z0-9._+-]{0,95}$').hasMatch(version)) {
      return null;
    }
    const roles = <String, String>{
      'companion_radio_ble': 'Companion BLE',
      'companion_radio_usb': 'Companion USB',
      'companion_radio_wifi': 'Companion Wi-Fi',
      'companion_ble': 'Companion BLE',
      'companion_usb': 'Companion USB',
      'repeater': 'Repeater',
      'room_server': 'Room Server',
      'roomserver': 'Room Server',
      'sensor': 'Sensor',
    };
    final role = roles[roleToken];
    if (role == null) return null;
    return FirmwarePackage(
      family: FirmwareFamily.meshCore,
      role: role,
      version: version,
      format: 'Merged ESP32-S3 image',
    );
  }

  /// Filename matching is only a first guard, not proof of publisher origin.
  /// A local SHA256 is an integrity fingerprint, NOT an authenticity signature.
  Future<OfflineFirmwareImage> inspectFile(
    String path, {
    String? expectedSha256,
    FirmwareFamily? expectedFamily,
    FirmwareBoard? board,
  }) async {
    final input = path.trim();
    final package = input.isEmpty
        ? null
        : recognizePackage(input.split('/').last, board: board);
    if (package == null ||
        (expectedFamily != null && package.family != expectedFamily)) {
      throw const FormatException(
        'Choose a matching Heltec V3 MeshCore -merged.bin or '
        'Meshtastic .factory.bin for the selected firmware family.',
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
    // These checks are structural, not cryptographic signatures or proof
    // that an image matches the connected board's wiring or bootloader.
    if (!_validFirmwareHeader(package.imageKind, prefix)) {
      throw FormatException(
        'Invalid ${package.imageKind.toUpperCase()} firmware header.',
      );
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
      package: package,
    );
  }

  static bool _validFirmwareHeader(String kind, List<int> prefix) {
    if (kind == 'merged' || kind == 'factory') {
      return prefix.length >= 8 && prefix[0] == 0xe9 &&
          prefix[1] >= 1 && prefix[1] <= 16;
    }
    if (kind == 'uf2') {
      return prefix.length >= 8 &&
          prefix[0] == 0x55 && prefix[1] == 0x46 &&
          prefix[2] == 0x32 && prefix[3] == 0x0a &&
          prefix[4] == 0x57 && prefix[5] == 0x51 &&
          prefix[6] == 0x5d && prefix[7] == 0x9e;
    }
    if (kind == 'dfu-zip') {
      return prefix.length >= 4 && prefix[0] == 0x50 &&
          prefix[1] == 0x4b && prefix[2] == 3 && prefix[3] == 4;
    }
    return false;
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
    final cachedPath = '$libraryPath/${image.sha256}.bin';
    // Selecting an already-cached image is idempotent. Cache entries are
    // digest named, so they cannot pass a filename-based importer again.
    if (File(image.path).absolute.path == File(cachedPath).absolute.path) {
      return _verifyStoredImage(
        cachedPath,
        image.sourceName,
        image.sha256,
        image.bytes,
        package: image.package,
      );
    }
    final board = (await FirmwareBoardCatalog.load()).byId(
      image.package.boardId,
    );
    final checked = await inspectFile(
      image.path,
      expectedSha256: image.sha256,
      expectedFamily: image.package.family,
      board: board,
    );
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
      package: checked.package,
    );
    final manifest = File('${directory.path}/${checked.sha256}.json');
    await manifest.writeAsString(
      jsonEncode({
        'target': 'device',
        'boardId': checked.package.boardId,
        'chip': checked.package.chip,
        'method': checked.package.method,
        'imageKind': checked.package.imageKind,
        'family': checked.package.family.name,
        'role': checked.package.role,
        'version': checked.package.version,
        'format': checked.package.format,
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
    int expectedBytes, {
    FirmwarePackage? package,
  }) async {
    final file = File(path);
    final stat = await file.stat();
    final pkg = package ?? recognizePackage(sourceName);
    if (pkg == null ||
        stat.type != FileSystemEntityType.file ||
        stat.size != expectedBytes ||
        await _calculateSha256(path) != checksum) {
      throw const FormatException(
        'Stored image failed integrity verification.',
      );
    }
    final handle = await file.open();
    try {
      if (!_validFirmwareHeader(pkg.imageKind, await handle.read(8))) {
        throw const FormatException(
          'Stored image header failed integrity verification.',
        );
      }
    } finally {
      await handle.close();
    }
    return OfflineFirmwareImage(
      path: file.absolute.path,
      sourceName: sourceName,
      sha256: checksum,
      bytes: expectedBytes,
      package: pkg,
    );
  }

  /// Integrity check every cached image before exposing it in the UI.
  Future<List<OfflineFirmwareImage>> savedImages() async {
    final directory = Directory(libraryPath);
    if (!await directory.exists()) return [];
    final catalog = await FirmwareBoardCatalog.load();
    final results = <OfflineFirmwareImage>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final manifest = jsonDecode(await entity.readAsString());
        if (manifest is! Map<String, dynamic> ||
            !const {'device', 'heltecV3', 'heltecV3MeshCoreCompanion'}
                .contains(manifest['target'])) {
          continue;
        }
        final sha = manifest['sha256'];
        final name = manifest['sourceName'];
        final bytes = manifest['bytes'];
        if (sha is! String ||
            name is! String ||
            bytes is! int ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
            entity.path.split('/').last != '$sha.json') {
          continue;
        }
        final board = catalog.byId(manifest['boardId'] as String?);
        final package = recognizePackage(name, board: board);
        if (package == null) continue;
        if (manifest['target'] == 'heltecV3MeshCoreCompanion' &&
            package.family != FirmwareFamily.meshCore) {
          continue;
        }
        if (manifest['target'] != 'heltecV3MeshCoreCompanion' &&
            (manifest['family'] != package.family.name ||
                manifest['role'] != package.role ||
                manifest['version'] != package.version ||
                manifest['format'] != package.format)) {
          continue;
        }
        if (manifest['target'] == 'device' &&
            (board == null ||
                manifest['boardId'] != package.boardId ||
                manifest['method'] != package.method ||
                manifest['chip'] != package.chip ||
                manifest['imageKind'] != package.imageKind)) {
          continue;
        }
        results.add(
          await _verifyStoredImage(
            '${directory.path}/$sha.bin',
            name,
            sha,
            bytes,
            package: package,
          ),
        );
      } catch (_) {
        // Bad/tampered cache entry is never offered for flashing.
      }
    }
    results.sort((a, b) => a.sourceName.compareTo(b.sourceName));
    return results;
  }

  /// USB chip-ID preflight validates the MCU family, not the board's pinout.
  /// A board's identity is still explicitly verified by its owner.
  Future<void> checkUsb(
    String port, {
    String chip = 'esp32s3',
  }) async {
    if (!Platform.isLinux) {
      throw UnsupportedError('USB flashing is currently Linux-only.');
    }
    if (!validPort(port)) {
      throw const FormatException(
        'Use /dev/ttyACM*, /dev/ttyUSB* or /dev/serial/by-id/…',
      );
    }
    if (!const {'esp32', 'esp32s3', 'esp32s2', 'esp32c3', 'esp32c6'}
        .contains(chip)) {
      throw const FormatException('Unsupported or unverified ESP32 chip.');
    }
    final result = await _runTool([
      '--chip', chip, '--port', port, 'flash-id',
    ], const Duration(seconds: 40));
    final display = switch (chip) {
      'esp32' => 'ESP32',
      'esp32s2' => 'ESP32-S2',
      'esp32s3' => 'ESP32-S3',
      'esp32c3' => 'ESP32-C3',
      'esp32c6' => 'ESP32-C6',
      _ => '',
    };
    final output = result.output.toUpperCase();
    final match = chip == 'esp32'
        ? RegExp(r'\bESP32\b(?![-A-Z0-9])').hasMatch(output)
        : output.contains(display);
    if (result.exitCode != 0 || !match) {
      throw StateError(
        'USB preflight did not confirm $display. No flash attempted.',
      );
    }
  }

  /// A full-image USB write is always explicit. A whole-chip erase is a
  /// separate, destructive opt-in that deletes identities and stored keys.
  /// Neither write nor erase is replayed after an interrupted operation.
  Future<void> flashMergedImage({
    required OfflineFirmwareImage image,
    required String port,
    required bool userConfirmed,
    bool eraseFirst = false,
    bool eraseConfirmed = false,
    bool Function()? mayWrite,
  }) async {
    if (!userConfirmed || (eraseFirst && !eraseConfirmed)) {
      throw StateError(
        'Explicit flash and optional full-erase approvals are required.',
      );
    }
    final catalog = await FirmwareBoardCatalog.load();
    final board = catalog.byId(image.package.boardId);
    final package = recognizePackage(image.sourceName, board: board);
    if (package == null ||
        !package.supportsDirectUsb ||
        package.boardId != image.package.boardId ||
        package.family != image.package.family ||
        package.role != image.package.role ||
        package.version != image.package.version ||
        package.format != image.package.format ||
        package.chip != image.package.chip) {
      throw const FormatException('Unsupported or changed firmware target.');
    }
    final file = File(image.path);
    if (!await file.exists() ||
        (await file.length()) != image.bytes ||
        await _calculateSha256(file.path) != image.sha256) {
      throw const FormatException('Firmware file changed since inspection.');
    }
    final handle = await file.open();
    try {
      final prefix = await handle.read(8);
      if (!_validFirmwareHeader(package.imageKind, prefix)) {
        throw const FormatException('Invalid ESP32 full-image header.');
      }
    } finally {
      await handle.close();
    }
    await checkUsb(port, chip: package.chip!);
    if (mayWrite != null && !mayWrite()) {
      throw StateError('Bluetooth session became active. No flash attempted.');
    }
    if (eraseFirst) {
      final erased = await _runTool([
        '--chip',
        package.chip!,
        '--port',
        port,
        'erase-flash',
      ], const Duration(minutes: 2));
      if (erased.exitCode != 0) {
        throw StateError(
          'Full erase failed. Inspect the device before recovery.',
        );
      }
      if (mayWrite != null && !mayWrite()) {
        throw StateError(
          'Bluetooth session became active after erase. '
          'No firmware write attempted; recover the node manually.',
        );
      }
    }
    final result = await _runTool([
      '--chip',
      'esp32s3',
      '--port',
      port,
      '--baud',
      '115200',
      'write-flash',
      package.flashOffset,
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
