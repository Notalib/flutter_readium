/// NOTE: Order MUST match [TaskStatus] for consistency with [ReadiumDownloadTaskStatusExtension.toEnum].
/// Defines a set of possible states which a [Task] can be in.
enum DownloadStatus {
  enqueued,
  running,
  complete,
  undefined,
  failed,
  cancelled,
  waitingToRetry,
  paused,
  lowDiskSpace,
}

extension ReadiumDownloadStatusExtension on DownloadStatus {
  bool get isUndefined => name == DownloadStatus.undefined.name;
  bool get isEnqueued => name == DownloadStatus.enqueued.name;
  bool get isRunning => name == DownloadStatus.running.name;
  bool get isComplete => name == DownloadStatus.complete.name;
  bool get isFailed => name == DownloadStatus.failed.name;
  bool get isCancelled => name == DownloadStatus.cancelled.name;
  bool get isWaitingToRetry => name == DownloadStatus.waitingToRetry.name;
  bool get isPaused => name == DownloadStatus.paused.name;
  bool get lowDiskSpace => name == DownloadStatus.lowDiskSpace.name;

  bool get isDownloadingOrPaused => isRunning || isEnqueued || isPaused;
}
