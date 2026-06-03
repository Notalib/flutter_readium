import 'dart:async';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Mock platform
// ---------------------------------------------------------------------------

class MockFlutterReadiumPlatform
    with MockPlatformInterfaceMixin
    implements FlutterReadiumPlatform {
  @override
  ReadiumReaderWidgetInterface? currentReaderWidget;

  @override
  EPUBPreferences? defaultPreferences;

  final _textLocatorController = StreamController<Locator>.broadcast();
  final _statusController = StreamController<ReadiumReaderStatus>.broadcast();
  final _timebasedController =
      StreamController<ReadiumTimebasedState>.broadcast();
  final _errorController = StreamController<ReadiumError>.broadcast();

  @override
  Stream<Locator> get onTextLocatorChanged => _textLocatorController.stream;

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged =>
      _statusController.stream;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged =>
      _timebasedController.stream;

  @override
  Stream<ReadiumError> get onErrorEvent => _errorController.stream;

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  static Publication _pub(String title) => Publication(
    links: [],
    metadata: Metadata(
      localizedTitle: LocalizedString.fromStrings({'en': title}),
    ),
    readingOrder: [],
  );

  @override
  Future<Publication> loadPublication(String pubUrl) async => _pub('Loaded');

  @override
  Future<Publication> openPublication(String pubUrl) async => _pub('Opened');

  @override
  Future<void> closePublication() async {}

  @override
  Future<void> goBackward() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<bool> goToLocator(Locator locator) async => true;

  @override
  Future<bool> goToProgression(double progression) async => true;

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {}

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {}

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {}

  @override
  Future<void> play(Locator? fromLocator) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> ttsEnable(TTSPreferences? preferences) async {}

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {}

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async => [];

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) async {}

  @override
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) async {}

  @override
  Future<void> audioEnable({
    AudioPreferences? prefs,
    Locator? fromLocator,
  }) async {}

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) async {}

  @override
  Future<void> audioSeekBy(Duration offset) async {}

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {}

  @override
  Future<void> setLogLevel(LogLevel level) async {}

  @override
  Future<List<TextSearchResult>> searchInPublication(String searchKey) async =>
      [];

  void emitLocator(Locator l) => _textLocatorController.add(l);
  void emitStatus(ReadiumReaderStatus s) => _statusController.add(s);
  void emitError(ReadiumError e) => _errorController.add(e);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterReadium reader;
  late MockFlutterReadiumPlatform platform;

  setUp(() {
    platform = MockFlutterReadiumPlatform();
    FlutterReadiumPlatform.instance = platform;
    reader = FlutterReadium();
  });

  group('FlutterReadium singleton', () {
    test('returns the same instance on repeated calls', () {
      expect(FlutterReadium(), same(FlutterReadium()));
    });
  });

  group('setDefaultPreferences', () {
    test('stores preferences on the platform', () {
      final prefs = EPUBPreferences(fontSize: 150);
      reader.setDefaultPreferences(prefs);
      expect(platform.defaultPreferences, prefs);
    });
  });

  group('openPublication', () {
    test('returns a publication with the mock title', () async {
      final pub = await reader.openPublication('https://example.com/book.epub');
      expect(pub.metadata.title, 'Opened');
    });
  });

  group('loadPublication', () {
    test('returns a publication without side effects', () async {
      final pub = await reader.loadPublication('https://example.com/book.epub');
      expect(pub.metadata.title, 'Loaded');
    });
  });

  group('goToLocator', () {
    test('returns true on success', () async {
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
      );
      expect(await reader.goToLocator(locator), isTrue);
    });
  });

  group('goToProgression', () {
    test('returns true on success', () async {
      expect(await reader.goToProgression(0.5), isTrue);
    });
  });

  group('ttsGetAvailableVoices', () {
    test('returns a list (empty from mock)', () async {
      final voices = await reader.ttsGetAvailableVoices();
      expect(voices, isEmpty);
    });
  });

  group('searchInPublication', () {
    test('returns a list (empty from mock)', () async {
      final results = await reader.searchInPublication('whale');
      expect(results, isEmpty);
    });
  });

  group('onTextLocatorChanged stream', () {
    test('emits locators from the platform', () async {
      final locator = Locator(
        href: '/ch1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(progression: 0.5, totalProgression: 0.1),
      );

      final future = reader.onTextLocatorChanged.first;
      platform.emitLocator(locator);
      expect(await future, locator);
    });
  });

  group('onReaderStatusChanged stream', () {
    test('emits reader status from the platform', () async {
      final future = reader.onReaderStatusChanged.first;
      platform.emitStatus(ReadiumReaderStatus.ready);
      expect(await future, ReadiumReaderStatus.ready);
    });
  });

  group('onErrorEvent stream', () {
    test('emits errors from the platform', () async {
      final error = ReadiumError('something went wrong', code: 'ERR_42');
      final future = reader.onErrorEvent.first;
      platform.emitError(error);
      expect(await future, error);
    });
  });

  group('skipToNextTOC', () {
    test('throws when current href not in TOC', () async {
      final pub = Publication(
        links: [],
        metadata: Metadata(
          localizedTitle: LocalizedString.fromStrings({'en': 'Test'}),
        ),
        readingOrder: [],
        tableOfContents: [
          Link(href: '/ch1.xhtml'),
          Link(href: '/ch2.xhtml'),
        ],
      );
      await expectLater(
        () => reader.skipToNextTOC(
          publication: pub,
          currentTocHref: '/unknown.xhtml',
        ),
        throwsA(isA<ReadiumException>()),
      );
    });

    test('throws when already at last chapter', () async {
      final pub = Publication(
        links: [],
        metadata: Metadata(
          localizedTitle: LocalizedString.fromStrings({'en': 'Test'}),
        ),
        readingOrder: [],
        tableOfContents: [
          Link(href: '/ch1.xhtml'),
          Link(href: '/ch2.xhtml'),
        ],
      );
      await expectLater(
        () => reader.skipToNextTOC(
          publication: pub,
          currentTocHref: '/ch2.xhtml',
        ),
        throwsA(isA<ReadiumException>()),
      );
    });
  });

  group('toPhysicalPageIndex', () {
    test('throws when page not found', () async {
      final pub = Publication(
        links: [],
        metadata: Metadata(
          localizedTitle: LocalizedString.fromStrings({'en': 'Test'}),
        ),
        readingOrder: [],
      );
      await expectLater(
        () => reader.toPhysicalPageIndex('999', pub),
        throwsA(isA<ReadiumException>()),
      );
    });
  });
}
