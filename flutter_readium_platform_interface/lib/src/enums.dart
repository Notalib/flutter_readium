import 'package:collection/collection.dart';

/// Playback state for a timebased (audio or TTS) navigator.
enum TimebasedState {
  /// No active navigator or state is unknown.
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

  /// Returns the [TimebasedState] matching [state] (case-insensitive), defaulting to [none].
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

  /// Returns the [ReadiumReaderStatus] matching [status] (case-insensitive), or `null` if unknown.
  static ReadiumReaderStatus? fromString(final String status) =>
      ReadiumReaderStatus.values.firstWhereOrNull((e) => e.name.toLowerCase() == status.toLowerCase());

  /// Whether the reader is in the loading state.
  bool get isLoading => this == ReadiumReaderStatus.loading;

  /// Whether the reader is ready for interaction.
  bool get isReady => this == ReadiumReaderStatus.ready;

  /// Whether the reader has been closed.
  bool get isClosed => this == ReadiumReaderStatus.closed;

  /// Whether the reader has reached the end of the publication.
  bool get hasReachedEndOfPublication => this == ReadiumReaderStatus.reachedEndOfPublication;

  /// Whether the reader is in an error state.
  bool get isError => this == ReadiumReaderStatus.error;
}

/// Reported gender of a TTS voice.
enum TTSVoiceGender {
  male,
  female,
  unspecified;

  /// Returns the [TTSVoiceGender] matching [gender] (case-insensitive), or `null` if unknown.
  static TTSVoiceGender? optFromString(final String gender) =>
      TTSVoiceGender.values.firstWhereOrNull((e) => e.name.toLowerCase() == gender.toLowerCase());

  /// Returns the [TTSVoiceGender] matching [gender], falling back to [unspecified].
  static TTSVoiceGender fromString(final String gender) => optFromString(gender) ?? TTSVoiceGender.unspecified;
}

/// Reported quality level of a TTS voice.
enum TTSVoiceQuality {
  lowest,
  low,
  normal,
  high,
  highest;

  /// Returns the [TTSVoiceQuality] matching [quality] (case-insensitive), or `null` if unknown.
  static TTSVoiceQuality? optFromString(final String quality) =>
      TTSVoiceQuality.values.firstWhereOrNull((e) => e.name.toLowerCase() == quality.toLowerCase());

  /// Returns the [TTSVoiceQuality] matching [quality], falling back to [normal].
  static TTSVoiceQuality fromString(final String quality) => optFromString(quality) ?? TTSVoiceQuality.normal;
}
