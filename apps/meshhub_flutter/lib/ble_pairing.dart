import 'dart:async';

import 'package:bluez/bluez.dart';

typedef BlePinRequest = Future<String?> Function();

/// Scoped to one explicitly selected device. Never becomes the default agent.
class BlePinAgent extends BlueZAgent {
  BlePinAgent(this.deviceId, this.requestPin, this.cancelPrompt);
  final String deviceId;
  final BlePinRequest requestPin;
  final void Function() cancelPrompt;
  bool active = true;

  Future<String?> _pin(BlueZDevice device) async {
    if (!active || device.path.value != deviceId) return null;
    try {
      final pin = await requestPin().timeout(const Duration(seconds: 60));
      return active && pin != null && RegExp(r'^\d{6}$').hasMatch(pin)
          ? pin
          : null;
    } on TimeoutException {
      return null;
    } finally {
      cancelPrompt();
    }
  }

  @override
  Future<BlueZAgentPasskeyResponse> requestPasskey(BlueZDevice device) async {
    final pin = await _pin(device);
    return pin == null
        ? BlueZAgentPasskeyResponse.canceled()
        : BlueZAgentPasskeyResponse.success(int.parse(pin));
  }

  @override
  Future<BlueZAgentPinCodeResponse> requestPinCode(BlueZDevice device) async {
    final pin = await _pin(device);
    return pin == null
        ? BlueZAgentPinCodeResponse.canceled()
        : BlueZAgentPinCodeResponse.success(pin);
  }

  @override
  Future<void> cancel() async {
    active = false;
    cancelPrompt();
  }

  @override
  Future<void> release() async {
    active = false;
    cancelPrompt();
  }
}
