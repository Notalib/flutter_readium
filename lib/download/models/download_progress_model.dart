import '../_index.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.status,
    required this.progress,
    required this.opdsPublication,
    this.taskId,
  });

  final DownloadStatus status;

  /// Progress from 0 to 100.
  final int progress;
  final OPDSPublication opdsPublication;
  final String? taskId;

  @override
  String toString() => 'DownloadProgress('
      'taskId: $taskId, '
      'opdsId:${opdsPublication.identifier} '
      'status: $status, '
      'progress:$progress '
      ')';
}

extension DownloadProgressExtension on DownloadProgress {
  DownloadProgress copyWith({
    final String? taskId,
    final DownloadStatus? status,
    final int? progress,
    final OPDSPublication? opdsPublication,
  }) =>
      DownloadProgress(
        taskId: taskId ?? this.taskId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        opdsPublication: opdsPublication ?? this.opdsPublication,
      );
}
