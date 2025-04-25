import '../_index.dart';

part 'readium_element.freezed.dart';
part 'readium_element.g.dart';

@freezedExcludeUnion
abstract class ReadiumElement with _$ReadiumElement {
  const ReadiumElement._();

  const factory ReadiumElement({
    required final Link link,
    required final String cssSelector,
    final int? start,
    final int? end,
    final String? text,
    final Duration? duration,
  }) = _ReadiumElement;

  factory ReadiumElement.fromJson(final Map<String, dynamic> json) =>
      _$ReadiumElementFromJson(json);

  DomRange toDomRange() => CssSelector(cssSelector).domRange(start: start ?? 0, end: end);

  Locations toLocations() => Locations(cssSelector: cssSelector);

  Locator? toLocator(final Publication publication) =>
      publication.locatorFromLink(link)?.mapLocations((final locations) {
        if (start != null) {
          return locations.copyWith(domRange: toDomRange());
        }

        return locations.copyWith(cssSelector: cssSelector);
      });

  @override
  String toString() =>
      'ReadiumSpan(${link.href},$start,$end,${text?.truncateQuote(20)},$cssSelector)';
}
