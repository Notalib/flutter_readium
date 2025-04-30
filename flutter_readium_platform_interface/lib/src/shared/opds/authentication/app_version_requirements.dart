import '../../index.dart';

part 'app_version_requirements.freezed.dart';
part 'app_version_requirements.g.dart';

@freezedExcludeUnion
abstract class AppVersionRequirements with _$AppVersionRequirements {
  const factory AppVersionRequirements({
    /// Minimum supported build number.
    final int? minAppVersion,

    /// Deprecated build number.
    final int? deprecatedAppVersion,
    final String? deprecatedAppMessage,
  }) = _AppVersionRequirements;

  factory AppVersionRequirements.fromJson(final Map<String, dynamic> json) =>
      _$AppVersionRequirementsFromJson(json);
}
