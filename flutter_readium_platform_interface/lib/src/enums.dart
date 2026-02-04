import 'package:dfunc/dfunc.dart';

enum TimebasedState {
  none,

  /// The player is currently playing.
  playing,

  /// The player is currently loading/buffering.
  loading,

  /// The player is currently paused.
  paused,

  /// The player has ended playback.
  ended,

  /// The player is in a failure state.
  failure,
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
  error,
}

extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => name == ReadiumReaderStatus.loading.name;
  bool get isReady => name == ReadiumReaderStatus.ready.name;
  bool get isClosed => name == ReadiumReaderStatus.closed.name;
  bool get reachedEndOfPublication => name == ReadiumReaderStatus.reachedEndOfPublication.name;
  bool get isError => name == ReadiumReaderStatus.error.name;
}

extension ReadiumReaderStatusStringExtension on String {
  ReadiumReaderStatus toReadiumReaderStatus() => toLowerCase().let(
    (it) => ReadiumReaderStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == it,
      orElse: () => ReadiumReaderStatus.error,
    ),
  );
}

enum TTSVoiceGender { male, female, unspecified }

enum TTSVoiceQuality { lowest, low, normal, high, highest }
