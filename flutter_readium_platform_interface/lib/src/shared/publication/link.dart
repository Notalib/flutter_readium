import '../../_index.dart';
import '../to_string_short.dart';

part 'link.freezed.dart';
part 'link.g.dart';

/// Link Object for the Readium Web Publication Manifest.
///
/// [Json Schema](https://readium.org/webpub-manifest/schema/link.schema.json)

@freezedExcludeUnion
abstract class Link with _$Link, ToStringShort {
  @Assert('bitrate == null || bitrate > 0.0')
  @Assert('duration == null || duration > 0.0')
  @Assert('height == null || height > 0')
  @Assert('width == null || width > 0')
  @r2JsonSerializable
  const factory Link({
    /// URI or URI template of the linked resource.
    /// format:
    ///   if `template` is set
    ///     uri-template
    ///   else
    ///     uri-reference
    required final String href,

    /// Alternate resources for the linked resource.
    final List<Link>? alternate,

    /// Bitrate of the linked resource in kbps.
    ///
    /// "exclusiveMinimum": 0
    final double? bitrate,

    /// Resources that are children of the linked resource, in the context of a
    /// given collection role.
    final List<Link>? children,

    /// Length of the linked resource in seconds.
    ///
    /// "exclusiveMinimum": 0
    final double? duration,

    /// Height of the linked resource in pixels.
    ///
    /// "exclusiveMinimum": 0
    final int? height,

    /// Expected language of the linked resource.
    ///
    /// anyOf:
    ///   String
    ///   List<String>
    @localizeStringListJson final List<String>? language,

    /// Properties associated to the linked resource.
    final Properties? properties,

    /// Relation between the linked resource and its containing collection.
    ///
    /// anyOf:
    ///   String
    ///   List<String>
    @stringListJson final List<String>? rel,

    /// Indicates that a URI template is used in href.
    final bool? templated,

    /// Title of the linked resource.
    final String? title,

    /// MIME type of the linked resource.
    final String? type,

    /// Width of the linked resource in pixels.
    ///
    /// "exclusiveMinimum": 0
    final int? width,
  }) = _Link;

  factory Link.fromJson(final Map<String, dynamic> json) => _$LinkFromJson(JsonUtils.trimStringsInMap(json));

  const Link._();
}
