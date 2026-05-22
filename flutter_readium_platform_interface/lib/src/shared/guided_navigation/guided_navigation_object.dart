import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/index.dart';
import 'guided_navigation_description.dart';
import 'guided_navigation_role.dart';
import 'guided_navigation_text.dart';

/// A single step in a guided navigation sequence.
///
/// Must contain at least one of: [audioref], [imgref], [textref], [videoref],
/// [text], or [children].
///
/// See https://readium.org/guided-navigation/schema/object.schema.json
@immutable
class GuidedNavigationObject with EquatableMixin implements JSONable {
  const GuidedNavigationObject({
    this.id,
    this.audioref,
    this.imgref,
    this.textref,
    this.videoref,
    this.text,
    this.role = const [],
    this.children = const [],
    this.description,
  });

  final String? id;
  final String? audioref;
  final String? imgref;
  final String? textref;
  final String? videoref;
  final GuidedNavigationText? text;
  final List<GuidedNavigationRole> role;
  final List<GuidedNavigationObject> children;
  final GuidedNavigationDescription? description;

  @override
  List<Object?> get props => [id, audioref, imgref, textref, videoref, text, role, children, description];

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('id', id)
    ..putOpt('audioref', audioref)
    ..putOpt('imgref', imgref)
    ..putOpt('textref', textref)
    ..putOpt('videoref', videoref)
    ..putJSONableIfNotEmpty('text', text)
    ..putIterableIfNotEmpty('role', role.map((r) => r.value))
    ..putIterableIfNotEmpty('children', children)
    ..putJSONableIfNotEmpty('description', description);

  static GuidedNavigationObject? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final jsonObject = Map<String, dynamic>.of(json);
    final id = jsonObject.optNullableString('id', remove: true);
    final audioref = jsonObject.optNullableString('audioref', remove: true);
    final imgref = jsonObject.optNullableString('imgref', remove: true);
    final textref = jsonObject.optNullableString('textref', remove: true);
    final videoref = jsonObject.optNullableString('videoref', remove: true);
    final text = GuidedNavigationText.fromJson(jsonObject.opt('text', remove: true));
    final role = jsonObject
        .optStringsFromArrayOrSingle('role', remove: true)
        .map(GuidedNavigationRole.optFromString)
        .whereType<GuidedNavigationRole>()
        .toList();
    final children = (jsonObject.optJsonArray('children', remove: true) ?? []).parseObjects(
      (it) => GuidedNavigationObject.fromJson(it is Map<String, dynamic> ? it : null),
    );
    final description = GuidedNavigationDescription.fromJson(jsonObject.optJsonObject('description', remove: true));

    if (audioref == null && imgref == null && textref == null && videoref == null && text == null && children.isEmpty) {
      ReadiumLog.d('GuidedNavigationObject: at least one media reference, text, or children is required');
      return null;
    }

    return GuidedNavigationObject(
      id: id,
      audioref: audioref,
      imgref: imgref,
      textref: textref,
      videoref: videoref,
      text: text,
      role: role,
      children: children,
      description: description,
    );
  }

  static List<GuidedNavigationObject> fromJsonArray(List<dynamic>? json) =>
      (json ?? []).parseObjects((it) => GuidedNavigationObject.fromJson(it is Map<String, dynamic> ? it : null));
}
