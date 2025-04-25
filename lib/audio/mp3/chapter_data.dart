import 'dart:convert';

import '../../_index.dart';

class ChapterData {
  ChapterData({
    required this.getString,
    required this.link,
    required this.narrationLink,
    required this.mediaItem,
  });

  final Future<String> Function(Link) getString;
  final Link link;
  final Link narrationLink;
  final MediaItem mediaItem;

  /// Returns document data, fetching it if needed.
  late final lazyDocument =
      getString(link).then<XmlDocument?>(XmlDocument.parse).catchError((final _, final __) => null);

  /// Returns the narration, fetching it if needed.
  late final narration = getString(narrationLink)
      .then<SyncMediaNarration?>(
    (final n) => SyncMediaNarration.fromJson(json.decode(n) as Map<String, dynamic>),
  )
      .catchError((final error) {
    R2Log.e(error, data: narrationLink);

    return null;
  });
}
