import '../index.dart';

part 'acquisition.freezed.dart';
part 'acquisition.g.dart';

/// OPDS Acquisition Object.
///
/// Indirect acquisition provides a hint for the expected media type that will
/// be acquired after additional steps.
///
/// [Acquisition Json Schema](https://drafts.opds.io/schema/acquisition-object.schema.json)

@freezedExcludeUnion
abstract class Acquisition with _$Acquisition {
  @r2JsonSerializable
  const factory Acquisition({
    required final String type,
    final List<Acquisition>? child,
  }) = _Acquisition;

  factory Acquisition.fromJson(final Map<String, dynamic> json) => _$AcquisitionFromJson(json);
}
