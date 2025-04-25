import '../../index.dart';

part 'boundary.freezed.dart';
part 'boundary.g.dart';

/// Boundary object for Readium.
///
/// [Json Schema](https://github.com/readium/architecture/blob/master/models/locators/extensions/html.md)
@freezedExcludeUnion
abstract class Boundary with _$Boundary {
  @Assert('textNodeIndex >= 0')
  @Assert('charOffset == null || charOffset >= 0')
  @r2JsonSerializable
  const factory Boundary({
    /// A CSS Selector to a DOM element
    required final String cssSelector,

    /// See full description below
    required final int textNodeIndex,

    /// See full description below
    final int? charOffset,
  }) = _Boundary;

  factory Boundary.fromJson(final JsonObject json) => _$BoundaryFromJson(json);
}
