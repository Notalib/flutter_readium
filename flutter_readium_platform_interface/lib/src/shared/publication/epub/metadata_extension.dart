import 'package:equatable/equatable.dart';

import '../../../utils/jsonable.dart';
import '../metadata.dart';

extension EpubMetadataExtension on Metadata {
  static const String _mediaOverlayKey = 'mediaOverlay';
  MetdataMediaOverlay? get mediaOverlay =>
      MetdataMediaOverlay.fromJson(additionalProperties.optJsonObject(_mediaOverlayKey));
}

class MetdataMediaOverlay with EquatableMixin implements JSONable {
  const MetdataMediaOverlay({this.activeClass, this.playbackActiveClass});

  final String? activeClass;
  final String? playbackActiveClass;

  @override
  List<Object?> get props => [activeClass, playbackActiveClass];

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'activeClass': activeClass,
    'playbackActiveClass': playbackActiveClass,
  };

  static MetdataMediaOverlay? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final activeClass = jsonObject.optNullableString('activeClass', remove: true);
    final playbackActiveClass = jsonObject.optNullableString('playbackActiveClass', remove: true);

    return MetdataMediaOverlay(activeClass: activeClass, playbackActiveClass: playbackActiveClass);
  }
}
