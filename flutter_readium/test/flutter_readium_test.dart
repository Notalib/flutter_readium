import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterReadiumPlatform with MockPlatformInterfaceMixin implements FlutterReadiumPlatform {
  @override
  ReadiumReaderWidgetInterface? currentReaderWidget;

  @override
  EPUBPreferences? defaultPreferences;

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) {
    // TODO: implement setCustomHeaders
    throw UnimplementedError();
  }

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) =>
      Future.value(Publication(links: [], metadata: Metadata(title: {'en': 'test'}), readingOrder: []));

  @override
  Future<Publication> openPublication(String pubUrl) =>
      Future.value(Publication(links: [], metadata: Metadata(title: {'en': 'test'}), readingOrder: []));

  @override
  Stream<Locator> get onTextLocatorChanged => Stream.fromIterable([
        // TODO: Test locators
      ]);

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) {
    // TODO: implement applyDecorations
    throw UnimplementedError();
  }

  @override
  Future<void> closePublication() {
    // TODO: implement closePublication
    throw UnimplementedError();
  }

  @override
  Future<void> goLeft() {
    // TODO: implement goLeft
    throw UnimplementedError();
  }

  @override
  Future<void> goRight() {
    // TODO: implement goRight
    throw UnimplementedError();
  }

  @override
  // TODO: implement onReaderStatusChanged
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => throw UnimplementedError();

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) {
    // TODO: implement setEPUBPreferences
    throw UnimplementedError();
  }

  @override
  Future<void> skipToNext() {
    // TODO: implement skipToNext
    throw UnimplementedError();
  }

  @override
  Future<void> skipToPrevious() {
    // TODO: implement skipToPrevious
    throw UnimplementedError();
  }

  @override
  Future<void> ttsEnable(TTSPreferences? preferences) {
    // TODO: implement ttsEnable
    throw UnimplementedError();
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() {
    // TODO: implement ttsGetAvailableVoices
    throw UnimplementedError();
  }

  @override
  Future<void> ttsSetDecorationStyle(
      ReaderDecorationStyle? utteranceDecoration, ReaderDecorationStyle? rangeDecoration) {
    // TODO: implement ttsSetDecorationStyle
    throw UnimplementedError();
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) {
    // TODO: implement ttsSetVoice
    throw UnimplementedError();
  }

  @override
  Future<void> play(Locator? fromLocator) {
    // TODO: implement play
    throw UnimplementedError();
  }

  @override
  Future<void> pause() {
    // TODO: implement ttsPause
    throw UnimplementedError();
  }

  @override
  Future<void> resume() {
    // TODO: implement ttsResume
    throw UnimplementedError();
  }

  @override
  Future<void> next() {
    // TODO: implement ttsNext
    throw UnimplementedError();
  }

  @override
  Future<void> previous() {
    // TODO: implement ttsPrevious
    throw UnimplementedError();
  }

  @override
  Future<void> stop() {
    // TODO: implement stop
    throw UnimplementedError();
  }

  @override
  // TODO: implement onAudioLocatorChanged
  Stream<Locator> get onAudioLocatorChanged => throw UnimplementedError();

  @override
  // TODO: implement onTimebasedPlayerStateChanged
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => throw UnimplementedError();

  @override
  // TODO: implement onErrorEvent
  Stream<ReadiumError> get onErrorEvent => throw UnimplementedError();

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) {
    // TODO: implement ttsSetPreferences
    throw UnimplementedError();
  }

  @override
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) {
    // TODO: implement audioEnable
    throw UnimplementedError();
  }

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) {
    // TODO: implement audioSetPreferences
    throw UnimplementedError();
  }

  @override
  Future<String?> getLinkContent(Link link) {
    // TODO: implement getLinkContent
    throw UnimplementedError();
  }

  @override
  Future<bool> goToLocator(Locator locator) {
    // TODO: implement goToLocator
    throw UnimplementedError();
  }
}

void main() {
  late FlutterReadium flutterReadium;
  late MockFlutterReadiumPlatform fakePlatform;

  setUpAll(() {
    fakePlatform = MockFlutterReadiumPlatform();
    FlutterReadiumPlatform.instance = fakePlatform;
    flutterReadium = FlutterReadium();
  });

  // test('batteryLevel', () async {
  //   expect(await flutterReadium.batteryLevel, 42);
  // });

  // test('isInBatterySaveMode', () async {
  //   expect(await flutterReadium.isInBatterySaveMode, true);
  // });

  // test('current state of the battery', () async {
  //   expect(await flutterReadium.batteryState, BatteryState.charging);
  // });

  // test('receiving events of the battery state', () async {
  //   final queue = StreamQueue<BatteryState>(battery.onBatteryStateChanged);

  //   expect(await queue.next, BatteryState.unknown);
  //   expect(await queue.next, BatteryState.charging);
  //   expect(await queue.next, BatteryState.full);
  //   expect(await queue.next, BatteryState.discharging);

  //   expect(await queue.hasNext, false);
  // });
}
