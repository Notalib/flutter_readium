import '../index.dart';

part 'labels.freezed.dart';
part 'labels.g.dart';

/// PartOf: [Authentication Json Schema](https://drafts.opds.io/schema/authentication.schema.json)

@freezedExcludeUnion
abstract class Labels with _$Labels {
  @r2JsonSerializable
  const factory Labels({
    final String? login,
    final String? password,
  }) = _Labels;

  factory Labels.fromJson(final Map<String, dynamic> json) => _$LabelsFromJson(json);
}
