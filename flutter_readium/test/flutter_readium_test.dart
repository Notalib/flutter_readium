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
  Future<void> closePublication(String pubIdentifier) {
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
  Future<void> ttsEnable(String? defaultLangCode, String? voiceIdentifier) {
    // TODO: implement ttsEnable
    throw UnimplementedError();
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() {
    // TODO: implement ttsGetAvailableVoices
    throw UnimplementedError();
  }

  @override
  Future<void> ttsNext() {
    // TODO: implement ttsNext
    throw UnimplementedError();
  }

  @override
  Future<void> ttsPause() {
    // TODO: implement ttsPause
    throw UnimplementedError();
  }

  @override
  Future<void> ttsPrevious() {
    // TODO: implement ttsPrevious
    throw UnimplementedError();
  }

  @override
  Future<void> ttsResume() {
    // TODO: implement ttsResume
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
  Future<void> ttsStart(Locator? fromLocator) {
    // TODO: implement ttsStart
    throw UnimplementedError();
  }

  @override
  Future<void> ttsStop() {
    // TODO: implement ttsStop
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
