## 0.1.0

* Initial release.
* Android: HCE sender via `HostApduService`, NFC reader mode via `NfcAdapter.enableReaderMode`.
* iOS: NFC reader mode via `NFCTagReaderSession` (CoreNFC). HCE stub with instructions for iOS 18.1+ entitlement.
* Headless API: `Stream<NfcEvent>` with `NfcListeningEvent`, `NfcDeviceDetectedEvent`, `NfcTokenReceivedEvent`, `HceStartedEvent`, `HceStoppedEvent`, `NfcErrorEvent`, `NfcUnavailableEvent`.
* Example app demonstrating both sender and receiver flows with mock server call.
