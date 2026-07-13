import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadiumErrorCode.fromWire', () {
    test('parses every known wire string to its enum member', () {
      const expected = {
        // Opening errors, shared by awaited failures and event payloads.
        'formatNotSupported': ReadiumErrorCode.formatNotSupported,
        'unsupportedScheme': ReadiumErrorCode.unsupportedScheme,
        'readingError': ReadiumErrorCode.readingError,
        'notFound': ReadiumErrorCode.notFound,
        'forbidden': ReadiumErrorCode.forbidden,
        'unavailable': ReadiumErrorCode.unavailable,
        'incorrectCredentials': ReadiumErrorCode.incorrectCredentials,
        // Audio streaming (iOS + Android + web parity codes).
        'AudioStreamRetry': ReadiumErrorCode.audioStreamRetry,
        'AudioStreamAuthError': ReadiumErrorCode.audioStreamAuthError,
        'AudioStreamHTTPError': ReadiumErrorCode.audioStreamHttpError,
        'AudioStreamNetworkError': ReadiumErrorCode.audioStreamNetworkError,
        'AudioStreamError': ReadiumErrorCode.audioStreamError,
        // TTS / navigator / resource-loading (iOS-only today).
        'TTSUtteranceFailed': ReadiumErrorCode.ttsUtteranceFailed,
        'VoiceNotFound': ReadiumErrorCode.voiceNotFound,
        'TTSError': ReadiumErrorCode.ttsError,
        'SearchError': ReadiumErrorCode.searchError,
        'NoPublication': ReadiumErrorCode.noPublicationOpened,
        'ResourceReadError': ReadiumErrorCode.resourceReadError,
      };

      for (final entry in expected.entries) {
        expect(
          ReadiumErrorCode.fromWire(entry.key),
          entry.value,
          reason: 'wire code "${entry.key}" should map to ${entry.value}',
        );
      }
    });

    test('parsing is case-insensitive', () {
      expect(ReadiumErrorCode.fromWire('audiostreamretry'), ReadiumErrorCode.audioStreamRetry);
      expect(ReadiumErrorCode.fromWire('AUDIOSTREAMERROR'), ReadiumErrorCode.audioStreamError);
      expect(ReadiumErrorCode.fromWire('NOTFOUND'), ReadiumErrorCode.notFound);
      expect(ReadiumErrorCode.fromWire('voicenotfound'), ReadiumErrorCode.voiceNotFound);
      expect(ReadiumErrorCode.fromWire('RESOURCEREADERROR'), ReadiumErrorCode.resourceReadError);
    });

    test('unknown, null, and empty codes fall back to unknown without throwing', () {
      expect(ReadiumErrorCode.fromWire('SomeRandomThrowableClassName'), ReadiumErrorCode.unknown);
      expect(ReadiumErrorCode.fromWire(null), ReadiumErrorCode.unknown);
      expect(ReadiumErrorCode.fromWire(''), ReadiumErrorCode.unknown);
    });
  });

  group('ReadiumErrorCode.isInformational / isFatal', () {
    test('audioStreamRetry is the only informational code', () {
      for (final code in ReadiumErrorCode.values) {
        if (code == ReadiumErrorCode.audioStreamRetry) {
          expect(code.isInformational, isTrue);
        } else {
          expect(code.isInformational, isFalse, reason: '$code should not be informational');
        }
      }
    });

    test('isFatal and isInformational are exact complements for every member', () {
      for (final code in ReadiumErrorCode.values) {
        expect(code.isFatal, !code.isInformational, reason: '$code: isFatal/isInformational must be complementary');
      }
    });
  });

  group('ReadiumErrorCode.category', () {
    test('maps audio streaming codes to ReadiumErrorCategory.audioStream', () {
      for (final code in [
        ReadiumErrorCode.audioStreamRetry,
        ReadiumErrorCode.audioStreamAuthError,
        ReadiumErrorCode.audioStreamHttpError,
        ReadiumErrorCode.audioStreamNetworkError,
        ReadiumErrorCode.audioStreamError,
      ]) {
        expect(code.category, ReadiumErrorCategory.audioStream);
      }
    });

    test('maps TTS codes to ReadiumErrorCategory.tts', () {
      expect(ReadiumErrorCode.ttsUtteranceFailed.category, ReadiumErrorCategory.tts);
      expect(ReadiumErrorCode.voiceNotFound.category, ReadiumErrorCategory.tts);
      expect(ReadiumErrorCode.ttsError.category, ReadiumErrorCategory.tts);
    });

    test('maps navigator/resource codes to ReadiumErrorCategory.navigator', () {
      expect(ReadiumErrorCode.searchError.category, ReadiumErrorCategory.navigator);
      expect(ReadiumErrorCode.noPublicationOpened.category, ReadiumErrorCategory.navigator);
      expect(ReadiumErrorCode.resourceReadError.category, ReadiumErrorCategory.navigator);
    });

    test('maps opening-error codes to ReadiumErrorCategory.opening', () {
      for (final code in [
        ReadiumErrorCode.formatNotSupported,
        ReadiumErrorCode.unsupportedScheme,
        ReadiumErrorCode.readingError,
        ReadiumErrorCode.notFound,
        ReadiumErrorCode.forbidden,
        ReadiumErrorCode.unavailable,
        ReadiumErrorCode.incorrectCredentials,
      ]) {
        expect(code.category, ReadiumErrorCategory.opening);
      }
    });

    test('maps unknown to ReadiumErrorCategory.unknown', () {
      expect(ReadiumErrorCode.unknown.category, ReadiumErrorCategory.unknown);
    });
  });

  group('ReadiumError.fromJson', () {
    test('populates codeEnum from the raw code without dropping the raw string', () {
      final error = ReadiumError.fromJson({
        'message': 'stream retry',
        'code': 'AudioStreamRetry',
      });
      expect(error.code, 'AudioStreamRetry');
      expect(error.codeEnum, ReadiumErrorCode.audioStreamRetry);
    });

    test('unrecognised raw code still keeps the raw string, codeEnum falls back to unknown', () {
      final error = ReadiumError.fromJson({
        'message': 'boom',
        'code': 'SomeThrowableClassName',
      });
      expect(error.code, 'SomeThrowableClassName');
      expect(error.codeEnum, ReadiumErrorCode.unknown);
    });

    test('missing code: raw code is null, codeEnum is unknown', () {
      final error = ReadiumError.fromJson({'message': 'boom'});
      expect(error.code, isNull);
      expect(error.codeEnum, ReadiumErrorCode.unknown);
    });
  });
}
