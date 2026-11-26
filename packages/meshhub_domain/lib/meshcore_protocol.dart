import 'dart:convert';

import 'meshhub_domain.dart';

/// Companion v1.18.0 payloads only; framing/transport and command sequencing
/// belong to the caller. These bytes never constitute RF delivery evidence.
abstract final class MeshCoreCompanionCodec {
  static List<int> appStart(String appName) {
    final name = utf8.encode(appName);
    if (name.contains(0) || name.length + 8 > 176) {
      throw ArgumentError('Invalid app name');
    }
    return [1, ...List<int>.filled(7, 0), ...name];
  }

  static List<int> deviceQuery() => [22, 3];

  static List<int> getChannel(int index) {
    RangeError.checkValueInInterval(index, 0, 255, 'index');
    return [0x1f, index];
  }

  /// Discard secret bytes 34..49 without copying them into the result.
  static MeshCoreChannel parseChannelInfo(
    List<int> frame, {
    required int requestedIndex,
  }) {
    RangeError.checkValueInInterval(requestedIndex, 0, 255, 'requestedIndex');
    if (frame.length != 50 ||
        frame[0] != 0x12 ||
        frame[1] != requestedIndex ||
        frame.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Malformed CHANNEL_INFO response');
    }
    final bytes = frame.sublist(2, 34);
    final end = bytes.indexOf(0);
    // The protocol guarantees a terminator, not zero-filled tail bytes.
    // The real Heltec can leave nonzero bytes after NUL; never decode them.
    return MeshCoreChannel(
      index: requestedIndex,
      name: utf8.decode(end < 0 ? bytes : bytes.sublist(0, end)),
    );
  }

  /// Only the public identity is retained; location, node name and other
  /// SELF_INFO fields are deliberately omitted from this M1 read-only result.
  static MeshCoreSelfIdentity parseSelfInfo(List<int> frame) {
    if (frame.length < 58 ||
        frame.length > 176 ||
        frame[0] != 5 ||
        frame.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Malformed SELF_INFO response');
    }
    final key = frame.sublist(4, 36);
    if (key.every((byte) => byte == 0)) {
      throw const FormatException('Empty SELF_INFO public identity');
    }
    int little32(int offset) =>
        frame[offset] |
        frame[offset + 1] << 8 |
        frame[offset + 2] << 16 |
        frame[offset + 3] << 24;
    return MeshCoreSelfIdentity(
      key,
      MeshCoreRadioPreset(
        frequencyKHz: little32(48),
        bandwidthHz: little32(52),
        spreadingFactor: frame[56],
        codingRate: frame[57],
      ),
    );
  }

  static List<int> encodeChannelText({
    required ConversationTarget target,
    required int maxChannels,
    required int timestampSeconds,
    required String text,
  }) {
    final index = int.tryParse(target.id);
    if (target.protocol != MeshProtocol.meshCore ||
        index == null ||
        target.id != index.toString() ||
        maxChannels < 1 ||
        maxChannels > 256 ||
        index < 0 ||
        index >= maxChannels) {
      throw ArgumentError.value(
        target.id,
        'target',
        'Invalid MeshCore channel slot',
      );
    }
    return [3, 0, index, ..._timeBytes(timestampSeconds), ..._textBytes(text)];
  }

  static List<int> encodeDirectText({
    required ConversationTarget target,
    required int timestampSeconds,
    required String text,
  }) {
    if (target.protocol != MeshProtocol.meshCore ||
        !RegExp(r'^[0-9a-f]{12}$').hasMatch(target.id)) {
      throw ArgumentError.value(
        target.id,
        'target',
        'Expected MeshCore contact key prefix',
      );
    }
    final prefix = [
      for (var i = 0; i < 12; i += 2)
        int.parse(target.id.substring(i, i + 2), radix: 16),
    ];
    return [
      2,
      0,
      0,
      ..._timeBytes(timestampSeconds),
      ...prefix,
      ..._textBytes(text),
    ];
  }

  static List<int> _timeBytes(int seconds) {
    if (seconds < 0 || seconds > 0xffffffff) {
      throw RangeError.range(seconds, 0, 0xffffffff, 'timestampSeconds');
    }
    return [
      seconds & 255,
      (seconds >> 8) & 255,
      (seconds >> 16) & 255,
      (seconds >> 24) & 255,
    ];
  }

  static List<int> _textBytes(String text) {
    final bytes = utf8.encode(text);
    if (bytes.isEmpty || bytes.length > 133 || bytes.contains(0)) {
      throw ArgumentError('Invalid MeshCore text');
    }
    return bytes;
  }

  static MeshCoreLocalSendResult parseSendResponse(
    List<int> frame, {
    required bool channel,
  }) {
    if (frame.isEmpty || frame.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid send response');
    }
    if (frame[0] == 1 && frame.length == 2) {
      return MeshCoreLocalSendResult.rejectedByRadio;
    }
    if (channel && frame.length == 1 && frame[0] == 0 ||
        !channel && frame.length == 10 && frame[0] == 6 && frame[1] <= 1) {
      return MeshCoreLocalSendResult.acceptedByRadio;
    }
    throw const FormatException('Unexpected send response');
  }

  static MeshCoreIncomingText parseIncomingText(
    List<int> frame, {
    required int maxChannels,
  }) {
    if (frame.isEmpty ||
        frame.length > 176 ||
        frame.any((byte) => byte < 0 || byte > 255) ||
        maxChannels < 1 ||
        maxChannels > 256) {
      throw const FormatException('Malformed v3 text frame');
    }
    final isChannel = frame[0] == 17;
    final isDirect = frame[0] == 16;
    final typeOffset = isChannel ? 6 : 11;
    final timestampOffset = isChannel ? 7 : 12;
    if ((!isChannel && !isDirect) ||
        frame.length < timestampOffset + 4 ||
        (isChannel && frame[4] >= maxChannels)) {
      throw const FormatException('Malformed v3 text frame');
    }
    final pathLength = frame[isChannel ? 5 : 10];
    final hashSize = (pathLength >> 6) + 1;
    if (pathLength != 0xff &&
        (hashSize == 4 || (pathLength & 63) * hashSize > 64)) {
      throw const FormatException('Invalid encoded receive path');
    }
    final textType = frame[typeOffset];
    if ((isChannel && textType != 0) ||
        (isDirect && textType != 0 && textType != 2)) {
      throw const FormatException('Unsupported v3 text type');
    }
    final textOffset = timestampOffset + 4 + (textType == 2 ? 4 : 0);
    if (frame.length <= textOffset || frame.sublist(textOffset).contains(0)) {
      throw const FormatException('Truncated or invalid v3 text frame');
    }
    final timestamp =
        frame[timestampOffset] |
        frame[timestampOffset + 1] << 8 |
        frame[timestampOffset + 2] << 16 |
        frame[timestampOffset + 3] << 24;
    final snr = (frame[1] < 128 ? frame[1] : frame[1] - 256) / 4.0;
    return MeshCoreIncomingText(
      origin: isChannel
          ? MeshCoreTextOrigin.channel
          : MeshCoreTextOrigin.direct,
      channelIndex: isChannel ? frame[4] : null,
      senderKeyPrefix: isDirect
          ? frame
                .sublist(4, 10)
                .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                .join()
          : null,
      pathLength: pathLength,
      snrDb: snr,
      timestampSeconds: timestamp,
      text: utf8.decode(frame.sublist(textOffset)),
    );
  }

  static MeshCoreDeviceInfo parseDeviceInfo(List<int> frame) {
    if (frame.length < 2 || frame[0] != 13) {
      throw const FormatException('Not a device info response');
    }
    if (frame[1] < 3) {
      throw UnsupportedError('Device info before protocol v3 is unsupported');
    }
    if (frame.length < 80 ||
        frame.length > 176 ||
        frame.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Malformed device info response');
    }
    String field(int start, int end) {
      final bytes = frame.sublist(start, end);
      final terminator = bytes.indexOf(0);
      return utf8.decode(terminator < 0 ? bytes : bytes.sublist(0, terminator));
    }

    return MeshCoreDeviceInfo(
      firmwareCode: frame[1],
      maxContacts: frame[2] * 2,
      maxChannels: frame[3],
      build: field(8, 20),
      model: field(20, 60),
      version: field(60, 80),
    );
  }
}

/// Acceptance by the local firmware is not evidence of recipient delivery.
enum MeshCoreLocalSendResult { acceptedByRadio, rejectedByRadio }

/// A channel slot is not an authenticated sender identity.
enum MeshCoreTextOrigin { channel, direct }

/// Public channel metadata only. Never retain the radio's channel secret.
final class MeshCoreChannel {
  const MeshCoreChannel({required this.index, required this.name});
  final int index;
  final String name;

  @override
  String toString() => 'MeshCoreChannel($index, $name)';
}

/// Radio-reported metadata from a dequeued v3 frame, not verified RF delivery.
class MeshCoreIncomingText {
  const MeshCoreIncomingText({
    required this.origin,
    required this.channelIndex,
    required this.senderKeyPrefix,
    required this.pathLength,
    required this.snrDb,
    required this.timestampSeconds,
    required this.text,
  });

  MeshProtocol get protocol => MeshProtocol.meshCore;
  final MeshCoreTextOrigin origin;
  final int? channelIndex;

  /// Six-byte public-key prefix; not a verified full identity.
  final String? senderKeyPrefix;

  /// 0xff means direct route on receive; other values describe flood path.
  final int pathLength;
  final double snrDb;
  final int timestampSeconds;
  final String text;
}

/// Read-only radio preset snapshot; not authorization that this RF setting is legal.
final class MeshCoreRadioPreset {
  const MeshCoreRadioPreset({
    required this.frequencyKHz,
    required this.bandwidthHz,
    required this.spreadingFactor,
    required this.codingRate,
  });
  final int frequencyKHz;
  final int bandwidthHz;
  final int spreadingFactor;
  final int codingRate;
}

/// Parsed public identity, never logged; only encrypted history may retain it.
final class MeshCoreSelfIdentity {
  MeshCoreSelfIdentity(List<int> key, this.radioPreset)
    : publicKey = List<int>.unmodifiable(key);
  final List<int> publicKey;
  final MeshCoreRadioPreset radioPreset;

  @override
  String toString() => 'MeshCoreSelfIdentity([redacted])';
}

/// Public device metadata only. PIN bytes 4..7 are intentionally discarded.
class MeshCoreDeviceInfo {
  const MeshCoreDeviceInfo({
    required this.firmwareCode,
    required this.maxContacts,
    required this.maxChannels,
    required this.build,
    required this.model,
    required this.version,
  });

  final int firmwareCode;
  final int maxContacts;
  final int maxChannels;
  final String build;
  final String model;
  final String version;

  @override
  String toString() =>
      'MeshCoreDeviceInfo($firmwareCode, $maxContacts, '
      '$maxChannels, $build, $model, $version)';
}
