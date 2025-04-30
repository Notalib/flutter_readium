import '../../index.dart';

part 'locator_text.freezed.dart';
part 'locator_text.g.dart';

/// LocatorText object for Readium.
///
/// [Json Schema](https://github.com/readium/architecture/tree/master/models/locators)
@freezedExcludeUnion
abstract class LocatorText with _$LocatorText {
  @r2JsonSerializable
  const factory LocatorText({
    /// The LocatorText after the locator.
    final String? after,

    /// The LocatorText before the locator.
    final String? before,

    /// The LocatorText at the locator.
    final String? highlight,
  }) = _LocatorText;

  factory LocatorText.fromJson(final JsonObject json) => _$LocatorTextFromJson(json);
}
