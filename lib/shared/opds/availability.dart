import '../index.dart';

part 'availability.freezed.dart';
part 'availability.g.dart';

/// Indicated the availability of a given resource.
///
/// PartOf: [Properties Json Schema](https://drafts.opds.io/schema/properties.schema.json)

@freezedExcludeUnion
abstract class Availability with _$Availability {
  @r2JsonSerializable
  const factory Availability({
    /// Indicated the availability of a given resource.
    required final OPDSState state,

    /// Timestamp for the previous state change.
    @dateTimeLocal final DateTime? since,

    /// Timestamp for the next state change.
    @dateTimeLocal final DateTime? until,
  }) = _Availability;

  factory Availability.fromJson(final Map<String, dynamic> json) => _$AvailabilityFromJson(json);
}
