/// Coarse grouping for [ReadiumErrorCode], mirroring the producer surfaces
/// documented in `docs/api-reference/error-codes.md`.
enum ReadiumErrorCategory {
  /// Audio streaming playback/recovery (iOS/Android/web `AudioStream*`).
  audioStream,

  /// Text-to-speech playback.
  tts,

  /// Time-based navigator / resource-loading failures not specific to audio
  /// streaming or TTS.
  navigator,

  /// Publication-opening failures, used by both the method-call and
  /// event-channel paths.
  opening,

  /// No known category — see [ReadiumErrorCode.unknown].
  unknown,
}

/// Typed vocabulary for the wire `code` string carried by [ReadiumError] and
/// [ReadiumException].
///
/// This enum only classifies known codes for client convenience — it never
/// replaces the raw `code` string field, which remains the source of truth.
/// Parsing never throws: an unrecognised or missing wire code maps to
/// [unknown].
///
/// See `docs/api-reference/error-codes.md` for the full vocabulary table
/// (which platforms emit which code, meaning, fatal/informational, category).
enum ReadiumErrorCode {
  // Opening errors — shared cross-platform wire vocabulary.
  formatNotSupported,
  unsupportedScheme,
  readingError,
  notFound,
  forbidden,
  unavailable,
  incorrectCredentials,

  // Audio streaming (iOS + Android + web parity codes).
  audioStreamRetry,
  audioStreamFailed,
  audioStreamAuthError,
  audioStreamHttpError,
  audioStreamNetworkError,
  audioStreamRangeNotSupported,
  audioStreamFileError,
  audioStreamError,

  // TTS.
  ttsUtteranceFailed,

  // Time-based navigator / resource loading (iOS-only today).
  timeBasedNavigatorError,
  didFailToLoadResource,

  /// Fallback for unrecognised, unmapped, or missing wire codes (e.g.
  /// Android's `Throwable::class.simpleName` fallback, which is not an
  /// enumerable vocabulary).
  unknown;

  /// Wire strings recognised for this member. Matching is case-insensitive
  /// via [fromWire].
  static const Map<ReadiumErrorCode, List<String>> _wireValues = {
    ReadiumErrorCode.formatNotSupported: ['formatNotSupported'],
    ReadiumErrorCode.unsupportedScheme: ['unsupportedScheme'],
    ReadiumErrorCode.readingError: ['readingError'],
    ReadiumErrorCode.notFound: ['notFound'],
    ReadiumErrorCode.forbidden: ['forbidden'],
    ReadiumErrorCode.unavailable: ['unavailable'],
    ReadiumErrorCode.incorrectCredentials: ['incorrectCredentials'],
    ReadiumErrorCode.audioStreamRetry: ['AudioStreamRetry'],
    ReadiumErrorCode.audioStreamFailed: ['AudioStreamFailed'],
    ReadiumErrorCode.audioStreamAuthError: ['AudioStreamAuthError'],
    ReadiumErrorCode.audioStreamHttpError: ['AudioStreamHTTPError'],
    ReadiumErrorCode.audioStreamNetworkError: ['AudioStreamNetworkError'],
    ReadiumErrorCode.audioStreamRangeNotSupported: ['AudioStreamRangeNotSupported'],
    ReadiumErrorCode.audioStreamFileError: ['AudioStreamFileError'],
    ReadiumErrorCode.audioStreamError: ['AudioStreamError'],
    ReadiumErrorCode.ttsUtteranceFailed: ['TTSUtteranceFailed'],
    ReadiumErrorCode.timeBasedNavigatorError: ['TimeBasedNavigatorError'],
    ReadiumErrorCode.didFailToLoadResource: ['DidFailToLoadResource'],
  };

  static final Map<String, ReadiumErrorCode> _byLowerWireValue = {
    for (final entry in _wireValues.entries)
      for (final wire in entry.value) wire.toLowerCase(): entry.key,
  };

  /// Parses a raw wire `code` string into a [ReadiumErrorCode].
  ///
  /// Case-insensitive; `null`, empty, or unrecognised input maps to
  /// [unknown]. Never throws.
  static ReadiumErrorCode fromWire(String? wireCode) {
    if (wireCode == null || wireCode.isEmpty) return ReadiumErrorCode.unknown;
    return _byLowerWireValue[wireCode.toLowerCase()] ?? ReadiumErrorCode.unknown;
  }

  /// `true` for informational events that do not represent a terminal
  /// failure (currently only [audioStreamRetry], emitted while automatic
  /// connection recovery is in progress).
  bool get isInformational => this == ReadiumErrorCode.audioStreamRetry;

  /// `true` for terminal errors. Exact complement of [isInformational].
  bool get isFatal => !isInformational;

  /// Coarse grouping for switching on related codes without enumerating
  /// every member.
  ReadiumErrorCategory get category {
    switch (this) {
      case ReadiumErrorCode.formatNotSupported:
      case ReadiumErrorCode.unsupportedScheme:
      case ReadiumErrorCode.readingError:
      case ReadiumErrorCode.notFound:
      case ReadiumErrorCode.forbidden:
      case ReadiumErrorCode.unavailable:
      case ReadiumErrorCode.incorrectCredentials:
        return ReadiumErrorCategory.opening;
      case ReadiumErrorCode.audioStreamRetry:
      case ReadiumErrorCode.audioStreamFailed:
      case ReadiumErrorCode.audioStreamAuthError:
      case ReadiumErrorCode.audioStreamHttpError:
      case ReadiumErrorCode.audioStreamNetworkError:
      case ReadiumErrorCode.audioStreamRangeNotSupported:
      case ReadiumErrorCode.audioStreamFileError:
      case ReadiumErrorCode.audioStreamError:
        return ReadiumErrorCategory.audioStream;
      case ReadiumErrorCode.ttsUtteranceFailed:
        return ReadiumErrorCategory.tts;
      case ReadiumErrorCode.timeBasedNavigatorError:
      case ReadiumErrorCode.didFailToLoadResource:
        return ReadiumErrorCategory.navigator;
      case ReadiumErrorCode.unknown:
        return ReadiumErrorCategory.unknown;
    }
  }
}
