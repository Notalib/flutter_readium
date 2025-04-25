import 'index.dart';

part 'media_overlay_style_info.freezed.dart';
part 'media_overlay_style_info.g.dart';

/// Readium media overlay styling info
/// based on https://github.com/readium/architecture/tree/master/models/media-overlay#style-information

@freezedExcludeUnion
abstract class MediaOverlayStyleInfo with _$MediaOverlayStyleInfo {
  const factory MediaOverlayStyleInfo({
    @JsonKey(name: 'active-class') final String? activeClass,
    @JsonKey(name: 'playback-active-class') final String? playbackActiveClass,
  }) = _MediaOverlayStyleInfo;

  factory MediaOverlayStyleInfo.fromJson(final Map<String, dynamic> json) =>
      _$MediaOverlayStyleInfoFromJson(json);
}
