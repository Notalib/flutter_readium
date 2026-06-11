import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/jsonable.dart';

/// Text associated with a guided navigation object or description.
///
/// Can be either a plain string or a structured object with optional SSML
/// markup and language tag.
///
/// See https://readium.org/guided-navigation/schema/text.schema.json
sealed class GuidedNavigationText implements JSONable {
  const GuidedNavigationText();

  /// Parses a [GuidedNavigationText] from its JSON representation.
  ///
  /// Accepts either a [String] or a [Map<String, dynamic>] with at least one
  /// of [plain] or [ssml].
  static GuidedNavigationText? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is String) {
      return json.isNotEmpty ? GuidedNavigationTextString(json) : null;
    }
    if (json is Map<String, dynamic>) {
      final jsonObject = Map<String, dynamic>.of(json);
      final plain = jsonObject.optNullableString('plain', remove: true);
      final ssml = jsonObject.optNullableString('ssml', remove: true);
      final language = jsonObject.optNullableString('language', remove: true);
      if (plain == null && ssml == null) return null;
      return GuidedNavigationTextObject(
        plain: plain,
        ssml: ssml,
        language: language,
      );
    }
    return null;
  }
}

/// A guided navigation text represented as a plain string.
@immutable
final class GuidedNavigationTextString extends GuidedNavigationText with EquatableMixin {
  const GuidedNavigationTextString(this.value);

  final String value;

  @override
  List<Object> get props => [value];

  @override
  String toJson() => value;
}

/// A guided navigation text represented as a structured object with optional
/// SSML markup and BCP 47 language tag.
@immutable
final class GuidedNavigationTextObject extends GuidedNavigationText with EquatableMixin {
  const GuidedNavigationTextObject({this.plain, this.ssml, this.language});

  final String? plain;
  final String? ssml;
  final String? language;

  @override
  List<Object?> get props => [plain, ssml, language];

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('plain', plain)
    ..putOpt('ssml', ssml)
    ..putOpt('language', language);
}
