import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firmware_hardware_catalog.dart';

/// Offline USB flashing is currently verified for Heltec V3 ESP32-S3 only.
/// Full MeshCore merged and Meshtastic factory images can be used; release
/// versions are parsed, not restricted to a fixed list.
enum FirmwareFamily { meshCore, meshtastic }

extension FirmwareFamilyLabel on FirmwareFamily {
  String get label =>
      this == FirmwareFamily.meshCore ? 'MeshCore' : 'Meshtastic';
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
  bool get supportsDirectUsb =>
      method == 'esptool' &&
      chip != null &&
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
  /// A board-specific matcher prevents cross-board firmware imports.
  /// Firmware filename matching cannot prove the publisher or chip wiring.
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
      final cleanName = filename
          .replaceAll('-merged.bin', '')
          .replaceAll('.factory.bin', '')
          .replaceAll('.uf2', '')
          .replaceAll('.zip', '');
      final releases = RegExp(
        r'[-_](v?[0-9]+(?:[.][0-9]+){1,3}(?:[._+-][A-Za-z0-9]+)*)',
      ).allMatches(cleanName).toList();
      final version = releases.isEmpty
          ? 'release file'
          : releases.last.group(1)!;
      return FirmwarePackage(
        family: family,
        role: variant.role,
        version: version,
        format: switch (variant.format) {
          'merged' =>
            board.chip == 'esp32s3'
                ? 'Merged ESP32-S3 image'
                : 'Merged ESP32 full image',
          'factory' =>
            board.chip == 'esp32s3'
                ? 'Factory ESP32-S3 image'
                : 'Factory ESP32 full image',
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
        boardId: 'meshtastic-heltec-v3',
        imageKind: 'factory',
      );
    }

    final core = RegExp(r'^heltec[-_]v3[-_](.+)-merged\.bin$').firstMatch(name);
    if (core == null) return null;
    final stem = core.group(1)!;
    final separator = RegExp(r'-v[0-9]').firstMatch(stem);
    final roleToken =
        (separator == null ? stem : stem.substring(0, separator.start))
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
  /// Checks size, a file-format header and optional independently obtained
  /// checksum. These are not code signing or complete board validation.
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
        (expectedFamily != null && expectedFamily != package.family)) {
      throw const FormatException('Firmware does not match selected board.');
    }
    final file = File(input);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < minImageSize ||
        stat.size > maxImageSize) {
      throw const FormatException(
        'Firmware file size must be 64 KiB to 16 MiB.',
      );
    }
    final handle = await file.open();
    try {
      if (!_validFirmwareHeader(package.imageKind, await handle.read(8))) {
        throw const FormatException('Unsupported firmware image header.');
      }
    } finally {
      await handle.close();
    }
    final digest = await _calculateSha256(file.path);
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final wanted = expectedSha256.trim().toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(wanted) || wanted != digest) {
        throw const FormatException('SHA-256 does not match publisher digest.');
      }
    }
    return OfflineFirmwareImage(
      path: file.absolute.path,
      sourceName: file.uri.pathSegments.last,
      sha256: digest,
      bytes: stat.size,
      package: package,
    );
  }

  static bool _validFirmwareHeader(String kind, List<int> prefix) {
    if (kind == 'merged' || kind == 'factory') {
      return prefix.length >= 8 &&
          prefix[0] == 0xe9 &&
          prefix[1] >= 1 &&
          prefix[1] <= 16;
    }
    if (kind == 'uf2') {
      return prefix.length >= 8 &&
          prefix[0] == 0x55 &&
          prefix[1] == 0x46 &&
          prefix[2] == 0x32 &&
          prefix[3] == 0x0a &&
          prefix[4] == 0x57 &&
          prefix[5] == 0x51 &&
          prefix[6] == 0x5d &&
          prefix[7] == 0x9e;
    }
    if (kind == 'dfu-zip') {
      return prefix.length >= 4 &&
          prefix[0] == 0x50 &&
          prefix[1] == 0x4b &&
          prefix[2] == 3 &&
          prefix[3] == 4;
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
  static String _cacheSuffix(FirmwarePackage package) =>
      switch (package.imageKind) {
        'uf2' => '.uf2',
        'dfu-zip' => '.zip',
        _ => '.bin',
      };

  Future<OfflineFirmwareImage> saveOffline(OfflineFirmwareImage image) async {
    final libraryFile = File(
      '$libraryPath/${image.sha256}${_cacheSuffix(image.package)}',
    );
    if (File(image.path).absolute.path == libraryFile.absolute.path) {
      return _verifyStoredImage(
        libraryFile.path,
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
    await Directory(libraryPath).create(recursive: true);
    if (File(checked.path).absolute.path != libraryFile.absolute.path) {
      await File(checked.path).copy(libraryFile.path);
    }
    final saved = await _verifyStoredImage(
      libraryFile.path,
      checked.sourceName,
      checked.sha256,
      checked.bytes,
      package: checked.package,
    );
    final manifest = File('$libraryPath/${checked.sha256}.json');
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
    final pkg = package ?? recognizePackage(sourceName);
    final file = File(path);
    final stat = await file.stat();
    if (pkg == null ||
        stat.type != FileSystemEntityType.file ||
        stat.size != expectedBytes ||
        await _calculateSha256(file.path) != checksum) {
      throw const FormatException('Stored image failed integrity check.');
    }
    final handle = await file.open();
    try {
      if (!_validFirmwareHeader(pkg.imageKind, await handle.read(8))) {
        throw const FormatException('Stored image has invalid header.');
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

  Future<List<OfflineFirmwareImage>> savedImages() async {
    final directory = Directory(libraryPath);
    if (!await directory.exists()) return [];
    final catalog = await FirmwareBoardCatalog.load();
    final images = <OfflineFirmwareImage>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final info = jsonDecode(await entity.readAsString());
        if (info is! Map<String, dynamic> ||
            !const {
              'device',
              'heltecV3',
              'heltecV3MeshCoreCompanion',
            }.contains(info['target'])) {
          continue;
        }
        final sha = info['sha256'];
        final filename = info['sourceName'];
        final size = info['bytes'];
        if (sha is! String ||
            filename is! String ||
            size is! int ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
            entity.path.split('/').last != '$sha.json') {
          continue;
        }
        final board = catalog.byId(info['boardId'] as String?);
        final pkg = recognizePackage(filename, board: board);
        if (pkg == null) continue;
        if (info['target'] == 'heltecV3MeshCoreCompanion' &&
            pkg.family != FirmwareFamily.meshCore) {
          continue;
        }
        if (info['target'] != 'heltecV3MeshCoreCompanion' &&
            (info['family'] != pkg.family.name ||
                info['role'] != pkg.role ||
                info['version'] != pkg.version ||
                info['format'] != pkg.format)) {
          continue;
        }
        if (info['target'] == 'device' &&
            (board == null ||
                info['boardId'] != pkg.boardId ||
                info['chip'] != pkg.chip ||
                info['method'] != pkg.method ||
                info['imageKind'] != pkg.imageKind)) {
          continue;
        }
        images.add(
          await _verifyStoredImage(
            '${directory.path}/$sha${_cacheSuffix(pkg)}',
            filename,
            sha,
            size,
            package: pkg,
          ),
        );
      } catch (_) {
        // Corrupt, tampered or obsolete cache entries are never offered.
      }
    }
    images.sort((a, b) => a.sourceName.compareTo(b.sourceName));
    return images;
  }

  /// Verify a known ESP32-family chip, not the board's radio/pinout.
  Future<void> checkUsb(String port, {String chip = 'esp32s3'}) async {
    if (!Platform.isLinux) {
      throw UnsupportedError('USB flashing is Linux-only.');
    }
    if (!validPort(port)) {
      throw const FormatException('Invalid USB serial port path.');
    }
    const chips = <String, String>{
      'esp32': 'ESP32',
      'esp32s2': 'ESP32-S2',
      'esp32s3': 'ESP32-S3',
      'esp32c3': 'ESP32-C3',
      'esp32c6': 'ESP32-C6',
    };
    final label = chips[chip];
    if (label == null) {
      throw const FormatException('Unverified or unsupported chip family.');
    }
    final result = await _runTool([
      '--chip',
      chip,
      '--port',
      port,
      'flash-id',
    ], const Duration(seconds: 40));
    final response = result.output.toUpperCase();
    final matches =
        response.contains('CHIP IS $label') &&
        (chip != 'esp32' || !response.contains('CHIP IS ESP32-'));
    if (result.exitCode != 0 || !matches) {
      throw StateError('USB preflight did not confirm $label.');
    }
  }

  /// Guarded one-time full ESP32 image write. UF2 and DFU are guided only.
  Future<void> flashMergedImage({
    required OfflineFirmwareImage image,
    required String port,
    required bool userConfirmed,
    bool eraseFirst = false,
    bool eraseConfirmed = false,
    bool Function()? mayWrite,
  }) async {
    if (!userConfirmed || (eraseFirst && !eraseConfirmed)) {
      throw StateError('Explicit FLASH/ERASE confirmation required.');
    }
    final board = (await FirmwareBoardCatalog.load()).byId(
      image.package.boardId,
    );
    final pkg = recognizePackage(image.sourceName, board: board);
    if (pkg == null ||
        !pkg.supportsDirectUsb ||
        pkg.boardId != image.package.boardId ||
        pkg.family != image.package.family ||
        pkg.role != image.package.role ||
        pkg.version != image.package.version ||
        pkg.format != image.package.format ||
        pkg.chip != image.package.chip) {
      throw const FormatException(
        'Firmware/board package changed or unsupported.',
      );
    }
    final file = File(image.path);
    if (!await file.exists() ||
        await file.length() != image.bytes ||
        await _calculateSha256(file.path) != image.sha256) {
      throw const FormatException('Firmware changed since inspection.');
    }
    final handle = await file.open();
    try {
      if (!_validFirmwareHeader(pkg.imageKind, await handle.read(8))) {
        throw const FormatException('Full ESP32 image header invalid.');
      }
    } finally {
      await handle.close();
    }
    await checkUsb(port, chip: pkg.chip!);
    if (mayWrite != null && !mayWrite()) {
      throw StateError('Bluetooth session became active. No write attempted.');
    }
    if (eraseFirst) {
      final result = await _runTool([
        '--chip',
        pkg.chip!,
        '--port',
        port,
        'erase-flash',
      ], const Duration(minutes: 2));
      if (result.exitCode != 0) {
        throw StateError('Full erase failed. Recover device manually.');
      }
      if (mayWrite != null && !mayWrite()) {
        throw StateError(
          'Bluetooth active after erase. No image write attempted.',
        );
      }
    }
    final written = await _runTool([
      '--chip',
      pkg.chip!,
      '--port',
      port,
      '--baud',
      '115200',
      'write-flash',
      pkg.flashOffset,
      file.absolute.path,
    ], Duration(seconds: 120 + (image.bytes ~/ 8000)));
    if (written.exitCode != 0) {
      throw StateError(
        'Flash incomplete; do not retry without inspecting device.',
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
