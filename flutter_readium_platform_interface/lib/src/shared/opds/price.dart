import '../index.dart';

part 'price.freezed.dart';
part 'price.g.dart';

/// The price of a publication is tied to its acquisition link.
///
/// PartOf: [Properties Json Schema](https://drafts.opds.io/schema/properties.schema.json)

@freezedExcludeUnion
abstract class Price with _$Price {
  @r2JsonSerializable
  const factory Price({
    required final Currency currency,

    /// "minimum": 0
    required final double value,
    final PricePeriod? period,
  }) = _Price;

  factory Price.fromJson(final Map<String, dynamic> json) => _$PriceFromJson(json);
}
