import 'package:flutter_test/flutter_test.dart';
import 'package:meshhub_flutter/diagnostics.dart';

void main() {
  test('diagnostic logger emits only fixed event codes', () {
    final emitted = <String>[];
    final logger = DiagnosticLogger(emitted.add);
    logger.record(DiagnosticEvent.radioDisconnected);

    expect(emitted, ['radio_disconnected']);
    expect(emitted.single, isNot(contains('device')));
  });
}
