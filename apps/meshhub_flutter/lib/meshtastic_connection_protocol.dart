import 'dart:convert';

/// Read-only connection subset of meshtastic/mesh.proto: ToRadio field 3,
/// FromRadio fields 3, 7, 8 and 13. Unknown/config/message fields are discarded.
/// No MeshPacket, admin command or channel key is retained or encoded here.
class MeshtasticConnectionReport {
  const MeshtasticConnectionReport({
    this.nodeNumber,
    this.firmwareVersion,
    this.hardwareModel,
    this.configCompleteId,
    this.rebooted = false,
  });

  final int? nodeNumber;
  final String? firmwareVersion;
  final int? hardwareModel;
  final int? configCompleteId;
  final bool rebooted;

  static List<int> requestConfig(int nonce) {
    if (nonce <= 0 || nonce > 0xffffffff) {
      throw ArgumentError.value(nonce, 'nonce');
    }
    final bytes = <int>[0x18]; // ToRadio.want_config_id (uint32, field 3).
    while (nonce > 127) {
      bytes.add((nonce & 127) | 128);
      nonce >>= 7;
    }
    return bytes..add(nonce);
  }

  static MeshtasticConnectionReport decode(List<int> bytes) {
    final fields = _fields(bytes);
    int? node, complete, hardware;
    String? version;
    var rebooted = false;
    for (final field in fields) {
      switch (field.id) {
        case 3:
          for (final item in _fields(field.message())) {
            if (item.id == 1) node = item.uint32();
          }
        case 7:
          complete = field.uint32();
        case 8:
          rebooted = field.uint32() != 0;
        case 13:
          for (final item in _fields(field.message())) {
            if (item.id == 1) {
              final data = item.message();
              if (data.length > 128) {
                throw const FormatException('Oversized firmware version');
              }
              version = utf8.decode(data);
            }
            if (item.id == 9) hardware = item.uint32();
          }
      }
    }
    return MeshtasticConnectionReport(
      nodeNumber: node,
      firmwareVersion: version,
      hardwareModel: hardware,
      configCompleteId: complete,
      rebooted: rebooted,
    );
  }
}

class _Field {
  const _Field(this.id, this.wire, this.value);
  final int id, wire;
  final Object value;
  int uint32() {
    if (wire != 0 ||
        value is! int ||
        (value as int) < 0 ||
        (value as int) > 0xffffffff) {
      throw const FormatException('Expected uint32');
    }
    return value as int;
  }

  List<int> message() {
    if (wire != 2) throw const FormatException('Expected message');
    return value as List<int>;
  }
}

List<_Field> _fields(List<int> bytes) {
  if (bytes.length > 512 || bytes.any((b) => b < 0 || b > 255)) {
    throw const FormatException('Invalid Meshtastic BLE frame');
  }
  var offset = 0;
  int varint() {
    var result = 0;
    // Only 32-bit values are interpreted; unknown 64-bit fields are skipped.
    for (var index = 0; index < 10; index++) {
      if (offset >= bytes.length) throw const FormatException('Short varint');
      final byte = bytes[offset++];
      if (index == 9 && byte > 1) {
        throw const FormatException('Varint overflow');
      }
      result |= (byte & 127) << (index * 7);
      if (byte < 128) return result;
    }
    throw const FormatException('Varint overflow');
  }

  List<int> take(int size) {
    if (size < 0 || size > bytes.length - offset) {
      throw const FormatException('Truncated field');
    }
    final result = bytes.sublist(offset, offset + size);
    offset += size;
    return result;
  }

  final fields = <_Field>[];
  while (offset < bytes.length) {
    final tag = varint();
    final id = tag >> 3, wire = tag & 7;
    if (id < 1 || id > 0x1fffffff) {
      throw const FormatException('Invalid protobuf field');
    }
    final Object value = switch (wire) {
      0 => varint(),
      1 => take(8),
      2 => take(varint()),
      5 => take(4),
      _ => throw const FormatException('Unsupported protobuf wire type'),
    };
    fields.add(_Field(id, wire, value));
  }
  return fields;
}
