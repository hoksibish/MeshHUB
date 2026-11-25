/// Protocol identifiers never imply interchangeable radios or identities.
enum MeshProtocol { meshCore, meshtastic }

/// A capability is explicit evidence, not inferred from a device name.
enum RadioCapability { receiveText, rfTransmit }

class RadioDevice {
  const RadioDevice({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.isSimulated,
    required this.capabilities,
  });

  final String id;
  final String displayName;
  final MeshProtocol protocol;
  final bool isSimulated;
  final Set<RadioCapability> capabilities;
}

/// Message state describes observation, not an end-to-end delivery receipt.
enum MessageDeliveryState { receivedByRadio, acceptedByLocalRadio }

/// A locally displayed message; simulation is never confused with RF evidence.
class RadioMessage {
  const RadioMessage({
    required this.id,
    required this.conversationId,
    required this.protocol,
    required this.sender,
    required this.text,
    required this.isSimulated,
    this.isOutgoing = false,
    this.deliveryState = MessageDeliveryState.receivedByRadio,
  });

  final String id;
  final String conversationId;
  final MeshProtocol protocol;
  final String sender;
  final String text;
  final bool isSimulated;
  final bool isOutgoing;
  final MessageDeliveryState deliveryState;
}

/// Storage boundary; encrypted on-disk implementation is a later milestone.
abstract interface class MessageRepository {
  Future<List<RadioMessage>> forProtocol(MeshProtocol protocol);
}

/// A mock result must not be presented as radio delivery.
enum SendStatus { simulated, submittedToRadio, uncertain }

/// A destination is bound to its network, even when IDs overlap.
class ConversationTarget {
  const ConversationTarget({required this.id, required this.protocol});

  final String id;
  final MeshProtocol protocol;
}

/// Byte transport boundary; a BLE/TCP implementation is not present in M0.
abstract interface class RadioTransport {
  MeshProtocol get protocol;
  Stream<List<int>> get frames;
  Future<void> open();
  Future<void> writeFrame(List<int> bytes);
  Future<void> close();
}

/// Protocol-specific integrations implement this port independently.
abstract interface class RadioAdapter {
  MeshProtocol get protocol;
  Future<List<RadioDevice>> discover();

  /// Incoming messages retain their protocol and simulation provenance.
  Stream<RadioMessage> get incomingText;
  Future<SendStatus> sendText({
    required ConversationTarget target,
    required String text,
  });
}
