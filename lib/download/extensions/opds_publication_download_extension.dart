import 'dart:convert';

import '../_index.dart';

const manifestRel = 'manifest';
const downloadRel = 'acquisition/download';
const downloadPreloadRel = 'acquisition/download-preload';

extension OPDSPublicationDownloadExtension on OPDSPublication {
  String get identifier {
    final id = metadata.identifier;
    if (id == null || id.isEmpty) {
      throw const ReadiumException(
        'Missing identifier!. Make sure the publication has a Unique identifier',
      );
    }

    return id;
  }

  Link? get coverLink => images.firstWhereOrNull(
        (final link) => link.rel?.any((final rel) => rel.contains('image')) ?? false,
      );

  Uri? get coverUri => Uri.tryParse(coverLink?.href ?? '');

  String get encodedIdentifier => base64Url.encode(utf8.encode(identifier));

  String get downloadTaskId => encodedIdentifier;

  String get displayName => metadata.title.values.first;

  // Link to the publications manifest. This should also be used as baseUrl for other requests.
  Link? get manifestLink => links.firstWhereOrNull(
        (final link) => link.rel?.any((final rel) => rel.endsWith(manifestRel)) ?? false,
      );

  Link? get preloadLink => links.firstWhereOrNull(
        (final link) =>
            (link.rel?.any((final rel) => rel.endsWith(downloadPreloadRel)) ?? false) &&
            ReadiumDownloader.downloadableMimeTypes.map((final m) => m.value).contains(link.type),
      );

  Link? get downloadLink => links.firstWhereOrNull(
        (final link) =>
            (link.rel?.any((final rel) => rel.endsWith(downloadRel)) ?? false) &&
            ReadiumDownloader.downloadableMimeTypes.map((final m) => m.value).contains(link.type),
      );

  bool get hasManifestLink => manifestLink != null;
  bool get hasPreloadLink => preloadLink != null;
  bool get hasDownloadLink => downloadLink != null;

  String? get baseUrl => manifestLink?.href.substring(0, manifestLink!.href.lastIndexOf('/') + 1);

  int get downloadSize => metadata.downloadSize;

  double get downloadSizeInMB => downloadSize / (1000 * 1000);

  MediaType? get mediaType => ReadiumDownloader.downloadableMimeTypes
      .firstWhereOrNull((final m) => m.value == downloadLink?.type);

  String get downloadDirName => encodedIdentifier;

  String get safeFilename => displayName.replaceAll(RegExp(r'[^\w\d]+'), '-');

  /// Filename of downloaded file.
  String? get filename =>
      mediaType != null ? '$safeFilename.${mediaType?.fileExtension ?? 'file'}' : null;

  String? get filenamePath => mediaType != null ? join(downloadDirName, filename) : null;

  /// Filename of (empty) file which if existing, indicates that the download is complete.
  String get downloadCompleteFilename => '$encodedIdentifier.complete';

  String get downloadCompleteFilenamePath => join(downloadDirName, downloadCompleteFilename);
}
