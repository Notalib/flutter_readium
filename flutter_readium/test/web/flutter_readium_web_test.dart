// Runs only in a browser: `flutter test --platform chrome test/web`.
// `dart:js_interop` does not exist on the Dart VM, so `flutter test` without a platform skips this file.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_readium/src/flutter_readium_web.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_readium_reader.dart';

const _audiobookProfile = 'https://readium.org/webpub-manifest/profiles/audiobook';

String _manifest({Object? title = 'Test Book', Object? sortAs, List<String>? conformsTo}) => jsonEncode({
  'metadata': {
    'title': title,
    'sortAs': ?sortAs,
    'conformsTo': ?conformsTo,
  },
  'links': <Object>[],
  'readingOrder': [
    {'href': 'ch1.xhtml', 'type': 'application/xhtml+xml'},
  ],
});

const _locator = Locator(
  href: 'ch1.xhtml',
  type: 'application/xhtml+xml',
  locations: Locations(progression: 0.25, position: 3),
);

Map<String, dynamic> _decodeArg(FakeCall call, int index) =>
    jsonDecode(call.args[index]! as String) as Map<String, dynamic>;

void main() {
  late FlutterReadiumWebPlugin plugin;

  setUpAll(FakeReadiumReader.install);

  setUp(() {
    FakeReadiumReader.reset();
    plugin = FlutterReadiumWebPlugin();
  });

  group('configuration', () {
    test('setLogLevel forwards the level index to JS and updates the Dart logger', () async {
      await plugin.setLogLevel(LogLevel.warn);

      expect(FakeReadiumReader.callsTo('setLogLevel').single.args, [LogLevel.warn.index]);
    });

    test('setAudioRecoveryPolicy sends the policy as a JSON string', () async {
      const policy = AudioRecoveryPolicy(maxAttempts: 5, backoffBaseSeconds: 2.0);

      await plugin.setAudioRecoveryPolicy(policy);

      final call = FakeReadiumReader.callsTo('setAudioRecoveryPolicy').single;
      expect(call.args.single, isA<String>());
      expect(AudioRecoveryPolicy.fromJson(_decodeArg(call, 0)), policy);
    });

    test('setCustomHeaders is a no-op because the browser owns HTTP headers', () async {
      await plugin.setCustomHeaders({'Authorization': 'Bearer x'});

      expect(FakeReadiumReader.calls, isEmpty);
    });

    test('setDefaultPreferences stores the preferences without calling JS', () {
      const preferences = EPUBPreferences(fontSize: 1.2);

      plugin.setDefaultPreferences(preferences);

      expect(plugin.defaultPreferences, preferences);
      expect(FakeReadiumReader.calls, isEmpty);
    });
  });

  group('loadPublication', () {
    test('parses the manifest JSON from JS without making it the current publication', () async {
      FakeReadiumReader.returns('getPublication', _manifest());

      final publication = await plugin.loadPublication('https://example.com/book/manifest.json');

      expect(publication.metadata.title, 'Test Book');
      expect(FakeReadiumReader.calls.map((c) => c.method), ['getPublication']);
      expect(FakeReadiumReader.calls.single.args, ['https://example.com/book/manifest.json']);
    });

    test('rewrites the literal "undefined" language key to "und"', () async {
      FakeReadiumReader.returns('getPublication', _manifest(title: {'undefined': 'Untitled'}));

      final publication = await plugin.loadPublication('https://example.com/m.json');

      expect(publication.metadata.localizedTitle.translations.keys, ['und']);
      expect(publication.metadata.title, 'Untitled');
    });

    test('flattens a sortAs LocalizedString map to its first value', () async {
      FakeReadiumReader.returns('getPublication', _manifest(sortAs: {'en': 'Book, Test'}));

      final publication = await plugin.loadPublication('https://example.com/m.json');

      expect(publication.metadata.sortAs, 'Book, Test');
    });

    test('drops an empty or non-string sortAs (the model then reports an empty string)', () async {
      FakeReadiumReader.returns('getPublication', _manifest(sortAs: <String, String>{}));
      expect((await plugin.loadPublication('https://example.com/m.json')).metadata.sortAs, isEmpty);

      FakeReadiumReader.returns('getPublication', _manifest(sortAs: 42));
      expect((await plugin.loadPublication('https://example.com/m.json')).metadata.sortAs, isEmpty);
    });

    test('maps a typed JS failure to a ReadiumException carrying the JS code', () async {
      FakeReadiumReader.failWith('getPublication', 'no such book', code: 'notFound', details: {'href': 'm.json'});

      await expectLater(
        plugin.loadPublication('https://example.com/m.json'),
        throwsA(
          isA<ReadiumException>()
              .having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.notFound)
              .having((e) => e.details?['href'], 'details.href', 'm.json'),
        ),
      );
    });

    test('maps an untyped HTTP failure by status code', () async {
      FakeReadiumReader.failWith('getPublication', 'Request failed with HTTP status code 404');

      await expectLater(
        plugin.loadPublication('https://example.com/m.json'),
        throwsA(
          isA<ReadiumException>()
              .having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.notFound)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
    });

    test('wraps a manifest that is not valid JSON in a ReadiumException', () async {
      FakeReadiumReader.returns('getPublication', 'not json');

      await expectLater(plugin.loadPublication('https://example.com/m.json'), throwsA(isA<ReadiumException>()));
    });

    test('rejects a manifest without metadata', () async {
      FakeReadiumReader.returns('getPublication', jsonEncode({'links': <Object>[], 'readingOrder': <Object>[]}));

      await expectLater(plugin.loadPublication('https://example.com/m.json'), throwsA(isA<ReadiumException>()));
    });
  });

  group('openPublication', () {
    test('makes an EPUB the current publication without opening it in the JS navigator', () async {
      FakeReadiumReader.returns('loadAsCurrentPublication', _manifest());

      final publication = await plugin.openPublication('https://example.com/book.epub');

      expect(publication.metadata.title, 'Test Book');
      expect(FakeReadiumReader.calls.map((c) => c.method), ['loadAsCurrentPublication']);
    });

    test('opens an audiobook in the JS navigator with the default preferences as JSON', () async {
      FakeReadiumReader.returns('loadAsCurrentPublication', _manifest(conformsTo: [_audiobookProfile]));
      plugin.setDefaultPreferences(const EPUBPreferences(fontSize: 1.5));

      await plugin.openPublication('https://example.com/audio/manifest.json');

      final open = FakeReadiumReader.callsTo('openPublication').single;
      expect(open.args[0], 'https://example.com/audio/manifest.json');
      expect(open.args[2], isNull, reason: 'no initial position');
      expect(_decodeArg(open, 3)['fontSize'], 1.5);
      expect(open.args[4], '[]');
    });

    test('maps a failure opening an audiobook to a ReadiumException', () async {
      FakeReadiumReader.returns('loadAsCurrentPublication', _manifest(conformsTo: [_audiobookProfile]));
      FakeReadiumReader.failWith('openPublication', 'Scheme not supported');

      await expectLater(
        plugin.openPublication('ftp://example.com/audio/manifest.json'),
        throwsA(isA<ReadiumException>().having((e) => e.codeEnum, 'codeEnum', ReadiumErrorCode.unsupportedScheme)),
      );
    });

    test('registers the JS callbacks that feed the player-state, reader-status and error streams', () async {
      FakeReadiumReader.returns('loadAsCurrentPublication', _manifest());
      await plugin.openPublication('https://example.com/book.epub');

      // `.first` subscribes at once; the streams are broadcast and would drop an event with no listener.
      final status = plugin.onReaderStatusChanged.first;
      FakeReadiumReader.invokeGlobalCallback('updateReaderStatus', 'ready');
      expect(await status, ReadiumReaderStatus.ready);

      final timebased = plugin.onTimebasedPlayerStateChanged.first;
      FakeReadiumReader.invokeGlobalCallback(
        'updateTimebasedPlayerState',
        jsonEncode({'state': 'playing', 'currentOffset': 1500}),
      );
      final state = await timebased;
      expect(state.state, TimebasedState.playing);
      expect(state.currentOffset, const Duration(milliseconds: 1500));

      final error = plugin.onErrorEvent.first;
      FakeReadiumReader.invokeGlobalCallback(
        'onErrorCallback',
        jsonEncode({'message': 'stalled', 'code': 'AudioStreamNetworkError'}),
      );
      expect((await error).codeEnum, ReadiumErrorCode.audioStreamNetworkError);
    });

    test('ignores an unknown reader status string', () async {
      FakeReadiumReader.returns('loadAsCurrentPublication', _manifest());
      await plugin.openPublication('https://example.com/book.epub');
      final received = <ReadiumReaderStatus>[];
      final subscription = plugin.onReaderStatusChanged.listen(received.add);

      FakeReadiumReader.invokeGlobalCallback('updateReaderStatus', 'bogus');
      FakeReadiumReader.invokeGlobalCallback('updateReaderStatus', 'loading');
      await pumpEventQueue();
      await subscription.cancel();

      expect(received, [ReadiumReaderStatus.loading]);
    });
  });

  group('lifecycle and navigation', () {
    test('closePublication calls JS and swallows a JS failure', () async {
      await plugin.closePublication();
      expect(FakeReadiumReader.callsTo('closePublication'), hasLength(1));

      FakeReadiumReader.failWith('closePublication', 'already closed');
      await plugin.closePublication();
    });

    test('goBackward and goForward call JS', () async {
      await plugin.goBackward();
      await plugin.goForward();

      expect(FakeReadiumReader.calls.map((c) => c.method), ['goBackward', 'goForward']);
    });

    test('goToLocator sends the locator as a JSON string and reports success', () async {
      final result = await plugin.goToLocator(_locator);

      expect(result, isTrue);
      final call = FakeReadiumReader.callsTo('goTo').single;
      expect(call.args.single, isA<String>(), reason: 'Readium-owned objects cross the bridge as JSON strings');
      expect(Locator.fromJson(_decodeArg(call, 0))!.toJson(), _locator.toJson());
    });

    test('goToLocator maps a typed JS failure to a ReadiumException', () async {
      FakeReadiumReader.failWith('goTo', 'bad locator', code: 'invalidArgument', details: {'href': 'x.xhtml'});

      await expectLater(
        plugin.goToLocator(_locator),
        throwsA(
          isA<ReadiumException>()
              .having((e) => e.code, 'code', 'invalidArgument')
              .having((e) => e.details?['href'], 'details.href', 'x.xhtml'),
        ),
      );
    });

    test('goToProgression returns the JS result', () async {
      FakeReadiumReader.returns('goToProgression', false);

      expect(await plugin.goToProgression(0.5), isFalse);
      expect(FakeReadiumReader.callsTo('goToProgression').single.args, [0.5]);
    });
  });

  group('preferences and decorations', () {
    test('setEPUBPreferences stores the preferences and sends them as a JSON string', () async {
      const preferences = EPUBPreferences(fontSize: 1.25);

      await plugin.setEPUBPreferences(preferences);

      expect(plugin.defaultPreferences, preferences);
      final call = FakeReadiumReader.callsTo('setEPUBPreferences').single;
      expect(EPUBPreferences.fromJson(_decodeArg(call, 0)), preferences);
    });

    test('setEPUBPreferences skips JS while the navigator is not ready but still stores them', () async {
      FakeReadiumReader.setProperty('isNavigatorReady', false);
      const preferences = EPUBPreferences(fontSize: 1.25);

      await plugin.setEPUBPreferences(preferences);

      expect(plugin.defaultPreferences, preferences);
      expect(FakeReadiumReader.callsTo('setEPUBPreferences'), isEmpty);
    });

    test('setPDFPreferences is unsupported on web and does not call JS', () async {
      await plugin.setPDFPreferences(const PDFPreferences());

      expect(FakeReadiumReader.calls, isEmpty);
    });

    test('applyDecorations sends the group id and one JSON array string', () async {
      final decorations = [
        ReaderDecoration(
          id: 'hit-1',
          locator: _locator,
          style: const ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Color(0xFFFFEB3B), isActive: true),
        ),
        ReaderDecoration(
          id: 'hit-2',
          locator: _locator,
          style: const ReaderDecorationStyle(style: DecorationStyle.underline),
        ),
      ];

      await plugin.applyDecorations('search', decorations);

      final call = FakeReadiumReader.callsTo('applyDecorations').single;
      expect(call.args[0], 'search');
      expect(call.args[1], isA<String>());
      final sent = (jsonDecode(call.args[1]! as String) as List<dynamic>).cast<Map<String, dynamic>>();
      expect(sent.map((d) => d['id']), ['hit-1', 'hit-2']);
      expect(Locator.fromJson(sent.first['locator'] as Map<String, dynamic>)!.toJson(), _locator.toJson());
      expect(sent.first['style'], containsPair('style', 'highlight'));
      expect(sent.first['style'], containsPair('isActive', true));
      expect(sent.last['style'], isNot(contains('tint')));
    });

    test('applyDecorations skips JS while the navigator is not ready', () async {
      FakeReadiumReader.setProperty('isNavigatorReady', false);

      await plugin.applyDecorations('search', const []);

      expect(FakeReadiumReader.callsTo('applyDecorations'), isEmpty);
    });

    test('setDecorationStyle sends each style as JSON, and null as null', () async {
      await plugin.setDecorationStyle(
        const ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Color(0xFF00FF00)),
        null,
      );

      final call = FakeReadiumReader.callsTo('setDecorationStyle').single;
      expect(_decodeArg(call, 0), containsPair('style', 'highlight'));
      expect(call.args[1], isNull);
    });
  });

  group('playback', () {
    test('play, pause, resume, stop, next and previous each call the matching JS method', () async {
      await plugin.play(null);
      await plugin.pause();
      await plugin.resume();
      await plugin.stop();
      await plugin.next();
      await plugin.previous();

      expect(FakeReadiumReader.calls.map((c) => c.method), ['play', 'pause', 'resume', 'stop', 'next', 'previous']);
    });

    test('play with no locator sends null, with a locator sends it as JSON', () async {
      await plugin.play(null);
      await plugin.play(_locator);

      final plays = FakeReadiumReader.callsTo('play');
      expect(plays.first.args.single, isNull);
      expect(Locator.fromJson(_decodeArg(plays.last, 0))!.toJson(), _locator.toJson());
    });

    test('setNarrationSyncEnabled forwards the flag', () async {
      await plugin.setNarrationSyncEnabled(true);

      expect(FakeReadiumReader.callsTo('setNarrationSyncEnabled').single.args, [true]);
    });
  });

  group('TTS', () {
    test('ttsEnable sends preferences as JSON, or an empty object when null', () async {
      await plugin.ttsEnable(const TTSPreferences(speed: 1.5));
      await plugin.ttsEnable(null);

      final enables = FakeReadiumReader.callsTo('ttsEnable');
      expect(_decodeArg(enables.first, 0), containsPair('speed', 1.5));
      expect(_decodeArg(enables.last, 0), isEmpty);
    });

    test('ttsGetAvailableVoices parses the voices JSON and skips non-object entries', () async {
      FakeReadiumReader.returns(
        'ttsGetAvailableVoices',
        jsonEncode([
          {'identifier': 'v1', 'name': 'Voice One', 'language': 'da-DK', 'networkRequired': false, 'gender': 'female'},
          'garbage',
        ]),
      );

      final voices = await plugin.ttsGetAvailableVoices();

      expect(voices.map((v) => v.identifier), ['v1']);
      expect(voices.single.language, 'da-DK');
    });

    test('ttsSetVoice forwards the identifier and language', () async {
      await plugin.ttsSetVoice('v1', 'da');

      expect(FakeReadiumReader.callsTo('ttsSetVoice').single.args, ['v1', 'da']);
    });

    test('ttsSetPreferences sends preferences as JSON', () async {
      await plugin.ttsSetPreferences(const TTSPreferences(pitch: 0.8));

      expect(_decodeArg(FakeReadiumReader.callsTo('ttsSetPreferences').single, 0), containsPair('pitch', 0.8));
    });
  });

  group('audiobook', () {
    test('audioEnable sends preferences and the start locator as JSON strings', () async {
      await plugin.audioEnable(prefs: const AudioPreferences(speed: 1.25), fromLocator: _locator);

      final call = FakeReadiumReader.callsTo('audioEnable').single;
      expect(_decodeArg(call, 0), containsPair('speed', 1.25));
      expect(Locator.fromJson(_decodeArg(call, 1))!.toJson(), _locator.toJson());
    });

    test('audioEnable without arguments sends an empty object and no locator', () async {
      await plugin.audioEnable();

      final call = FakeReadiumReader.callsTo('audioEnable').single;
      expect(_decodeArg(call, 0), isEmpty);
      expect(call.args[1], isNull);
    });

    test('audioSetPreferences sends preferences as JSON', () async {
      await plugin.audioSetPreferences(const AudioPreferences(volume: 0.5));

      expect(_decodeArg(FakeReadiumReader.callsTo('setAudioPreferences').single, 0), containsPair('volume', 0.5));
    });

    test('audioSeekBy converts the offset to fractional seconds', () async {
      await plugin.audioSeekBy(const Duration(milliseconds: -2500));

      expect(FakeReadiumReader.callsTo('seekBy').single.args, [-2.5]);
    });
  });

  group('getResourceUrl', () {
    test('returns the URL from JS', () async {
      FakeReadiumReader.returns('getResourceUrl', 'blob:http://localhost/abc');

      expect(await plugin.getResourceUrl('cover.jpg'), 'blob:http://localhost/abc');
      expect(FakeReadiumReader.callsTo('getResourceUrl').single.args, ['cover.jpg']);
    });
  });

  group('unsupported on web', () {
    test('searchInPublication, setCssInjections and setJavaScriptInjections throw UnimplementedError', () {
      expect(() => plugin.searchInPublication('word'), throwsUnimplementedError);
      expect(() => plugin.setCssInjections(const []), throwsUnimplementedError);
      expect(() => plugin.setJavaScriptInjections(const []), throwsUnimplementedError);
    });
  });

  group('event streams', () {
    test('static add* helpers feed the matching broadcast streams', () async {
      final locator = plugin.onTextLocatorChanged.first;
      FlutterReadiumWebPlugin.addTextLocatorUpdate(_locator);
      expect(await locator, _locator);

      final sync = plugin.onNarrationSyncChanged.first;
      FlutterReadiumWebPlugin.addNarrationSyncUpdate(true);
      expect(await sync, isTrue);

      final error = ReadiumError('boom', code: 'unknown');
      final errorEvent = plugin.onErrorEvent.first;
      FlutterReadiumWebPlugin.addErrorEvent(error);
      expect(await errorEvent, error);
    });

    test('streams are broadcast, so every listener sees an event', () async {
      final first = plugin.onReaderStatusChanged.first;
      final second = plugin.onReaderStatusChanged.first;

      FlutterReadiumWebPlugin.addReaderStatusUpdate(ReadiumReaderStatus.closed);

      expect(await first, ReadiumReaderStatus.closed);
      expect(await second, ReadiumReaderStatus.closed);
    });
  });
}
