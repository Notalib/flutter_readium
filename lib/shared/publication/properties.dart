import '../index.dart';
import '../to_string_short.dart';

part 'properties.freezed.dart';
part 'properties.g.dart';

/// Properties associated to the linked resource
///
/// PartOf: [Link Json Schema](https://readium.org/webpub-manifest/schema/link.schema.json)
///
/// AllOf:
///   * [OPDS Properties Json Schema](https://drafts.opds.io/schema/properties.schema.json)
///   * [EPUB Properties Json Schema](https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json)
///   * [Presentation Properties Json Schema](https://readium.org/webpub-manifest/schema//extensions/presentation/properties.schema.json)

@freezedExcludeUnion
abstract class Properties with _$Properties, ToStringShort {
  @Assert('numberOfItems == null || numberOfItems >= 0')
  @r2JsonSerializable
  const factory Properties({
    /// Indicated the availability of a given resource.
    final Availability? availability,

    /// Library-specific feature that contains information about the copies that
    /// a library has acquired.
    final Copies? copies,

    /// Library-specific features when a specific book is unavailable but
    /// provides a hold list.
    final Holds? holds,

    /// Indirect acquisition provides a hint for the expected media type that
    /// will be acquired after additional steps.
    final List<Acquisition>? indirectAcquisition,

    /// Provide a hint about the expected number of items returned.
    ///
    /// "minimum": 0
    final int? numberOfItems,

    /// The price of a publication is tied to its acquisition link.
    final Price? price,

    /// "uniqueItems": true
    final List<Contain>? contains,

    /// Indicates that a resource is encrypted/obfuscated and provides relevant
    /// information for decryption.
    final Encrypted? encrypted,

    /// Hints how the layout of the resource should be presented.
    final Layout? layout,

    /// Specifies whether or not the parts of a linked resource that flow out of
    /// the viewport are clipped.
    final bool? clipped,

    /// Specifies constraints for the presentation of a linked resource within
    /// the viewport.
    final Fit? fit,

    /// Suggested orientation for the device when displaying the linked
    /// resource.
    final Orientation? orientation,

    /// Indicates how the linked resource should be displayed in a reading
    /// environment that displays synthetic spreads.
    final Page? page,

    /// Indicates the condition to be met for the linked resource to be rendered
    /// within a synthetic spread.
    final Spread? spread,

    /// Properties related to subscription.
    final Subscription? subscription,

    /// TODO: Extract x-properties from core readium
    @JsonKey(name: 'characters') final int? xCharacters,
    @JsonKey(name: 'x-book-list-added') @dateTimeLocal final DateTime? xBooklistAdded,
    @JsonKey(name: 'x-book-list-last-access') @dateTimeLocal final DateTime? xBooklistLastAccess,
    @JsonKey(name: 'x-color') final String? xColor,
    @JsonKey(name: 'x-cover') final String? xCover,
    @JsonKey(name: 'x-favorite-type') final String? xFavoriteType,
    @JsonKey(name: 'x-http-params') final Map<String, String>? xHttpParams,
    @JsonKey(name: 'x-icon-url') final String? xIconUrl,
    @JsonKey(name: 'x-identifier') final String? xIdentifier,
    @JsonKey(name: 'x-is-active') final bool? xIsActive,
    @JsonKey(name: 'x-is-default') final bool? xIsDefault,
    @JsonKey(name: 'x-is-dirty') final bool? xIsDirty,
    @JsonKey(name: 'x-subtitle') final String? xSubtitle,
    @JsonKey(name: 'x-summary') final String? xSummary,
    @JsonKey(name: 'x-target-audience') final String? xTargetAudience,
    @JsonKey(name: 'x-teaser') final String? xTeaser,
    @JsonKey(name: 'x-type') final XType? xType,
    @JsonKey(name: 'x-value-dirty') final int? xValueDirty,
    @JsonKey(name: 'x-value') final int? xValue,
    @JsonKey(includeFromJson: false, includeToJson: false) final int? xTocLevel,
    @JsonKey(includeFromJson: false, includeToJson: false, defaultValue: false)
    final bool? xIsCurrentToc,
  }) = _Properties;

  factory Properties.fromJson(final Map<String, dynamic> json) => _$PropertiesFromJson(json);

  const Properties._();
}
