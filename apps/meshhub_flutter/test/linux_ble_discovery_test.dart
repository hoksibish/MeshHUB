import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/linux_meshcore_ble.dart';

void main() {
  test(
    'scanner deduplicates observed candidates without claiming identity',
    () async {
      final scanner = MeshCoreBleScanner(
        (_) async => const [
          MeshCoreBleObservation('a', 'MeshCore-radio', []),
          MeshCoreBleObservation('a', 'MeshCore-radio', [
            MeshCoreCandidateAssessment.serviceUuid,
          ]),
          MeshCoreBleObservation('b', 'Other', []),
        ],
      );
      final candidates = await scanner.scan(const Duration(milliseconds: 1));
      expect(candidates, hasLength(1));
      expect(candidates.single.id, 'a');
      expect(
        candidates.single.assessment,
        MeshCoreCandidateAssessment.serviceUuidKnown,
      );
    },
  );

  test(
    'cached BlueZ candidate is not mistaken for a fresh observation',
    () async {
      final scanner = MeshCoreBleScanner(
        (_) async => const [
          MeshCoreBleObservation('known', 'MeshCore-Radio', [], isFresh: false),
        ],
      );
      final candidates = await scanner.scan(const Duration(milliseconds: 1));
      expect(candidates.single.isFresh, isFalse);
    },
  );

  test(
    'BlueZ scan rejects a nonpositive duration before touching D-Bus',
    () async {
      await expectLater(scanBlueZ(Duration.zero), throwsArgumentError);
    },
  );

  test('scan cleanup closes client even if stopping discovery fails', () async {
    final steps = <String>[];
    await expectLater(
      finishBleDiscovery(
        stop: () async {
          steps.add('stop');
          throw StateError('stop failed');
        },
        cancelAdded: () async => steps.add('added'),
        cancelProperties: [() async => steps.add('property')],
        closeClient: () async => steps.add('client'),
      ),
      throwsStateError,
    );
    expect(steps, ['stop', 'added', 'property', 'client']);
  });

  test('scan preserves its original error when cleanup also fails', () async {
    final steps = <String>[];
    await expectLater(
      withBleCleanup(
        () async {
          steps.add('scan');
          throw StateError('scan failed');
        },
        () async {
          steps.add('cleanup');
          throw StateError('cleanup failed');
        },
      ),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'scan failed'),
      ),
    );
    expect(steps, ['scan', 'cleanup']);
  });

  test('MeshCore service advertisement is a candidate, not a connection', () {
    expect(
      MeshCoreCandidateAssessment.assess(
        name: 'Custom radio',
        uuids: const ['6e400001-b5a3-f393-e0a9-e50e24dcca9e'],
      ),
      MeshCoreCandidateAssessment.serviceUuidKnown,
    );
  });

  test('MeshCore-like name alone does not verify a service', () {
    expect(
      MeshCoreCandidateAssessment.assess(
        name: 'MeshCore-Heltec',
        uuids: const [],
      ),
      MeshCoreCandidateAssessment.nameHintOnly,
    );
    expect(
      MeshCoreCandidateAssessment.assess(name: 'Other', uuids: const []),
      MeshCoreCandidateAssessment.unrelated,
    );
  });
}
