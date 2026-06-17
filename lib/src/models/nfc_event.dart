/// All NFC-related events emitted by the plugin.
///
/// The host app subscribes to [FlutterNfcP2p.eventStream] and casts
/// to the concrete subtype it cares about.
sealed class NfcEvent {
  const NfcEvent();
}

/// Reader mode is active and waiting for a device to be presented.
class NfcListeningEvent extends NfcEvent {
  const NfcListeningEvent();
}

/// A device (or tag) came within range. Emitted before the APDU exchange
/// completes — useful for showing a "hold still" indicator.
class NfcDeviceDetectedEvent extends NfcEvent {
  const NfcDeviceDetectedEvent();
}

/// The reader successfully completed the APDU exchange and extracted a token.
class NfcTokenReceivedEvent extends NfcEvent {
  /// The raw token string returned by the sender's HCE service.
  final String token;
  const NfcTokenReceivedEvent(this.token);
}

/// HCE was started successfully on the sender side.
class HceStartedEvent extends NfcEvent {
  const HceStartedEvent();
}

/// HCE was stopped (either by the app or the OS).
class HceStoppedEvent extends NfcEvent {
  const HceStoppedEvent();
}

/// An error occurred in either reader or HCE mode.
class NfcErrorEvent extends NfcEvent {
  final String message;
  final String? code;
  const NfcErrorEvent(this.message, {this.code});
}

/// NFC hardware is not available or is disabled on this device.
class NfcUnavailableEvent extends NfcEvent {
  final String reason;
  const NfcUnavailableEvent(this.reason);
}
