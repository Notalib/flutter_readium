import 'index.dart';

part 'media_overlay_node.freezed.dart';
part 'media_overlay_node.g.dart';

/// Based on https://github.com/readium/architecture/blob/master/models/media-overlay/syntax.md

@freezedExcludeUnion
abstract class MediaOverlayNode with _$MediaOverlayNode {
  const factory MediaOverlayNode({
    /// URI to a fragment id in an HTML/XHTML resource.
    final String? textref,

    /// URI to a media fragment in an audio resource.
    final String? audioref,

    /// List of roles relevant for the current node.
    @stringListJson final List<String>? role,

    /// List of media overlay nodes.
    final List<MediaOverlayNode>? children,
  }) = _MediaOverlayNode;

  factory MediaOverlayNode.fromJson(final Map<String, dynamic> json) =>
      _$MediaOverlayNodeFromJson(json);
}
