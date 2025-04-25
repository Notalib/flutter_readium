import 'dart:core';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '_index.dart';

typedef ReadiumDownloadHeaders = Map<String, String>;

typedef ReadiumDownloadNotificationTapCallback = void Function(OPDSPublication);

class ReadiumDownloader {
  ReadiumDownloader._();
  factory ReadiumDownloader() => instance;
  static final instance = ReadiumDownloader._();

  late final FileDownloader _downloader;
  late final downloadProgress = BehaviorSubject<DownloadProgress>();

  final _warningLowDiskSpaceLimitMB = 10000;

  final _errorLowDiskSpaceLimitMB = 7000;

  static const downloadableMimeTypes = [
    MediaType.epub,
    MediaType.readiumWebPub,
    MediaType.pdf,
  ];

  Future<void> init({
    final int step = 0,
    // Set to true only when debugging download
    final bool debug = false,

    // Only for android.
    final ReadiumDownloadNotificationTapCallback? notificationTapCallback,
  }) async {
    R2Log.d('Initialize...');

    _downloader = FileDownloader()
      ..configure(
        globalConfig: [
          (Config.checkAvailableSpace, _errorLowDiskSpaceLimitMB),
        ],
      )
      ..resumeFromBackground()
      ..registerCallbacks(
        taskStatusCallback: (final update) {
          _downloadProgressCallback(update.task);
        },
        taskProgressCallback: (final update) {
          _downloadProgressCallback(update.task);
        },
        taskNotificationTapCallback: (final task, final notificationType) {
          final opdsPub = task.getOpdsPublication();

          if (opdsPub != null) {
            notificationTapCallback?.call(opdsPub);
          }
        },
      );

    await _downloader.trackTasks();

    R2Log.d('Initialized');
  }

  Future<void> download(
    final OPDSPublication opdsPublication, {
    final Link? downloadLink,
    final ReadiumDownloadHeaders? headers,
    final bool allowCellular = true,
    final bool ignoreLowDiskSpace = false,
    final String? displayName,
  }) async {
    if (!await hasInternetConnection()) {
      throw const R2OfflineDownloadException('Offline');
    }

    if (!allowCellular && await isMobileConnectivity) {
      throw const R2NotAllowedCellularDownloadException('Download via cellular not allowed!');
    }

    // Use the supplied downloadLink or default to opdsPublication's downloadLink.
    final link = downloadLink ?? opdsPublication.downloadLink;

    if (link == null) {
      throw R2DownloadException('No download link found in opdsPublication: $opdsPublication');
    }

    await _prepare(opdsPublication, ignoreLowDiskSpace: ignoreLowDiskSpace);

    if (await _hasActiveTask(opdsPublication)) {
      R2Log.d('Already downloaded or downloading');
      return;
    }

    final task = DownloadTask(
      url: link.href,
      directory: await _getPublicationRelativeDirPath(opdsPublication),
      baseDirectory: BaseDirectory.applicationSupport,
      filename: opdsPublication.filename,
      headers: headers ?? const {},
      requiresWiFi: !allowCellular,
      taskId: opdsPublication.downloadTaskId,
      updates: Updates.statusAndProgress,
    ).setOpdsPublication(opdsPublication);

    final displayName = opdsPublication.displayName;

    // Only show download notifications on android.
    if (Platform.isAndroid) {
      _downloader.configureNotificationForTask(
        task,
        running: TaskNotification(displayName, ''),
        complete: TaskNotification(displayName, ''),
        progressBar: true,
        tapOpensFile: true,
      );
    }

    final success = await _downloader.enqueue(task);

    if (!success) {
      throw const R2DownloadException('Could not enqueue task');
    }
  }

  Future<List<OPDSPublication>> getAllCompleted() async {
    final opdsPubs = <OPDSPublication>[];

    final records = await _getAllRecords();

    for (final record in records) {
      final opdsPub = record.task.getOpdsPublication();
      if (opdsPub != null) {
        opdsPubs.add(opdsPub);
      }
    }

    return opdsPubs;
  }

  Future<void> remove(final OPDSPublication opdsPublication) async {
    R2Log.d('Removing: ${opdsPublication.displayName}');

    final taskId = opdsPublication.downloadTaskId;

    await _downloader.cancelTaskWithId(taskId);
    await _downloader.database.deleteRecordWithId(taskId);

    downloadProgress.add(
      DownloadProgress(
        taskId: taskId,
        status: DownloadStatus.undefined,
        progress: -1,
        opdsPublication: opdsPublication,
      ),
    );

    await _deletePublicationDir(opdsPublication);

    R2Log.d('Done');
  }

  /// Stops any tasks and deletes the contents of the download directory (but doesn't delete the
  /// now-empty download directory).
  Future<void> removeAll() async {
    await _downloader.reset();

    await _clearDir(await ReadiumStorage.publicationsDir);
  }

  /// Removes only completed downloads
  Future<void> removeAllCompleted() async {
    final records = await _getAllRecords();

    for (final record in records) {
      if (record.status.isFinalState) {
        final opsPub = record.task.getOpdsPublication();
        if (opsPub != null) {
          remove(opsPub);
        }
      }
    }

    await _clearDir(await ReadiumStorage.publicationsDir);
  }

  Future<bool> isDownloaded(final OPDSPublication opdsPublication) async {
    final dirPath = await ReadiumStorage.publicationsDirPath;
    final completeFilePath = join(dirPath, opdsPublication.downloadCompleteFilenamePath);

    final completeFile = File(completeFilePath);

    return await _isPubFileDownloaded(opdsPublication) && completeFile.existsSync();
  }

  Future<DownloadProgress?> getProgress(final OPDSPublication opdsPublication) async {
    final record = await _getRecordById(opdsPublication.downloadTaskId);

    if (record == null && await isDownloaded(opdsPublication)) {
      R2Log.d(
        'No record found but publication is downloaded - return `complete` progress',
      );
      return DownloadProgress(
        status: DownloadStatus.complete,
        progress: 100,
        opdsPublication: opdsPublication,
      );
    } else if (record != null) {
      return record.toDownloadProgress();
    }

    return null;
  }

  Future<Publication?> getReadiumPublication(final OPDSPublication opdsPublication) async {
    if (await isDownloaded(opdsPublication)) {
      final downloadDirPath = await ReadiumStorage.publicationsDirPath;
      final pubFilenamePath = join(downloadDirPath, opdsPublication.filenamePath);

      return ReadiumPublicationChannel.fromPath(
        pubFilenamePath,
        mediaType: opdsPublication.mediaType,
      );
    } else if (isLocalAsset(opdsPublication)) {
      final pubFilenamePath = opdsPublication.links.first.href;
      final mediaType = getMediaType(opdsPublication.links.first.type ?? pubFilenamePath);

      if (mediaType == null) {
        throw R2DownloadException('Unsupported local media type: $pubFilenamePath');
      }

      return ReadiumPublicationChannel.fromPath(
        pubFilenamePath,
        mediaType: mediaType,
      );
    }

    return null;
  }

  Future<bool> hasDownloads() async {
    final bytes = await _downloadDirectoryBytes();
    R2Log.d('Total downloaded bytes: $bytes');
    return bytes > 0;
  }

  Future<void> _downloadProgressCallback(final Task task) async {
    final taskId = task.taskId;
    final opdsPub = task.getOpdsPublication();

    if (opdsPub == null) {
      R2Log.d('No OPDS publication found for $taskId -- remove');
      // await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
      return;
    }

    final record = await _getRecordById(taskId);

    if (record == null) {
      throw R2ProgressDownloadException(
        'No download records found for ${opdsPub.identifier} ${opdsPub.filename}',
      );
    }

    final dlProgress = record.toDownloadProgress();

    final exception = record.exception;
    if (exception is TaskFileSystemException) {
      // TODO: Not a safe way at all to handle a exception by description text.
      // Create an issue on upstream to fine a better solution. Maybe every exception should have a
      // code.
      if (exception.description.toLowerCase().contains('insufficient space to store')) {
        return downloadProgress.add(
          dlProgress.copyWith(
            status: DownloadStatus.lowDiskSpace,
            progress: -1,
          ),
        );
      }
    }

    if (dlProgress.status.isComplete) {
      if (await _isPubFileDownloaded(opdsPub)) {
        await _createCompleteFile(opdsPub);
      } else {
        R2Log.d(
          'False complete: missing publication file: ${opdsPub.downloadLink?.href ?? 'no-downloadlink'} -- ${opdsPub.filename}',
        );

        return downloadProgress.add(
          dlProgress.copyWith(
            status: DownloadStatus.failed,
            progress: -1,
          ),
        );
      }
    }

    downloadProgress.add(dlProgress);
  }

  Future<bool> _isPubFileDownloaded(final OPDSPublication opdsPublication) async {
    final downloadDirPath = await ReadiumStorage.publicationsDirPath;

    if (!opdsPublication.hasDownloadLink) {
      return false;
    }

    final potentialFilePath = opdsPublication.filenamePath;
    final pubFilenamePath = join(downloadDirPath, potentialFilePath);

    final pubFile = File(pubFilenamePath);

    return pubFile.existsSync() && pubFile.lengthSync() > 5000;
  }

  Future<void> _createCompleteFile(final OPDSPublication opdsPublication) async {
    R2Log.d('Create complete file: ${opdsPublication.filename}');

    final downloadDirPath = await ReadiumStorage.publicationsDirPath;
    await File(join(downloadDirPath, opdsPublication.downloadCompleteFilenamePath)).create();
  }

  /// Returns number of bytes in publication's download directory (not counting filesystem overhead).
  Future<int> _downloadDirectoryBytes() async {
    var fileNum = 0;
    var bytes = 0;
    final dir = await ReadiumStorage.publicationsDir;
    _debugPrintDir(dir);

    if (dir.existsSync()) {
      dir.listSync(recursive: true, followLinks: false).forEach(
        (final entity) {
          if (entity is File) {
            fileNum++;
            bytes += entity.lengthSync();
          }
        },
      );
    }

    R2Log.d('Measured $bytes bytes from $fileNum files.');
    return bytes;
  }

  Future<TaskRecord?> _getRecordById(final String taskId) async {
    final record = await _downloader.database.recordForId(taskId);

    return record;
  }

  Future<Task?> _getTaskById(final String taskId) async {
    final record = await _getRecordById(taskId);

    return record?.task;
  }

  Future<List<TaskRecord>> _getAllRecords() async => _downloader.database.allRecords();

  Future<OPDSPublication?> getOpdsPubByTaskId(final String taskId) async {
    final task = await _getTaskById(taskId);

    return task?.getOpdsPublication();
  }

  /// Returns `true` if there is an active task with the given href, while clearing any inactive tasks
  /// with the given href. If the download was successful, creates the `downloadCompleteFile`.
  Future<bool> _hasActiveTask(final OPDSPublication opdsPublication) async {
    final record = await _getRecordById(opdsPublication.downloadTaskId);

    if (record == null) {
      return false;
    }

    return record.status.isNotFinalState;
  }

  Future<void> _prepare(
    final OPDSPublication opdsPublication, {
    required final bool ignoreLowDiskSpace,
  }) async {
    await _checkDiskSpace(ignoreLowDiskSpace: ignoreLowDiskSpace);
    await _createPublicationDir(opdsPublication);
  }

  Future<void> _checkDiskSpace({
    required final bool ignoreLowDiskSpace,
  }) async {
    // TODO: Uncomment when byteSize is set for all Publication types.
    // if (size == 0.0) {
    //   throw R2DownloadException(
    //     'Download size is 0.0MB for publication: $opdsPublication',
    //   );
    // }

    final diskSpace = await FlutterReadium.instance.getFreeDiskSpaceInMB();

    if (diskSpace == null) {
      throw const R2UnknownDiskSpaceDownloadException('Unknown available disk space!');
    }

    if (diskSpace < _errorLowDiskSpaceLimitMB) {
      throw R2NotEnoughDiskSpaceDownloadException('Low disk space: $diskSpace');
    }

    if (diskSpace < _warningLowDiskSpaceLimitMB && !ignoreLowDiskSpace) {
      throw R2LowDiskSpaceDownloadException('Low disk space: $diskSpace');
    }
  }

  Future<String> _getPublicationRelativeDirPath(final OPDSPublication opdsPublication) async =>
      join(await ReadiumStorage.publicationsRelativeDirPath, opdsPublication.downloadDirName);

  Future<String> _getPublicationDirPath(final OPDSPublication opdsPublication) async =>
      join(await ReadiumStorage.publicationsDirPath, opdsPublication.downloadDirName);

  Future<Directory> _getPublicationDir(final OPDSPublication opdsPublication) async =>
      Directory(await _getPublicationDirPath(opdsPublication));

  Future<void> _createPublicationDir(final OPDSPublication opdsPublication) async =>
      (await _getPublicationDir(opdsPublication)).create();

  Future<void> _deletePublicationDir(final OPDSPublication opdsPublication) async =>
      _deleteDir(await _getPublicationDir(opdsPublication));

  Future<void> _clearDir(final Directory dir) async {
    await _deleteDir(dir);
    await dir.create();
  }

  Future<void> _deleteDir(final Directory dir) async {
    try {
      R2Log.d('Deleted: ${dir.path}');
      await dir.delete(recursive: true);
    } on FileSystemException {
      // File doesn't exist.
      R2Log.d("Delete: ${dir.path} (didn't exist)");
    }
  }

  /// Only use it while debugging.
  // ignore: unused_element
  Future<void> _debugPrintDir(final Directory dir) async {
    if (kDebugMode) {
      R2Log.d('${dir.path} \$ ls -l');
      final dirList = await dir.list().toList();
      for (final entity in dirList.sortedBy((final entity) => entity.path)) {
        R2Log.d(
          '${entity is File ? (await entity.length()).toString().padLeft(10) : '----------'} '
          '${entity.path.substring(dir.path.length + 1)}',
        );
      }
      R2Log.d('-end-');
    }
  }

  /// Only use it while debugging.
  // ignore: unused_element
  Future<void> _debugPrintTasks() async {
    if (kDebugMode) {
      R2Log.d('BEGIN tasks');
      final tasks = await _getAllRecords();
      for (final task in tasks) {
        R2Log.d('$task');
      }
      R2Log.d('END tasks');
    }
  }

  bool isLocalAsset(final OPDSPublication opdsPublication) =>
      opdsPublication.links.first.href.contains('local');

  static MediaType? getMediaType(final String linkType) {
    final mediaTypes = [
      MediaType.epub,
      MediaType.readiumWebPub,
      MediaType.readiumAudiobook,
      // add more if needed
    ];

    for (final mediaType in mediaTypes) {
      if (mediaType.value == linkType) {
        return mediaType;
      }
    }

    final extension = linkType.split('.').last;

    for (final mediaType in mediaTypes) {
      if (mediaType.fileExtension == extension) {
        return mediaType;
      }
    }
    return null;
  }
}
