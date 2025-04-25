import '../index.dart';

part 'subject.freezed.dart';
part 'subject.g.dart';

/// * [Doc](https://github.com/readium/webpub-manifest/tree/master/contexts/default#subjects)
//
/// * [Subject Json Schema](https://readium.org/webpub-manifest/schema/subject.schema.json)
/// * [SubjectObject Json Schema](https://readium.org/webpub-manifest/schema/subject-object.schema.json)

@freezedExcludeUnion
abstract class Subject with _$Subject {
  @r2JsonSerializable
  const factory Subject({
    /// Valid values:
    ///   String
    ///   Map<String, String>
    ///
    /// "minProperties": 1
    @localizeStringMapJson required final Map<String, String> name,
    final String? code,

    /// Used to retrieve similar publications for the given subjects.
    final List<Link>? links,

    /// "format": "uri"
    final String? scheme,

    /// Provides a string that a machine can sort.
    final String? sortAs,
  }) = _Subject;

  factory Subject.fromJson(final Map<String, dynamic> json) => _$SubjectFromJson(json);
}
