import '../index.dart';

part 'presentation.freezed.dart';
part 'presentation.g.dart';

/// Presentation associated to the linked resource
///
/// PartOf: PartOf: [Metadata Json Schema](https://readium.org/webpub-manifest/schema/metadata.schema.json)
///
/// AllOf:
///   * [ePub Metadata Json Schema](https://readium.org/webpub-manifest/schema/extensions/epub/metadata.schema.json)
///   * [Presentation Metadata Json Schema](https://readium.org/webpub-manifest/schema/extensions/presentation/metadata.schema.json)

@freezedExcludeUnion
abstract class Presentation with _$Presentation {
  @r2JsonSerializable
  const factory Presentation({
    final Layout? layout,

    /// Specifies whether or not the parts of a linked resource that flow out of
    /// the viewport are clipped.
    final bool? clipped,

    /// Indicates if consecutive linked resources from the `reading order`
    /// should be handled in a continuous or discontinuous way.
    final bool? continuous,

    /// Specifies constraints for the presentation of a linked resource within
    /// the viewport.
    final Fit? fit,

    /// Suggested orientation for the device when displaying the linked
    /// resource.
    final Orientation? orientation,

    /// Indicates if the overflow of linked resources from the `readingOrder` or
    /// `resources` should be handled using dynamic pagination or scrolling.
    final Overflow? overflow,

    /// Indicates the condition to be met for the linked resource to be rendered
    /// within a synthetic spread.
    final Spread? spread,
  }) = _Presentation;

  factory Presentation.fromJson(final Map<String, dynamic> json) => _$PresentationFromJson(json);
}
