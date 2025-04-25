import 'dart:io';

import 'package:dio/dio.dart';

import '_index.dart';

class ReadiumPreloader {
  ReadiumPreloader._();

  factory ReadiumPreloader() => instance;

  static final instance = ReadiumPreloader._();

  static final _downloader = ReadiumDownloader.instance;

  List<ReadiumPreloadProgress> _preloads = [];

  Future<Response>? downloadFuture;

  /// Downloads a file based on the opds feed provided and the url given.
  ///
  /// It returns a string which is where the file is downloaded to.
  /// If the result is null it means the request was cancelled.
  Future<String?> preloadFile({
    required final OPDSPublication opdsPub,
    required final String url,
    final Map<String, String>? headers,
    final void Function(double)? onProgress,
  }) async {
    if (await _downloader.isDownloaded(opdsPub)) {
      final downloadDirPath = await ReadiumStorage.publicationsDirPath;
      final downloadedPath = join(downloadDirPath, opdsPub.filenamePath);
      R2Log.d('Already downloaded in path: $downloadedPath');

      return downloadedPath;
    }

    final opdsPubId = opdsPub.identifier;

    final oldPreload = _preloads.getPreload(opdsPubId);

    if (oldPreload != null) {
      R2Log.d('Already preloading the publication');

      await oldPreload.preloadFuture;

      return oldPreload.savePath;
    }

    final file = await _getPublicationCachePath(opdsPub);

    if (file.existsSync()) {
      R2Log.d('Already cached in path ${file.path}');

      return file.path;
    }

    final directory = Directory(file.path).parent;

    R2Log.d('Preloading $opdsPubId to $directory');

    // Track last download progress to reduce progress updates from `onReceiveProgress`.
    double? lastProgress;

    final cancelToken = CancelToken();

    final preloadFuture = Dio().download(
      url,
      file.path,
      cancelToken: cancelToken,
      options: Options(headers: headers),
      onReceiveProgress: (final count, final total) {
        final progress = count / total;
        final roundedProgress = double.parse((progress).toStringAsFixed(2));

        if (roundedProgress != lastProgress) {
          lastProgress = roundedProgress;

          onProgress?.call(roundedProgress);
        }
      },
    );

    final preload = ReadiumPreloadProgress(
      opdsPubId: opdsPubId,
      savePath: file.path,
      cancelToken: cancelToken,
      preloadFuture: preloadFuture,
    );

    _preloads.add(preload);

    return _handlePreload(preload);
  }

  Future<void> cancelAllPreload() async {
    for (final preload in _preloads) {
      preload.cancelToken.cancel();
    }

    return _cleanupCacheDir();
  }

  Future<void> cancelPreloadPublication(final OPDSPublication opdsPub) async {
    final opdsPubId = opdsPub.identifier;
    final preload = _preloads.getPreload(opdsPubId);
    if (preload == null) {
      R2Log.d('No preload found for $opdsPubId');

      return;
    }

    R2Log.d('Canceling preload $opdsPubId');

    preload.cancelToken.cancel();

    try {
      final pubCacheDir = await _getPublicationCacheDir(opdsPub);
      pubCacheDir.deleteSync(recursive: true);
    } on Object catch (e) {
      R2Log.e(e, updateState: false);
    }
  }

  Future<void> _cleanupCacheDir() async {
    final dir = await ReadiumStorage.publicationCacheDir;
    try {
      R2Log.d('Cleaning up preload cache');
      final contents = dir.listSync();

      // Delete files older than 7 days.
      contents
          .where(
        (final item) =>
            item.statSync().modified.isBefore(DateTime.now().subtract(const Duration(days: 7))),
      )
          .forEach((final item) {
        item.deleteSync(recursive: true);
      });

      // Keep only the 5 most recently accessed files.
      final updatedContents = dir.listSync();
      if (updatedContents.length > 5) {
        updatedContents
            .sort((final a, final b) => a.statSync().accessed.compareTo(b.statSync().accessed));
        for (var i = updatedContents.length - 1; i >= 5; i--) {
          try {
            updatedContents[i].deleteSync(recursive: true);
          } on Object catch (e) {
            R2Log.e('Failed to delete pub from preloadCache ${updatedContents[i].path}', data: e);
          }
        }
      }
    } on FileSystemException {
      // File doesn't exist.
      R2Log.d("${dir.path} (didn't exist)");
    }
  }

  Future<String?> _handlePreload(final ReadiumPreloadProgress preload) async {
    try {
      await preload.preloadFuture;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        R2Log.d('Preload file was cancelled');
        return null;
      }
      rethrow;
    } finally {
      _preloads = _preloads.removePreload(preload.opdsPubId);
    }

    return preload.savePath;
  }

  Future<Directory> _getPublicationCacheDir(final OPDSPublication opdsPub) async {
    final encodedPubId = opdsPub.encodedIdentifier;
    final cacheDir = await ReadiumStorage.publicationCacheDirPath;
    return Directory('$cacheDir/$encodedPubId');
  }

  Future<File> _getPublicationCachePath(final OPDSPublication opdsPub) async {
    final filename = opdsPub.filename;
    final pubCacheDir = await _getPublicationCacheDir(opdsPub);

    return File('${pubCacheDir.path}/$filename');
  }
}
