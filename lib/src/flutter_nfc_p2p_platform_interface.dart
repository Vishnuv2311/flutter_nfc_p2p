import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models/nfc_event.dart';

abstract class FlutterNfcP2pPlatform extends PlatformInterface {
  FlutterNfcP2pPlatform() : super(token: _token);

  static final Object _token = Object();
  static FlutterNfcP2pPlatform? _instance;

  /// True if an implementation has been registered (or the default was set).
  static bool get hasInstance => _instance != null;

  static FlutterNfcP2pPlatform get instance {
    final i = _instance;
    if (i == null) {
      throw UnimplementedError(
        'No platform implementation registered for FlutterNfcP2pPlatform. '
        'The default MethodChannel implementation is registered automatically '
        'when you access FlutterNfcP2p — ensure you import flutter_nfc_p2p.dart.',
      );
    }
    return i;
  }

  static set instance(FlutterNfcP2pPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Stream of NFC events from both HCE and reader mode.
  Stream<NfcEvent> get eventStream;

  /// Start HCE (Host Card Emulation) on the sender device.
  ///
  /// [token] is the secure, short-lived token that the receiver will read.
  /// Throws [UnsupportedError] if HCE is not supported.
  Future<void> startHce(String token);

  /// Stop the active HCE service.
  Future<void> stopHce();

  /// Enable NFC reader mode on the receiver device.
  ///
  /// Emits [NfcListeningEvent] immediately, then either
  /// [NfcTokenReceivedEvent] or [NfcErrorEvent] once a device is tapped.
  Future<void> startReader();

  /// Disable NFC reader mode.
  Future<void> stopReader();

  /// Returns true if NFC is available and enabled on this device.
  Future<bool> isNfcAvailable();
}
