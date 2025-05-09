import 'package:flutter/foundation.dart';
import '../../../extensions/index.dart';

import '../../index.dart';

part 'locator.freezed.dart';
part 'locator.g.dart';

/// Locator object for Readium.
///
/// [Json Schema](https://github.com/readium/architecture/tree/master/models/locators)
@freezedExcludeUnion
abstract class Locator with _$Locator {
  @r2JsonSerializable
  const factory Locator({
    /// The URI of the resource that the Locator Object points to.
    required final String href,

    /// The media type of the resource that the Locator Object points to.
    required final String type,

    /// The title of the chapter or section which is more relevant in the context of this locator.
    final String? title,

    /// One or more alternative expressions of the location.
    final Locations? locations,

    /// Textual context of the locator.
    final LocatorText? text,

    /// TODO: extract x-properties
    @JsonKey(name: 'x-type') final XType? xType,
    @JsonKey(name: 'x-timestamp') @dateTimeLocal final DateTime? xTimestamp,
    @JsonKey(name: 'x-uuid') final String? xUuid,
    @JsonKey(name: 'x-note') final String? xNote,
  }) = _Locator;

  factory Locator.fromJson(final JsonObject json) => _$LocatorFromJson(json);

  const Locator._();

  /// Returns /path from [href] without #fragment and query parameters.
  String get hrefPath {
    final path = href.path;

    if (path == null) {
      return href;
    }

    return path;
  }

  Locations get locationsOrEmpty => locations ?? const Locations();

  Locator mapLocations(final Locations Function(Locations locations) function) =>
      copyWith(locations: function(locationsOrEmpty));

  Locator toTextLocator() {
    // WORKAROUND:
    // Sometimes readium handled any fragments as an `id` fragment and tries to scroll
    // to it as fx. [readium.scrollToId('t=287.55899999999997')] which will cause the book
    // starts from the beginning.
    // Only set id fragments to less confusing readium.
    final selector = locations?.cssSelector ?? locations?.domRange?.start.cssSelector;
    final idFragment = selector?.startsWith('#') == true ? selector!.substring(1) : null;

    return copyWith(
      // Makes sure href only contains /path.
      href: hrefPath,
      type: MediaType.html.value,
      locations: locations?.copyWith(
        fragments: idFragment == null ? null : [idFragment],
      ),
    );
  }
}
