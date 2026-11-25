import 'dart:convert';

import 'package:flutter/services.dart';

/// Snapshot of upstream *currently supported* targets. The JSON source is
/// shipped with MeshHub so board selection works entirely offline.
class FirmwareBoardCatalog {
  FirmwareBoardCatalog._(this.boards);

  final List<FirmwareBoard> boards;

  static Future<FirmwareBoardCatalog> load() async {
    final json = await rootBundle.loadString(
      'assets/firmware_hardware_catalog.json',
    );
    return parse(json);
  }

  static FirmwareBoardCatalog parse(String jsonText) {
    final obj = jsonDecode(jsonText);
    if (obj is! Map<String, dynamic> || obj['schema'] != 1 ||
        obj['boards'] is! List) {
      throw const FormatException('Unsupported firmware hardware catalog.');
    }
    final boards = <FirmwareBoard>[];
    for (final raw in obj['boards'] as List<dynamic>) {
      if (raw is! Map<String, dynamic>) continue;
      final board = FirmwareBoard.fromJson(raw);
      if (board != null) boards.add(board);
    }
    return FirmwareBoardCatalog._(boards);
  }

  FirmwareBoard? byId(String? id) {
    if (id == null) return null;
    for (final board in boards) {
      if (board.id == id) return board;
    }
    return null;
  }

  List<FirmwareBoard> forFamily(String family) =>
      boards.where((b) => b.family == family).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
}

class FirmwareVariantPattern {
  const FirmwareVariantPattern({
    required this.role,
    required this.pattern,
    required this.format,
  });

  final String role;
  final String pattern;
  final String format;

  static FirmwareVariantPattern? fromJson(Map<String, dynamic> obj) {
    final role = obj['role'];
    final pattern = obj['pattern'];
    final format = obj['format'];
    if (role is! String || pattern is! String || format is! String ||
        pattern.length > 320 || pattern.isEmpty ||
        !const {'merged', 'factory', 'uf2', 'dfu-zip'}.contains(format)) {
      return null;
    }
    return FirmwareVariantPattern(role: role, pattern: pattern, format: format);
  }

  RegExpMatch? match(String filename) {
    try {
      return RegExp(pattern, caseSensitive: false).firstMatch(filename);
    } on FormatException {
      return null;
    }
  }
}

class FirmwareBoard {
  const FirmwareBoard({
    required this.id,
    required this.family,
    required this.name,
    required this.architecture,
    required this.chip,
    required this.method,
    required this.patterns,
  });

  final String id;
  final String family;
  final String name;
  final String architecture;
  final String? chip;
  final String method;
  final List<FirmwareVariantPattern> patterns;

  bool get supportsUsbFlash =>
      method == 'esptool' &&
      chip != null &&
      const {'esp32', 'esp32s3', 'esp32c3', 'esp32c6', 'esp32s2'}
          .contains(chip);

  bool get offersUf2 => patterns.any((p) => p.format == 'uf2');

  static FirmwareBoard? fromJson(Map<String, dynamic> obj) {
    final id = obj['id'], family = obj['family'], name = obj['name'];
    final arch = obj['architecture'], chip = obj['chip'];
    final method = obj['method'], patterns = obj['patterns'];
    if (id is! String || family is! String || name is! String ||
        arch is! String || method is! String ||
        patterns is! List || id.length > 140 ||
        !(family == 'meshCore' || family == 'meshtastic') ||
        (chip != null && chip is! String) ||
        !(method == 'esptool' || method == 'guided')) {
      return null;
    }
    final parsed = <FirmwareVariantPattern>[];
    for (final raw in patterns) {
      if (raw is Map<String, dynamic>) {
        final variant = FirmwareVariantPattern.fromJson(raw);
        if (variant != null) parsed.add(variant);
      }
    }
    if (parsed.isEmpty) return null;
    return FirmwareBoard(
      id: id,
      family: family,
      name: name,
      architecture: arch,
      chip: chip as String?,
      method: method,
      patterns: parsed,
    );
  }

  FirmwareVariantPattern? match(String filename) {
    for (final variant in patterns) {
      if (variant.match(filename) != null) return variant;
    }
    return null;
  }
}
