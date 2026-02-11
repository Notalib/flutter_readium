import 'package:collection/collection.dart';

enum TimebasedState {
  none,

  /// The player is currently playing - equivalent to kotlin-toolkit Ready + playWhenReady = true
  playing,

  /// The player is currently loading/buffering.
  loading,

  /// Playback is paused - equivalent to kotlin-toolkit Ready + playWhenReady = false
  paused,

  /// The player has reached the end of the publication.
  ended,

  /// The player is in a failure state.
  failure;

  static TimebasedState? fromString(final String state) =>
      TimebasedState.values.firstWhereOrNull((e) => e.name.toLowerCase() == state.toLowerCase()) ?? TimebasedState.none;
}

/// Indicates the current reader widget status.
enum ReadiumReaderStatus {
  /// The reader is loading content.
  loading,

  /// The reader is ready
  ready,

  /// The reader is closed
  closed,

  /// The reader has reached the end of the publication.
  reachedEndOfPublication,

  /// An error has occurred in the reader.
  error;

  static ReadiumReaderStatus? fromString(final String status) =>
      ReadiumReaderStatus.values.firstWhereOrNull((e) => e.name.toLowerCase() == status.toLowerCase());
}

extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => this == ReadiumReaderStatus.loading;
  bool get isReady => this == ReadiumReaderStatus.ready;
  bool get isClosed => this == ReadiumReaderStatus.closed;
  bool get reachedEndOfPublication => this == ReadiumReaderStatus.reachedEndOfPublication;
  bool get isError => this == ReadiumReaderStatus.error;
}

enum TTSVoiceGender { male, female, unspecified }

enum TTSVoiceQuality { lowest, low, normal, high, highest }
