import '../index.dart';

enum XType {
  recommendations,
  authors,
  subjects,

  @JsonValue('Lastmark')
  lastmark,
  @JsonValue('Bookmark')
  bookmark,
}

extension XTypeExtension on XType {
  /// Articles X Types.
  bool get isRecommendations => name == XType.recommendations.name;
  bool get isAuthors => name == XType.authors.name;
  bool get isSubjects => name == XType.subjects.name;

  /// Locator X Types.
  bool get isBookmark => name == XType.bookmark.name;
  bool get isLastmark => name == XType.lastmark.name;
}
