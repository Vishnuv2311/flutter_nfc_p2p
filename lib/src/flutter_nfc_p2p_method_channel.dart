import 'dart:async';
import 'package:flutter/services.dart';
import 'flutter_nfc_p2p_platform_interface.dart';
import 'models/nfc_event.dart';

/// Method channel names must stay in sync with the native side.
const _methodChannel = MethodChannel('flutter_nfc_p2p/methods');
const _eventChannel = EventChannel('flutter_nfc_p2p/events');

class MethodChannelFlutterNfcP2p extends FlutterNfcP2pPlatform {
  Stream<NfcEvent>? _eventStream;

  @override
  Stream<NfcEvent> get eventStream {
    if (_eventStream != null) return _eventStream!;

    // Use a broadcast StreamController so we can convert EventChannel *errors*
    // (stream-level errors) into typed NfcErrorEvent values. handleError()'s
    // return value is ignored by the Stream API, so we need this explicit
    // bridge instead of chaining .map().handleError().
    final controller = StreamController<NfcEvent>.broadcast();
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) => controller.add(_parseEvent(event)),
      onError: (Object err) {
        final pe = err is PlatformException ? err : null;
        controller.add(NfcErrorEvent(
          pe?.message ?? err.toString(),
          code: pe?.code,
        ));
      },
      cancelOnError: false,
    );
    _eventStream = controller.stream;
    return _eventStream!;
  }

  @override
  Future<void> startHce(String token) async {
    try {
      await _methodChannel.invokeMethod<void>('startHce', {'token': token});
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<void> stopHce() async {
    try {
      await _methodChannel.invokeMethod<void>('stopHce');
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<void> startReader() async {
    try {
      await _methodChannel.invokeMethod<void>('startReader');
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<void> stopReader() async {
    try {
      await _methodChannel.invokeMethod<void>('stopReader');
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<bool> isNfcAvailable() async {
    final result =
        await _methodChannel.invokeMethod<bool>('isNfcAvailable') ?? false;
    return result;
  }

  static NfcEvent _parseEvent(dynamic raw) {
    if (raw is! Map) return const NfcErrorEvent('Malformed event from native');
    final map = Map<String, dynamic>.from(raw);
    final type = map['type'] as String? ?? '';

    return switch (type) {
      'listening' => const NfcListeningEvent(),
      'deviceDetected' => const NfcDeviceDetectedEvent(),
      'tokenReceived' => NfcTokenReceivedEvent(map['token'] as String),
      'hceStarted' => const HceStartedEvent(),
      'hceStopped' => const HceStoppedEvent(),
      'unavailable' =>
        NfcUnavailableEvent(map['reason'] as String? ?? 'NFC unavailable'),
      'error' => NfcErrorEvent(
          map['message'] as String? ?? 'Unknown error',
          code: map['code'] as String?,
        ),
      _ => NfcErrorEvent('Unknown event type: $type'),
    };
  }

  static Never _throwMapped(PlatformException e) {
    switch (e.code) {
      case 'NFC_UNAVAILABLE':
        throw UnsupportedError(e.message ?? 'NFC not available');
      case 'HCE_UNSUPPORTED':
        throw UnsupportedError(e.message ?? 'HCE not supported on this device');
      default:
        throw Exception('${e.code}: ${e.message}');
    }
  }
}
