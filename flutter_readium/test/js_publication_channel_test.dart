// Runs only in a browser: `flutter test --platform chrome test/js_publication_channel_test.dart`.
// `dart:js_interop` does not exist on the Dart VM, so `flutter test` without a platform skips this file.
@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter_readium/src/js_error.dart';
import 'package:flutter_readium/src/js_publication_channel.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_readium_reader.dart';

/// Every entry point that awaits a JS promise, each started so that its first JS call is [method].
final _asyncEntryPoints = <String, Future<Object?> Function()>{
  'openPublication': () => JsPublicationChannel().openPublication(
    'https://example.com/book',
    pubId: 'id',
    initialPreferences: '{}',
  ),
  'getPublication': () => JsPublicationChannel().getPublication('https://example.com/book'),
  'loadAsCurrentPublication': () => JsPublicationChannel().loadAsCurrentPublication('https://example.com/book'),
  'goTo': () => JsPublicationChannel.goToLocator('{}'),
  'ttsGetAvailableVoices': JsPublicationChannel.ttsGetAvailableVoices,
  'ttsEnable': () => JsPublicationChannel.ttsEnable('{}'),
  'audioEnable': () => JsPublicationChannel.audioEnable('{}'),
  'getResourceUrl': () => JsPublicationChannel.getResourceUrl('cover.jpg'),
};

/// Synchronous JS calls, which `_guardJsCall` wraps.
final _syncEntryPoints = <String, void Function()>{
  'goBackward': JsPublicationChannel.goBackward,
  'goForward': JsPublicationChannel.goForward,
  'play': JsPublicationChannel.playAudio,
  'pause': JsPublicationChannel.pauseAudio,
  'resume': JsPublicationChannel.resumeAudio,
  'stop': JsPublicationChannel.stopAudio,
  'next': JsPublicationChannel.nextAudio,
  'previous': JsPublicationChannel.previousAudio,
  'seekBy': () => JsPublicationChannel.seekBy(1),
  'goToProgression': () => JsPublicationChannel.goToProgression(0.5),
  'setNarrationSyncEnabled': () => JsPublicationChannel.setNarrationSyncEnabled(true),
  'setAudioPreferences': () => JsPublicationChannel.setAudioPreferences('{}'),
  'ttsSetVoice': () => JsPublicationChannel.ttsSetVoice('v1'),
  'ttsSetPreferences': () => JsPublicationChannel.ttsSetPreferences('{}'),
  'setDecorationStyle': () => JsPublicationChannel().setDecorationStyle(null, null),
  'applyDecorations': () => JsPublicationChannel().applyDecorations('group', '[]'),
};

Future<PlatformException> _caught(Future<Object?> Function() call) async {
  try {
    await call();
  } on PlatformException catch (e) {
    return e;
  }
  fail('expected a PlatformException');
}

void main() {
  setUpAll(FakeReadiumReader.install);
  setUp(FakeReadiumReader.reset);

  group('JS calls', () {
    test('openPublication passes URL, id, initial position, preferences and font declarations in order', () async {
      await JsPublicationChannel().openPublication(
        'https://example.com/book',
        pubId: 'urn:uuid:1',
        initialPreferences: '{"fontSize":1.2}',
        initialPositionJson: '{"href":"ch1.xhtml"}',
        fontFamilyDeclarationsJson: '[{"fontFamily":"X"}]',
      );

      expect(FakeReadiumReader.callsTo('openPublication').single.args, [
        'https://example.com/book',
        'urn:uuid:1',
        '{"href":"ch1.xhtml"}',
        '{"fontSize":1.2}',
        '[{"fontFamily":"X"}]',
      ]);
    });

    test('openPublication defaults the font declarations to an empty list and the position to null', () async {
      await JsPublicationChannel().openPublication('u', pubId: 'id', initialPreferences: '{}');

      final args = FakeReadiumReader.callsTo('openPublication').single.args;
      expect(args[2], isNull);
      expect(args[4], '[]');
    });

    test('setLogLevel and setAudioRecoveryPolicy forward their arguments', () {
      JsPublicationChannel.setLogLevel(LogLevel.error);
      JsPublicationChannel.setAudioRecoveryPolicy('{"maxAttempts":2}');

      expect(FakeReadiumReader.callsTo('setLogLevel').single.args, [LogLevel.error.index]);
      expect(FakeReadiumReader.callsTo('setAudioRecoveryPolicy').single.args, ['{"maxAttempts":2}']);
    });

    test('ttsEnable and audioEnable pass the optional start locator through', () async {
      await JsPublicationChannel.ttsEnable('{}', fromLocatorJson: '{"href":"a"}');
      await JsPublicationChannel.audioEnable('{}');

      expect(FakeReadiumReader.callsTo('ttsEnable').single.args, ['{}', '{"href":"a"}']);
      expect(FakeReadiumReader.callsTo('audioEnable').single.args, ['{}', null]);
    });

    test('getPublication and loadAsCurrentPublication return the manifest string', () async {
      FakeReadiumReader.returns('getPublication', '{"a":1}');
      FakeReadiumReader.returns('loadAsCurrentPublication', '{"b":2}');

      expect(await JsPublicationChannel().getPublication('u'), '{"a":1}');
      expect(await JsPublicationChannel().loadAsCurrentPublication('u'), '{"b":2}');
    });

    test('setEPUBPreferences forwards when the navigator is ready and skips when it is not', () async {
      await JsPublicationChannel().setEPUBPreferences('{"a":1}');
      FakeReadiumReader.setProperty('isNavigatorReady', false);
      await JsPublicationChannel().setEPUBPreferences('{"a":2}');

      expect(FakeReadiumReader.callsTo('setEPUBPreferences').map((c) => c.args.single), ['{"a":1}']);
    });

    test('closePublication never throws, even when JS does', () {
      FakeReadiumReader.failWith('closePublication', 'boom');

      JsPublicationChannel().closePublication();
    });
  });

  group('typed JS errors', () {
    test('keep the JS code and merge its details with the message', () async {
      FakeReadiumReader.failWith(
        'getResourceUrl',
        'no publication open',
        code: 'noPublication',
        details: {'href': 'x'},
      );

      final e = await _caught(() => JsPublicationChannel.getResourceUrl('x'));

      expect(e.code, 'noPublication');
      expect(e.message, contains('no publication open'));
      expect(e.details, containsPair('href', 'x'));
      expect(e.details, contains('message'));
    });

    test('without details still carry the message', () async {
      FakeReadiumReader.failWith('getResourceUrl', 'bad href', code: 'invalidArgument');

      final e = await _caught(() => JsPublicationChannel.getResourceUrl('x'));

      expect(e.code, 'invalidArgument');
      expect(e.details, {'message': e.message});
    });

    test('with an empty code fall back to the message heuristics', () async {
      FakeReadiumReader.failWith('getResourceUrl', 'HTTP status code 404', code: '');

      final e = await _caught(() => JsPublicationChannel.getResourceUrl('x'));

      expect(e.code, ReadiumErrorCode.notFound.name);
    });

    test('surface the JS stack in the message so call sites reach the logs', () async {
      FakeReadiumReader.failWith('getResourceUrl', 'distinctive failure');

      final e = await _caught(() => JsPublicationChannel.getResourceUrl('x'));

      expect(e.message, startsWith('distinctive failure'));
      expect(e.message!.split('\n').length, greaterThan(1), reason: 'message plus stack');
    });
  });

  group('untyped JS errors map by message', () {
    const statusCodes = {
      415: ReadiumErrorCode.formatNotSupported,
      404: ReadiumErrorCode.notFound,
      400: ReadiumErrorCode.readingError,
      403: ReadiumErrorCode.forbidden,
      500: ReadiumErrorCode.unavailable,
      401: ReadiumErrorCode.incorrectCredentials,
      418: ReadiumErrorCode.unknown,
    };
    for (final entry in statusCodes.entries) {
      test('HTTP status code ${entry.key} becomes ${entry.value.name} and keeps the status', () async {
        FakeReadiumReader.failWith('getPublication', 'Fetch failed: HTTP status code ${entry.key}');

        final e = await _caught(() => JsPublicationChannel().getPublication('u'));

        expect(e.code, entry.value.name);
        expect(e.details, containsPair('httpStatus', entry.key));
      });
    }

    test('"Scheme not supported" becomes unsupportedScheme, ignoring case', () async {
      FakeReadiumReader.failWith('getPublication', 'URL SCHEME NOT SUPPORTED: ftp');

      final e = await _caught(() => JsPublicationChannel().getPublication('ftp://x'));

      expect(e.code, ReadiumErrorCode.unsupportedScheme.name);
      expect(e.details, isNot(contains('httpStatus')));
    });

    test('an audio preparation timeout becomes audioStreamNetworkError', () async {
      FakeReadiumReader.failWith('audioEnable', 'Timed out preparing audio playback after 10s');

      final e = await _caught(() => JsPublicationChannel.audioEnable('{}'));

      expect(e.code, ReadiumErrorCode.audioStreamNetworkError.name);
    });

    test('a message with no known pattern becomes unknown', () async {
      FakeReadiumReader.failWith('getPublication', 'something odd');

      final e = await _caught(() => JsPublicationChannel().getPublication('u'));

      expect(e.code, ReadiumErrorCode.unknown.name);
    });
  });

  group('every JS entry point converts a failure to a PlatformException', () {
    for (final entry in _asyncEntryPoints.entries) {
      test('${entry.key} (async)', () async {
        FakeReadiumReader.failWith(entry.key, 'HTTP status code 403');

        final e = await _caught(entry.value);

        expect(e.code, ReadiumErrorCode.forbidden.name);
      });
    }

    for (final entry in _syncEntryPoints.entries) {
      test('${entry.key} (sync)', () {
        FakeReadiumReader.failWith(entry.key, 'boom', code: 'noPublication');

        expect(entry.value, throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'noPublication')));
      });
    }

    test('setEPUBPreferences', () async {
      FakeReadiumReader.failWith('setEPUBPreferences', 'boom', code: 'invalidArgument');

      final e = await _caught(() => JsPublicationChannel().setEPUBPreferences('{}'));

      expect(e.code, 'invalidArgument');
    });
  });

  group('describeJsError', () {
    test('falls back to toString for a Dart object', () {
      expect(describeJsError('plain'), 'plain');
      expect(describeJsError(StateError('x')), contains('x'));
    });
  });
}
