# flutter_nfc_p2p

A **headless** Flutter plugin for custom phone-to-phone NFC interactions designed for closed-loop payment systems. It bypasses Visa/Mastercard entirely — all you need is your own backend.

| Feature | Android | iOS |
|---|---|---|
| NFC Reader (Receiver/Merchant) | ✅ | ✅ (iOS 13+) |
| HCE Sender (Payer) | ✅ (Android 5+) | ⚠️ iOS 18.1+ entitlement required (see below) |
| App wake-up from background | ✅ NDEF/Tech intent filters | ✅ Background Tag Reading via Universal Links |

> **Strictly headless** — this package contains zero UI. It exposes a `Stream<NfcEvent>` that your app consumes to build its own UI.

---

## Hardware Requirements

- Two Android phones with NFC, both supporting HCE (Android 4.4+)
- One phone acts as **Sender** (HCE/payer), the other as **Receiver** (reader/merchant)
- iOS: reader mode works (iOS 13+), but sender/HCE is stub-only until Apple grants the entitlement

---

## How it works

```
Sender (Payer)                    Receiver (Merchant)
─────────────────────────────────────────────────────
1. App fetches short-lived         
   token from your backend         
                                   
2. startHce(token: "PAY-…")  ←→   startReader()
   [Android HostApduService        [NFC Reader mode /
    responds with token]            CoreNFC session]
                                   
3.                                 NfcTokenReceivedEvent("PAY-…")
                                   
4.                                 App POSTs token to backend
                                   Backend validates & settles
```

The plugin handles the NFC APDU handshake. Your app owns the backend calls.

---

## Installation

```yaml
dependencies:
  flutter_nfc_p2p: ^0.1.0
```

---

## Android Setup

### 1. Permissions

Add to your **app's** `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
<uses-feature android:name="android.hardware.nfc.hce" android:required="false" />
```

> Set `android:required="true"` if NFC is essential to your app, or `"false"` if it is optional. Devices without NFC will not see your app on the Play Store when `required="true"`.

### 2. HCE Service

Re-declare the HCE service inside your `<application>` tag so Android's manifest merger
keeps it and routes APDUs to it:

```xml
<service
    android:name="com.example.flutter_nfc_p2p.HceService"
    android:exported="true"
    android:permission="android.permission.BIND_NFC_SERVICE">
    <intent-filter>
        <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
    </intent-filter>
    <meta-data
        android:name="android.nfc.cardemulation.host_apdu_service"
        android:resource="@xml/apdu_service" />
</service>
```

Copy `android/src/main/res/xml/apdu_service.xml` from this package into your app's
`android/app/src/main/res/xml/` directory.

### 3. App Wake-up (Intent Filters)

To have Android open (or resume) your app when the **receiver phone** detects the sender's HCE device, add these to your `MainActivity`:

```xml
<!-- Wakes the app for any ISO-DEP / NFC-A / NFC-B tag -->
<intent-filter>
    <action android:name="android.nfc.action.TECH_DISCOVERED" />
</intent-filter>
<meta-data
    android:name="android.nfc.action.TECH_DISCOVERED"
    android:resource="@xml/nfc_tech_filter" />
```

Create `android/app/src/main/res/xml/nfc_tech_filter.xml`:

```xml
<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">
    <tech-list>
        <tech>android.nfc.tech.IsoDep</tech>
    </tech-list>
</resources>
```

Set `android:launchMode="singleTop"` on your MainActivity to avoid launching duplicate instances when an NFC intent arrives while the app is in the foreground.

---

## iOS Setup

### 1. Xcode Capability

In Xcode, navigate to **Signing & Capabilities → + → Near Field Communication Tag Reading**.
This adds the `com.apple.developer.nfc.readersession.formats` entitlement automatically.

### 2. Info.plist

```xml
<key>NFCReaderUsageDescription</key>
<string>This app uses NFC to receive payment tokens from nearby devices.</string>
```

### 3. Background Tag Reading (app wake-up)

To wake your iOS app when it is in the background or screen is locked:

1. Enable **Associated Domains** in Xcode and add your Universal Link domain:
   `applinks:pay.your-domain.com`

2. Host an `apple-app-site-association` JSON file at
   `https://pay.your-domain.com/.well-known/apple-app-site-association`.

3. On the **sender (Android) side**, encode your Universal Link URL as an NDEF record.
   When iOS scans the NDEF tag in background, it delivers the URL to your app via
   `UIApplicationDelegate.application(_:continue:restorationHandler:)`.

4. In `AppDelegate.swift`:
   ```swift
   func application(_ application: UIApplication,
                    continue userActivity: NSUserActivity,
                    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
       if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
           // Extract the token from the URL query parameters and forward to Flutter
           // via a MethodChannel or EventChannel call.
       }
       return true
   }
   ```

### 4. iOS HCE (Sender side)

Full HCE on iOS requires the `com.apple.developer.nfc.hce` entitlement,
introduced in iOS 18.1. This entitlement is currently **invite-only** (financial
institution partners via Apple Pay NFC). Until you receive it:

- Use an **Android device** as the sender/payer.
- When you receive the entitlement, implement `NFCCardEmulationSession` in
  `SwiftFlutterNfcP2pPlugin.swift` and replace the `startHce` stub.

---

## API Reference

### `FlutterNfcP2p`

| Method | Returns | Description |
|---|---|---|
| `isNfcAvailable()` | `Future<bool>` | Returns true if NFC is supported and enabled |
| `startHce({required String token})` | `Future<void>` | Start HCE broadcasting (sender/payer) |
| `stopHce()` | `Future<void>` | Stop HCE |
| `startReader()` | `Future<void>` | Enable NFC reader mode (receiver/merchant) |
| `stopReader()` | `Future<void>` | Disable NFC reader mode |
| `eventStream` | `Stream<NfcEvent>` | Broadcast stream of NFC events |

### `NfcEvent` subtypes

| Type | Fields | When emitted |
|---|---|---|
| `NfcListeningEvent` | — | Reader mode is active |
| `NfcDeviceDetectedEvent` | — | A device came within range |
| `NfcTokenReceivedEvent` | `token: String` | Token successfully read from sender |
| `HceStartedEvent` | — | HCE is broadcasting |
| `HceStoppedEvent` | — | HCE stopped |
| `NfcErrorEvent` | `message`, `code?` | Error in either mode |
| `NfcUnavailableEvent` | `reason` | NFC not available/enabled |

---

## Usage

### Sender (Payer) — broadcast a token via HCE

```dart
import 'package:flutter_nfc_p2p/flutter_nfc_p2p.dart';

// 1. Fetch a short-lived token from your backend
final token = await myBackend.createPaymentToken(amount: 42.50);

// 2. Start HCE
await FlutterNfcP2p.startHce(token: token);

// 3. Listen for events
FlutterNfcP2p.eventStream.listen((event) {
  switch (event) {
    case HceStartedEvent():
      updateUI('Hold your phone near the terminal');
    case NfcErrorEvent(:final message):
      showError(message);
    default:
      break;
  }
});

// 4. Stop HCE when the user navigates away
@override
void dispose() {
  FlutterNfcP2p.stopHce();
  super.dispose();
}
```

### Receiver (Merchant) — read the token and submit to backend

```dart
import 'package:flutter_nfc_p2p/flutter_nfc_p2p.dart';
import 'package:http/http.dart' as http;

final sub = FlutterNfcP2p.eventStream.listen((event) async {
  switch (event) {
    case NfcListeningEvent():
      showUI('Tap the payer\'s phone here');
    case NfcDeviceDetectedEvent():
      showUI('Hold still…');
    case NfcTokenReceivedEvent(:final token):
      await sub.cancel();
      await redeemToken(token);  // your backend call
    case NfcErrorEvent(:final message, :final code):
      showError('$code: $message');
    default:
      break;
  }
});

await FlutterNfcP2p.startReader();

// Your backend call — the plugin does NOT make HTTP requests
Future<void> redeemToken(String token) async {
  final response = await http.post(
    Uri.parse('https://api.your-backend.com/v1/transactions/redeem'),
    headers: {'Authorization': 'Bearer $merchantKey'},
    body: '{"payment_token": "$token"}',
  );
  // handle response…
}
```

---

## Custom AID

The plugin uses the proprietary AID `F001020304050607` (the `F0` prefix is reserved for proprietary use per ISO 7816-4 and will not conflict with payment scheme AIDs).

To change it:
1. Update `NFC_AID` in `android/src/main/kotlin/…/HceService.kt`.
2. Update the `<aid-filter>` in `android/src/main/res/xml/apdu_service.xml`.
3. Update `nfcAID` in `ios/Classes/SwiftFlutterNfcP2pPlugin.swift`.

---

## Security notes

- Tokens should be **short-lived** (60–300 seconds) and **single-use**, generated and validated by your backend.
- Tokens are transmitted in plaintext over the air via NFC. NFC operates at ~5 cm range — physical proximity is the primary security layer, but you should still treat tokens as sensitive.
- Do **not** encode any PAN, CVV, or cardholder data in the token. The token should be an opaque reference that your backend resolves.

---

## License

MIT — see [LICENSE](LICENSE).
