import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Mock platform
// ---------------------------------------------------------------------------

class MockFlutterReadiumPlatform with MockPlatformInterfaceMixin implements FlutterReadiumPlatform {
  @override
  ReadiumReaderWidgetInterface? currentReaderWidget;

  @override
  EPUBPreferences? defaultPreferences;

  final _textLocatorController = StreamController<Locator>.broadcast();
  final _statusController = StreamController<ReadiumReaderStatus>.broadcast();
  final _timebasedController = StreamController<ReadiumTimebasedState>.broadcast();
  final _externalPlaybackCommandController = StreamController<ReadiumExternalPlaybackCommand>.broadcast();
  final _errorController = StreamController<ReadiumError>.broadcast();
  final _narrationSyncController = StreamController<bool>.broadcast();

  String? methodToThrow;
  Object? errorToThrow;

  // Helper to simulate throwing an error for a specific method.
  Future<T> _maybeThrow<T>(String method, T value) async {
    if (methodToThrow == method && errorToThrow != null) {
      throw errorToThrow!;
    }
    return value;
  }

  @override
  Stream<Locator> get onTextLocatorChanged => _textLocatorController.stream;

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _statusController.stream;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => _timebasedController.stream;

  @override
  Stream<ReadiumExternalPlaybackCommand> get onExternalPlaybackCommand => _externalPlaybackCommandController.stream;

  @override
  Stream<ReadiumError> get onErrorEvent => _errorController.stream;

  @override
  Stream<bool> get onNarrationSyncChanged => _narrationSyncController.stream;

  @override
  Future<void> setNarrationSyncEnabled(bool enabled) async {}

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
  Future<Publication> loadPublication(String pubUrl) async => _maybeThrow('loadPublication', _pub('Loaded'));

  @override
  Future<Publication> openPublication(String pubUrl) async => _maybeThrow('openPublication', _pub('Opened'));

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
  }) async {
    await _maybeThrow('audioEnable', null);
  }

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) async {}

  @override
  Future<void> audioSeekBy(Duration offset) async {}

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {}

  @override
  Future<void> setLogLevel(LogLevel level) async {}

  AudioRecoveryPolicy? lastAudioRecoveryPolicy;

  @override
  Future<void> setAudioRecoveryPolicy(AudioRecoveryPolicy policy) async {
    lastAudioRecoveryPolicy = policy;
  }

  @override
  Future<String> getResourceUrl(String href) async => _maybeThrow('getResourceUrl', 'file:///tmp/$href');

  @override
  Future<List<TextSearchResult>> searchInPublication(String searchKey) async => [];

  void emitLocator(Locator l) => _textLocatorController.add(l);
  void emitStatus(ReadiumReaderStatus s) => _statusController.add(s);
  void emitExternalPlaybackCommand(ReadiumExternalPlaybackCommand command) =>
      _externalPlaybackCommandController.add(command);
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
      final prefs = EPUBPreferences(fontSize: 1.5);
      reader.setDefaultPreferences(prefs);
      expect(platform.defaultPreferences, prefs);
    });
  });

  group('setAudioRecoveryPolicy', () {
    test('delegates the policy to the platform', () async {
      const policy = AudioRecoveryPolicy(maxAttempts: 5, backoffBaseSeconds: 0.5);
      await reader.setAudioRecoveryPolicy(policy);
      expect(platform.lastAudioRecoveryPolicy, policy);
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

    test('maps platform domain failures to ReadiumException', () async {
      platform
        ..methodToThrow = 'loadPublication'
        ..errorToThrow = PlatformException(
          code: 'notFound',
          message: 'Publication not found',
          details: {'href': '/missing.epub', 'httpStatus': 404},
        );

      await expectLater(
        () => reader.loadPublication('https://example.com/missing.epub'),
        throwsA(
          isA<ReadiumException>()
              .having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.notFound)
              .having((e) => e.href, 'href', '/missing.epub')
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
    });
  });

  group('audioEnable', () {
    test('maps platform domain failures to ReadiumException', () async {
      platform
        ..methodToThrow = 'audioEnable'
        ..errorToThrow = PlatformException(
          code: 'AudioStreamNetworkError',
          message: 'Timed out preparing audio playback',
          details: {'href': '/track.mp3'},
        );

      await expectLater(
        () => reader.audioEnable(),
        throwsA(
          isA<ReadiumException>()
              .having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.audioStreamNetworkError)
              .having((e) => e.href, 'href', '/track.mp3'),
        ),
      );
    });

    test('leaves InvalidArgument platform misuse as PlatformException', () async {
      platform
        ..methodToThrow = 'audioEnable'
        ..errorToThrow = PlatformException(
          code: 'InvalidArgument',
          message: 'bad args',
        );

      await expectLater(
        () => reader.audioEnable(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'InvalidArgument')),
      );
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

  group('onExternalPlaybackCommand stream', () {
    test('emits commands from the platform', () async {
      const command = ReadiumExternalPlaybackCommand(
        action: ExternalPlaybackCommandAction.seekForward,
      );
      final future = reader.onExternalPlaybackCommand.first;

      platform.emitExternalPlaybackCommand(command);

      expect(await future, same(command));
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

  group('ReadiumResourceImageProvider', () {
    test('converts platform resource-load failures to ReadiumException', () async {
      platform
        ..methodToThrow = 'getResourceUrl'
        ..errorToThrow = PlatformException(
          code: 'notFound',
          message: 'Resource not found',
          details: {'href': 'images/cover.png'},
        );

      final provider = ReadiumResourceImageProvider('images/cover.png', platform);
      final stream = provider.resolve(ImageConfiguration.empty);

      final errorCompleter = Completer<Object>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, synchronousCall) {},
        onError: (error, stackTrace) {
          errorCompleter.complete(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final error = await errorCompleter.future;
      expect(
        error,
        isA<ReadiumException>().having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.notFound),
      );
    });
  });
}
