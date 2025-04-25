import '../../index.dart';

part 'dom_range.freezed.dart';
part 'dom_range.g.dart';

/// DomRange object for Readium.
///
/// [Json Schema](https://github.com/readium/architecture/blob/master/models/locators/extensions/html.md)
@freezedExcludeUnion
abstract class DomRange with _$DomRange {
  @r2JsonSerializable
  const factory DomRange({
    /// A serializable representation of the "start" boundary point of the DOM Range
    required final Boundary start,

    /// A serializable representation of the "end" boundary point of the DOM Range
    ///
    /// Note that end field is optional. When only the start field is specified, the domRange object
    /// represents a "collapsed" range that has identical "start" and "end" boundary points.
    final Boundary? end,
  }) = _DomRange;

  factory DomRange.fromJson(final JsonObject json) => _$DomRangeFromJson(json);
}
