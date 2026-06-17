import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_nfc_p2p/flutter_nfc_p2p.dart';
import 'package:flutter_nfc_p2p/src/flutter_nfc_p2p_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockFlutterNfcP2pPlatform
    with MockPlatformInterfaceMixin
    implements FlutterNfcP2pPlatform {
  final _controller = StreamController<NfcEvent>.broadcast();

  @override
  Stream<NfcEvent> get eventStream => _controller.stream;

  @override
  Future<bool> isNfcAvailable() async => true;

  @override
  Future<void> startHce(String token) async {
    _controller.add(const HceStartedEvent());
  }

  @override
  Future<void> stopHce() async {
    _controller.add(const HceStoppedEvent());
  }

  @override
  Future<void> startReader() async {
    _controller.add(const NfcListeningEvent());
  }

  @override
  Future<void> stopReader() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockFlutterNfcP2pPlatform mock;

  setUp(() {
    mock = _MockFlutterNfcP2pPlatform();
    FlutterNfcP2pPlatform.instance = mock;
  });

  test('isNfcAvailable returns true from mock', () async {
    expect(await FlutterNfcP2p.isNfcAvailable(), isTrue);
  });

  test('startHce emits HceStartedEvent', () async {
    final events = <NfcEvent>[];
    final sub = FlutterNfcP2p.eventStream.listen(events.add);
    await FlutterNfcP2p.startHce(token: 'TEST-TOKEN-123');
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(isA<HceStartedEvent>()));
    await sub.cancel();
  });

  test('stopHce emits HceStoppedEvent', () async {
    final events = <NfcEvent>[];
    final sub = FlutterNfcP2p.eventStream.listen(events.add);
    await FlutterNfcP2p.stopHce();
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(isA<HceStoppedEvent>()));
    await sub.cancel();
  });

  test('startReader emits NfcListeningEvent', () async {
    final events = <NfcEvent>[];
    final sub = FlutterNfcP2p.eventStream.listen(events.add);
    await FlutterNfcP2p.startReader();
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(isA<NfcListeningEvent>()));
    await sub.cancel();
  });

  test('default platform is MethodChannelFlutterNfcP2p', () {
    FlutterNfcP2pPlatform.instance = MethodChannelFlutterNfcP2p();
    expect(
      FlutterNfcP2pPlatform.instance,
      isA<MethodChannelFlutterNfcP2p>(),
    );
  });
}
