enum ReadiumPreloadStatus {
  none,
  loading,
  canceled,
  complete,
}

extension ReadiumPreloadStatusExtension on ReadiumPreloadStatus {
  bool get isNone => name == ReadiumPreloadStatus.none.name;
  bool get isLoading => name == ReadiumPreloadStatus.loading.name;
  bool get isCanceled => name == ReadiumPreloadStatus.canceled.name;
  bool get isComplete => name == ReadiumPreloadStatus.complete.name;
}
