import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_domain/meshhub_domain.dart';
import 'package:meshhub_domain/meshcore_protocol.dart';

void main() {
  test('APP_START reserves seven bytes and DEVICE_QUERY negotiates v3', () {
    expect(MeshCoreCompanionCodec.appStart('MeshHub'), [
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...utf8.encode('MeshHub'),
    ]);
    expect(MeshCoreCompanionCodec.deviceQuery(), [22, 3]);
  });

  test('SELF_INFO parses full public identity without exposing it in logs', () {
    final key = List<int>.generate(32, (index) => index + 1);
    final frame = [5, 1, 2, 3, ...key, ...List<int>.filled(22, 0)];
    final identity = MeshCoreCompanionCodec.parseSelfInfo(frame);
    expect(identity.publicKey, key);
    expect(identity.toString(), isNot(contains('01020304')));
    expect(() => identity.publicKey[0] = 42, throwsUnsupportedError);
  });

  test('SELF_INFO reads actual RF preset without writing configuration', () {
    final frame = [
      5, 1, 2, 3,
      ...List<int>.filled(32, 1),
      ...List<int>.filled(12, 0),
      189, 228, 13, 0, // 910525 kHz
      36, 244, 0, 0, // 62500 Hz
      7, 5,
    ];
    final identity = MeshCoreCompanionCodec.parseSelfInfo(frame);
    expect(identity.radioPreset.frequencyKHz, 910525);
    expect(identity.radioPreset.bandwidthHz, 62500);
    expect(identity.radioPreset.spreadingFactor, 7);
    expect(identity.radioPreset.codingRate, 5);
  });

  test('SELF_INFO rejects truncated or zero public identity', () {
    expect(
      () => MeshCoreCompanionCodec.parseSelfInfo([5, 1]),
      throwsFormatException,
    );
    expect(
      () =>
          MeshCoreCompanionCodec.parseSelfInfo([5, ...List<int>.filled(57, 0)]),
      throwsFormatException,
    );
  });

  test('device info exposes public fields only, never BLE PIN', () {
    final frame = [
      13,
      14,
      5,
      8,
      0x12,
      0x34,
      0x56,
      0x78,
      ..._fixed('2026-11-18', 12),
      ..._fixed('Heltec V3', 40),
      ..._fixed('1.18.0', 20),
      1,
      2,
    ];
    final info = MeshCoreCompanionCodec.parseDeviceInfo(frame);
    expect(info.firmwareCode, 14);
    expect(info.maxContacts, 10);
    expect(info.maxChannels, 8);
    expect(info.build, '2026-11-18');
    expect(info.model, 'Heltec V3');
    expect(info.version, '1.18.0');
    expect(info.toString(), isNot(contains('78563412')));
    expect(info.toString(), isNot(contains('12345678')));
  });

  test('device info rejects truncated and unsupported firmware frames', () {
    expect(
      () => MeshCoreCompanionCodec.parseDeviceInfo([13, 3]),
      throwsFormatException,
    );
    expect(
      () => MeshCoreCompanionCodec.parseDeviceInfo([
        13,
        3,
        ...List.filled(77, 0),
      ]),
      throwsFormatException,
    );
    expect(
      () => MeshCoreCompanionCodec.parseDeviceInfo([13, 2]),
      throwsUnsupportedError,
    );
    expect(
      () => MeshCoreCompanionCodec.parseDeviceInfo([
        13,
        3,
        ...List.filled(175, 0),
      ]),
      throwsFormatException,
    );
  });

  test(
    'v3 channel frame retains radio provenance, SNR and slot not sender',
    () {
      final msg = MeshCoreCompanionCodec.parseIncomingText([
        17,
        0xfc,
        99,
        88,
        2,
        0xff,
        0,
        0xd2,
        0x02,
        0x96,
        0x49,
        ...utf8.encode('Hi'),
      ], maxChannels: 8);
      expect(msg.protocol, MeshProtocol.meshCore);
      expect(msg.origin, MeshCoreTextOrigin.channel);
      expect(msg.channelIndex, 2);
      expect(msg.senderKeyPrefix, isNull);
      expect(msg.pathLength, 0xff);
      expect(msg.snrDb, -1.0);
      expect(msg.timestampSeconds, 1234567890);
      expect(msg.text, 'Hi');
    },
  );
  test('v3 direct signed text skips signature and retains six-byte prefix', () {
    final msg = MeshCoreCompanionCodec.parseIncomingText([
      16,
      4,
      1,
      2,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
      1,
      2,
      0xd2,
      0x02,
      0x96,
      0x49,
      9,
      8,
      7,
      6,
      ...utf8.encode('Direct'),
    ], maxChannels: 8);
    expect(msg.origin, MeshCoreTextOrigin.direct);
    expect(msg.channelIndex, isNull);
    expect(msg.senderKeyPrefix, 'aabbccddeeff');
    expect(msg.timestampSeconds, 1234567890);
    expect(msg.text, 'Direct');
    expect(msg.snrDb, 1);
  });

  test('v3 direct plain text has no signature field', () {
    final msg = MeshCoreCompanionCodec.parseIncomingText([
      16,
      0,
      0,
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      0xff,
      0,
      1,
      0,
      0,
      0,
      ...utf8.encode('A'),
    ], maxChannels: 1);
    expect(msg.senderKeyPrefix, '010203040506');
    expect(msg.text, 'A');
    expect(msg.timestampSeconds, 1);
  });

  test(
    'v3 frames reject truncated, invalid text, wrong type and channel bounds',
    () {
      for (final frame in [
        <int>[17, 0],
        <int>[
          16,
          ...List.filled(10, 0),
          2,
          ...List.filled(4, 0),
        ], // Signed text without signature.
        <int>[17, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0],
        <int>[17, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0],
        <int>[17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff],
        <int>[8, ...List.filled(11, 0)],
      ]) {
        expect(
          () => MeshCoreCompanionCodec.parseIncomingText(frame, maxChannels: 8),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'channel command uses validated MeshCore slot and little-endian time',
    () {
      expect(
        MeshCoreCompanionCodec.encodeChannelText(
          target: const ConversationTarget(
            id: '1',
            protocol: MeshProtocol.meshCore,
          ),
          maxChannels: 8,
          timestampSeconds: 1234567890,
          text: 'Hello',
        ),
        [3, 0, 1, 0xd2, 0x02, 0x96, 0x49, ...utf8.encode('Hello')],
      );
      for (final target in [
        const ConversationTarget(id: '8', protocol: MeshProtocol.meshCore),
        const ConversationTarget(id: '-1', protocol: MeshProtocol.meshCore),
        const ConversationTarget(id: '01', protocol: MeshProtocol.meshCore),
        const ConversationTarget(id: '1', protocol: MeshProtocol.meshtastic),
      ]) {
        expect(
          () => MeshCoreCompanionCodec.encodeChannelText(
            target: target,
            maxChannels: 8,
            timestampSeconds: 1,
            text: 'Hi',
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'direct text encodes exact six-byte contact prefix and attempt zero',
    () {
      expect(
        MeshCoreCompanionCodec.encodeDirectText(
          target: const ConversationTarget(
            id: 'aabbccddeeff',
            protocol: MeshProtocol.meshCore,
          ),
          timestampSeconds: 1234567890,
          text: 'Hi',
        ),
        [
          2,
          0,
          0,
          0xd2,
          0x02,
          0x96,
          0x49,
          0xaa,
          0xbb,
          0xcc,
          0xdd,
          0xee,
          0xff,
          ...utf8.encode('Hi'),
        ],
      );
      for (final target in [
        const ConversationTarget(
          id: 'aabbccdd',
          protocol: MeshProtocol.meshCore,
        ),
        const ConversationTarget(
          id: 'aabbccddeeff00',
          protocol: MeshProtocol.meshCore,
        ),
        const ConversationTarget(
          id: 'aabbccddeefg',
          protocol: MeshProtocol.meshCore,
        ),
        const ConversationTarget(
          id: 'aabbccddeeff',
          protocol: MeshProtocol.meshtastic,
        ),
      ]) {
        expect(
          () => MeshCoreCompanionCodec.encodeDirectText(
            target: target,
            timestampSeconds: 1,
            text: 'Hi',
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test('send response reports only local radio acceptance, never delivery', () {
    expect(
      MeshCoreCompanionCodec.parseSendResponse([0], channel: true),
      MeshCoreLocalSendResult.acceptedByRadio,
    );
    expect(
      MeshCoreCompanionCodec.parseSendResponse([
        6,
        1,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ], channel: false),
      MeshCoreLocalSendResult.acceptedByRadio,
    );
    expect(
      MeshCoreCompanionCodec.parseSendResponse([1, 2], channel: false),
      MeshCoreLocalSendResult.rejectedByRadio,
    );
    for (final response in [
      <int>[6],
      <int>[0, 1],
      <int>[0x82],
      <int>[1],
    ]) {
      expect(
        () => MeshCoreCompanionCodec.parseSendResponse(response, channel: true),
        throwsFormatException,
      );
    }
    expect(
      () => MeshCoreCompanionCodec.parseSendResponse([0], channel: false),
      throwsFormatException,
    );
  });
  test(
    'outbound bounds reject empty, NUL, oversized UTF-8 and time overflow',
    () {
      const target = ConversationTarget(
        id: '0',
        protocol: MeshProtocol.meshCore,
      );
      for (final text in ['', 'a\u0000b', 'é' * 67]) {
        expect(
          () => MeshCoreCompanionCodec.encodeChannelText(
            target: target,
            maxChannels: 8,
            timestampSeconds: 1,
            text: text,
          ),
          throwsArgumentError,
        );
      }
      for (final time in [-1, 0x100000000]) {
        expect(
          () => MeshCoreCompanionCodec.encodeChannelText(
            target: target,
            maxChannels: 8,
            timestampSeconds: time,
            text: 'ok',
          ),
          throwsRangeError,
        );
      }
      expect(
        MeshCoreCompanionCodec.encodeChannelText(
          target: target,
          maxChannels: 8,
          timestampSeconds: 0xffffffff,
          text: 'a' * 133,
        ).length,
        140,
      );
    },
  );

  test('incoming rejects invalid bytes, empty text and oversized frames', () {
    for (final frame in [
      <int>[17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      <int>[17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      <int>[17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 256],
      <int>[17, ...List.filled(176, 0)],
    ]) {
      expect(
        () => MeshCoreCompanionCodec.parseIncomingText(frame, maxChannels: 8),
        throwsFormatException,
      );
    }
  });
  test('incoming rejects invalid encoded flood path lengths', () {
    for (final path in [0xc0, 0x7f, 0xbf]) {
      expect(
        () => MeshCoreCompanionCodec.parseIncomingText([
          17,
          0,
          0,
          0,
          0,
          path,
          0,
          1,
          0,
          0,
          0,
          65,
        ], maxChannels: 8),
        throwsFormatException,
      );
    }
  });

  test('validation errors do not echo message content or app names', () {
    try {
      MeshCoreCompanionCodec.encodeDirectText(
        target: const ConversationTarget(
          id: 'aabbccddeeff',
          protocol: MeshProtocol.meshCore,
        ),
        timestampSeconds: 1,
        text: 'private-content\u0000',
      );
      fail('Expected validation error');
    } on ArgumentError catch (error) {
      expect(error.toString(), isNot(contains('private-content')));
    }
    try {
      MeshCoreCompanionCodec.appStart('private-app\u0000');
      fail('Expected validation error');
    } on ArgumentError catch (error) {
      expect(error.toString(), isNot(contains('private-app')));
    }
  });
}

List<int> _fixed(String value, int width) => [
  ...utf8.encode(value),
  ...List<int>.filled(width - utf8.encode(value).length, 0),
];
