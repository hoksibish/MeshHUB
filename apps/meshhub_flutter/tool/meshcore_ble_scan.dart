import 'dart:convert';
import 'dart:io';

import 'package:meshhub_flutter/linux_meshcore_ble.dart';

Future<void> main() async {
  final scanner = MeshCoreBleScanner(scanBlueZ);
  final candidates = await scanner.scan(const Duration(seconds: 12));
  stdout.writeln(
    jsonEncode({
      'candidateCount': candidates.length,
      'freshCandidates': candidates.where((c) => c.isFresh).length,
      'cachedCandidates': candidates.where((c) => !c.isFresh).length,
      'serviceUuidKnown': candidates
          .where(
            (c) => c.assessment == MeshCoreCandidateAssessment.serviceUuidKnown,
          )
          .length,
      'nameHintOnly': candidates
          .where(
            (c) => c.assessment == MeshCoreCandidateAssessment.nameHintOnly,
          )
          .length,
      'identityVerified': false,
      'paired': false,
      'connected': false,
    }),
  );
}
