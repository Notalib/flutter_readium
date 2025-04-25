import 'package:dio/dio.dart';

import '_index.dart';

class ReadiumPreloadProgress {
  const ReadiumPreloadProgress({
    required this.opdsPubId,
    required this.savePath,
    required this.cancelToken,
    required this.preloadFuture,
  });

  final String opdsPubId;
  final String savePath;
  final CancelToken cancelToken;
  final Future<Response> preloadFuture;
}

extension ReadiumPreloadProgressExtension on List<ReadiumPreloadProgress> {
  ReadiumPreloadProgress? getPreload(final String opdsPubId) =>
      firstWhereOrNull((final preload) => preload.opdsPubId == opdsPubId);

  List<ReadiumPreloadProgress> removePreload(final String opdsPubId) =>
      where((final preload) => preload.opdsPubId != opdsPubId).toList();
}
