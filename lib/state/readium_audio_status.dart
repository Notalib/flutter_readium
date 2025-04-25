enum ReadiumAudioStatus {
  /// There hasn't been any resource loaded yet.
  none,

  /// Resource is being loaded.
  loading,

  /// Resource is being buffered.
  buffering,

  /// Resource is buffered enough and available for playback.
  ready,

  /// Resource is buffered enough and available for playback.
  playing,

  /// End of chapter reached.
  endOfChapter,

  /// End of publication reached.
  endOfPublication,

  /// Audio handler encountered an issue.
  error,
}

extension ReadiumAudioStatusExtension on ReadiumAudioStatus {
  bool get isNone => name == ReadiumAudioStatus.none.name;
  bool get isLoading => name == ReadiumAudioStatus.loading.name;
  bool get isBuffering => name == ReadiumAudioStatus.buffering.name;
  bool get isReady => name == ReadiumAudioStatus.ready.name;
  bool get isEndOfChapter => name == ReadiumAudioStatus.endOfChapter.name;
  bool get isEndOfPublication => name == ReadiumAudioStatus.endOfPublication.name;
  bool get isError => name == ReadiumAudioStatus.error.name;
}
