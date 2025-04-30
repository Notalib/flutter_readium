import 'index.dart';

part 'media_overlay.freezed.dart';
part 'media_overlay.g.dart';

@freezedExcludeUnion
abstract class MediaOverlay with _$MediaOverlay {
  const factory MediaOverlay({
    final List<MediaOverlayNode>? mediaOverlays,
  }) = _MediaOverlay;

  factory MediaOverlay.fromJson(final Map<String, dynamic> json) => _$MediaOverlayFromJson(json);
}
