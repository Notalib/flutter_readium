import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadiumErrorCode.fromWire', () {
    test('parses every known wire string to its enum member', () {
      const expected = {
        // Opening errors (OpeningReadiumExceptionType wire vocabulary,
        // also emitted by Android's PublicationError.ReadiumExceptionType).
        'formatNotSupported': ReadiumErrorCode.formatNotSupported,
        'unsupportedScheme': ReadiumErrorCode.unsupportedScheme,
        'readingError': ReadiumErrorCode.readingError,
        'notFound': ReadiumErrorCode.notFound,
        'forbidden': ReadiumErrorCode.forbidden,
        'unavailable': ReadiumErrorCode.unavailable,
        'incorrectCredentials': ReadiumErrorCode.incorrectCredentials,
        // Audio streaming (iOS + Android + web parity codes).
        'AudioStreamRetry': ReadiumErrorCode.audioStreamRetry,
        'AudioStreamFailed': ReadiumErrorCode.audioStreamFailed,
        'AudioStreamAuthError': ReadiumErrorCode.audioStreamAuthError,
        'AudioStreamHTTPError': ReadiumErrorCode.audioStreamHttpError,
        'AudioStreamNetworkError': ReadiumErrorCode.audioStreamNetworkError,
        'AudioStreamRangeNotSupported': ReadiumErrorCode.audioStreamRangeNotSupported,
        'AudioStreamFileError': ReadiumErrorCode.audioStreamFileError,
        'AudioStreamError': ReadiumErrorCode.audioStreamError,
        // TTS / navigator / resource-loading (iOS-only today).
        'TimeBasedNavigatorError': ReadiumErrorCode.timeBasedNavigatorError,
        'TTSUtteranceFailed': ReadiumErrorCode.ttsUtteranceFailed,
        'DidFailToLoadResource': ReadiumErrorCode.didFailToLoadResource,
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
      expect(ReadiumErrorCode.fromWire('AUDIOSTREAMFAILED'), ReadiumErrorCode.audioStreamFailed);
      expect(ReadiumErrorCode.fromWire('NOTFOUND'), ReadiumErrorCode.notFound);
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
        ReadiumErrorCode.audioStreamFailed,
        ReadiumErrorCode.audioStreamAuthError,
        ReadiumErrorCode.audioStreamHttpError,
        ReadiumErrorCode.audioStreamNetworkError,
        ReadiumErrorCode.audioStreamFileError,
        ReadiumErrorCode.audioStreamError,
      ]) {
        expect(code.category, ReadiumErrorCategory.audioStream);
      }
    });

    test('maps TTS codes to ReadiumErrorCategory.tts', () {
      expect(ReadiumErrorCode.ttsUtteranceFailed.category, ReadiumErrorCategory.tts);
    });

    test('maps navigator/resource codes to ReadiumErrorCategory.navigator', () {
      expect(ReadiumErrorCode.timeBasedNavigatorError.category, ReadiumErrorCategory.navigator);
      expect(ReadiumErrorCode.didFailToLoadResource.category, ReadiumErrorCategory.navigator);
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
