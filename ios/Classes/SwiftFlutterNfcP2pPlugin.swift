import Flutter
import UIKit
import CoreNFC

// ---------------------------------------------------------------------------
// iOS HCE NOTE
// ---------------------------------------------------------------------------
// Full Host Card Emulation on iOS requires the "com.apple.developer.nfc.hce"
// entitlement introduced in iOS 18.1. This entitlement is currently invite-
// only (available to financial-institution partners via Apple Pay NFC).
//
// Until the entitlement is available to your organisation, the sender (payer)
// side MUST use an Android device. The iOS implementation below covers the
// reader (receiver / merchant) side only, which works on any device running
// iOS 13+ with an NFC-capable chip.
//
// When you receive the HCE entitlement, implement NFCCardEmulationSession
// (iOS 18.1 SDK) in `startHce()` below and remove this comment.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// iOS Background Tag Reading
// ---------------------------------------------------------------------------
// To wake the app when the iPhone is locked/backgrounded and reads an NFC tag:
// 1. Add the "com.apple.developer.nfc.readersession.formats" entitlement with
//    value ["TAG"] to your Xcode entitlements file.
// 2. Add a Universal Link domain to your Xcode target.
// 3. Encode that Universal Link URL in an NDEF record on the peer device.
//    When iOS reads the NDEF record in background, it opens your Universal Link.
// 4. In AppDelegate.application(_:continue:restorationHandler:) retrieve
//    the NFC payload from the activity's userInfo["ndefMessagePayload"].
//
// For the APDU / HCE reader session in the foreground, no special entitlement
// is needed beyond the existing "Near Field Communication Tag Reading" capability.
// ---------------------------------------------------------------------------

@objc public class SwiftFlutterNfcP2pPlugin: NSObject, FlutterPlugin {

    // MARK: - Constants

    private static let methodChannelName = "flutter_nfc_p2p/methods"
    private static let eventChannelName  = "flutter_nfc_p2p/events"

    /// Custom AID — must match the Android side (HceService.kt / apdu_service.xml)
    private static let nfcAID: [UInt8] = [0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )

        let instance = SwiftFlutterNfcP2pPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - State

    private var eventSink: FlutterEventSink?
    private var tagSession: NFCTagReaderSession?

    // MARK: - FlutterPlugin (method calls)

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isNfcAvailable":
            result(NFCTagReaderSession.readingAvailable)

        case "startReader":
            startReader(result: result)

        case "stopReader":
            stopReader()
            result(nil)

        case "startHce":
            // HCE is not available without the invite-only entitlement.
            // Return a platform error so the host app can inform the user.
            result(FlutterError(
                code: "HCE_UNSUPPORTED",
                message: "iOS HCE requires the com.apple.developer.nfc.hce entitlement " +
                         "(iOS 18.1+, invite-only). Use an Android device as the sender.",
                details: nil
            ))

        case "stopHce":
            result(nil) // no-op on iOS until entitlement is available

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Reader mode

    private func startReader(result: @escaping FlutterResult) {
        guard NFCTagReaderSession.readingAvailable else {
            result(FlutterError(
                code: "NFC_UNAVAILABLE",
                message: "NFC is not available on this device or iOS version.",
                details: nil
            ))
            return
        }

        let session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        session?.alertMessage = "Hold your iPhone near the payment terminal."
        session?.begin()
        tagSession = session

        sendEvent(["type": "listening"])
        result(nil)
    }

    private func stopReader() {
        tagSession?.invalidate()
        tagSession = nil
    }

    // MARK: - Helpers

    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    private func sendError(code: String, message: String) {
        sendEvent(["type": "error", "code": code, "message": message])
    }

    /// Builds an ISO 7816-4 SELECT (by DF name) APDU for the given AID.
    private func buildSelectApdu(aid: [UInt8]) -> Data {
        var apdu: [UInt8] = [
            0x00, // CLA
            0xA4, // INS: SELECT
            0x04, // P1: by DF name
            0x00, // P2
            UInt8(aid.count) // Lc
        ]
        apdu.append(contentsOf: aid)
        apdu.append(0x00) // Le
        return Data(apdu)
    }
}

// ---------------------------------------------------------------------------
// MARK: - NFCTagReaderSessionDelegate
// ---------------------------------------------------------------------------

extension SwiftFlutterNfcP2pPlugin: NFCTagReaderSessionDelegate {

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session is active — already emitted "listening" in startReader()
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        // Code 200 = session invalidated by user / app — not a real error.
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled &&
           nfcError?.code != .readerSessionInvalidationErrorSessionTimeout {
            sendError(code: "SESSION_ERROR", message: error.localizedDescription)
        }
        tagSession = nil
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else { return }
        sendEvent(["type": "deviceDetected"])

        session.connect(to: firstTag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Connection failed.")
                self.sendError(code: "CONNECTION_ERROR", message: error.localizedDescription)
                return
            }

            guard case .iso7816(let iso7816Tag) = firstTag else {
                session.invalidate(errorMessage: "Unsupported tag type.")
                self.sendError(code: "UNSUPPORTED_TAG", message: "Tag does not support ISO 7816.")
                return
            }

            let apduData = self.buildSelectApdu(aid: SwiftFlutterNfcP2pPlugin.nfcAID)
            let apdu = NFCISO7816APDU(data: apduData)!

            iso7816Tag.sendCommand(apdu: apdu) { responseData, sw1, sw2, error in
                if let error = error {
                    session.invalidate(errorMessage: "APDU failed.")
                    self.sendError(code: "APDU_ERROR", message: error.localizedDescription)
                    return
                }

                if sw1 == 0x90 && sw2 == 0x00 {
                    if let token = String(data: responseData, encoding: .utf8) {
                        session.alertMessage = "Payment token received!"
                        session.invalidate()
                        self.sendEvent(["type": "tokenReceived", "token": token])
                    } else {
                        session.invalidate(errorMessage: "Failed to decode token.")
                        self.sendError(code: "DECODE_ERROR", message: "Token is not valid UTF-8.")
                    }
                } else {
                    let msg = String(format: "Status word: %02X%02X", sw1, sw2)
                    session.invalidate(errorMessage: "Unexpected response.")
                    self.sendError(code: "APDU_SW_ERROR", message: msg)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - FlutterStreamHandler
// ---------------------------------------------------------------------------

extension SwiftFlutterNfcP2pPlugin: FlutterStreamHandler {

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
