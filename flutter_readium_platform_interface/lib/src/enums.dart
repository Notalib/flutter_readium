enum TimebasedState {
  playing,
  loading,
  paused,
  ended,
  failure,
}

/// Indicates the current reader widget status.
enum ReadiumReaderStatus {
  loading,
  ready,
  closed,
  reachedEndOfPublication,
  error,
}

extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => name == ReadiumReaderStatus.loading.name;
  bool get isReady => name == ReadiumReaderStatus.ready.name;
  bool get isClosed => name == ReadiumReaderStatus.closed.name;
  bool get reachedEndOfPublication => name == ReadiumReaderStatus.reachedEndOfPublication.name;
  bool get isError => name == ReadiumReaderStatus.error.name;
}

enum TTSVoiceGender { male, female, unspecified }

enum TTSVoiceQuality { lowest, low, normal, high, highest }
