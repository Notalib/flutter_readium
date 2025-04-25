class R2DownloadException implements Exception {
  const R2DownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2DownloadException{$message}';
}

class R2NotAllowedCellularDownloadException implements Exception {
  const R2NotAllowedCellularDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2NotAllowedCellularDownloadException{$message}';
}

class R2LowDiskSpaceDownloadException implements Exception {
  const R2LowDiskSpaceDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2LowDiskSpaceDownloadException{$message}';
}

class R2NotEnoughDiskSpaceDownloadException implements Exception {
  const R2NotEnoughDiskSpaceDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2NotEnoughDiskSpaceDownloadException{$message}';
}

class R2UnknownDiskSpaceDownloadException implements Exception {
  const R2UnknownDiskSpaceDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2UnknownDiskSpaceDownloadException{$message}';
}

class R2ProgressDownloadException implements Exception {
  const R2ProgressDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2ProgressDownloadException{$message}';
}

class R2OfflineDownloadException implements Exception {
  const R2OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => 'R2OfflineDownloadException{$message}';
}
