import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/index.dart';
import 'guided_navigation_text.dart';

/// Alternative description for a guided navigation object, using one or more
/// media references.
///
/// At least one of [audioref], [imgref], [textref], [videoref], or [text]
/// must be present.
///
/// See https://readium.org/guided-navigation/schema/description.schema.json
@immutable
class GuidedNavigationDescription with EquatableMixin implements JSONable {
  const GuidedNavigationDescription({this.audioref, this.imgref, this.textref, this.videoref, this.text});

  final String? audioref;
  final String? imgref;
  final String? textref;
  final String? videoref;
  final GuidedNavigationText? text;

  @override
  List<Object?> get props => [audioref, imgref, textref, videoref, text];

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('audioref', audioref)
    ..putOpt('imgref', imgref)
    ..putOpt('textref', textref)
    ..putOpt('videoref', videoref)
    ..putJSONableIfNotEmpty('text', text);

  static GuidedNavigationDescription? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final jsonObject = Map<String, dynamic>.of(json);
    final audioref = jsonObject.optNullableString('audioref', remove: true);
    final imgref = jsonObject.optNullableString('imgref', remove: true);
    final textref = jsonObject.optNullableString('textref', remove: true);
    final videoref = jsonObject.optNullableString('videoref', remove: true);
    final text = GuidedNavigationText.fromJson(jsonObject.opt('text', remove: true));

    if (audioref == null && imgref == null && textref == null && videoref == null && text == null) {
      ReadiumLog.d('GuidedNavigationDescription: at least one media reference is required');
      return null;
    }

    return GuidedNavigationDescription(
      audioref: audioref,
      imgref: imgref,
      textref: textref,
      videoref: videoref,
      text: text,
    );
  }
}
