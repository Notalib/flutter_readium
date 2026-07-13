import 'dart:convert' show JsonCodec;

import 'package:equatable/equatable.dart';

import '../../../utils/jsonable.dart';
import '../../../utils/readium_log.dart';
import '../index.dart';

/// Represents a single text search result within a publication.
/// Contains a [Locator] to the location of the search result, an optional chapter title, and optional page numbers.
/// This class was created to provide a simpler structure rather than sending full [LocatorCollection] over the bridge.
class TextSearchResult with Equatable implements JSONable {
  const TextSearchResult({
    required this.locator,
    this.chapterTitle,
    this.pageNumbers,
  });

  factory TextSearchResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('json cannot be null');
    }

    final jsonObject = Map<String, dynamic>.of(json);

    return TextSearchResult(
      locator: Locator.fromJsonDynamic(jsonObject['locator'])!,
      chapterTitle: jsonObject['chapterTitle'] as String?,
      pageNumbers: (jsonObject['pageNumbers'] as String?)?.split(','),
    );
  }

  static TextSearchResult? fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> json = JsonCodec().decode(jsonString);
      return TextSearchResult.fromJson(json);
    } on Exception catch (ex, st) {
      ReadiumLog.e(
        'fromJsonString: Failed to decode TextSearchResult: $jsonString',
        stackTrace: st,
      );
    }
    return null;
  }

  static TextSearchResult? fromJsonDynamic(dynamic json) {
    if (json == null) {
      return null;
    } else if (json is String) {
      return fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return TextSearchResult.fromJson(json);
    }

    ReadiumLog.e(
      'TextSearchResult.fromJsonDynamic: Unsupported json type: ${json.runtimeType}',
    );
    return null;
  }

  final Locator locator;
  final String? chapterTitle;
  final List<String>? pageNumbers;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{}
    ..put('locator', locator)
    ..putOpt('chapterTitle', chapterTitle)
    ..putIterableIfNotEmpty('pageNumbers', pageNumbers);

  @override
  List<Object?> get props => [locator, chapterTitle, pageNumbers];

  @override
  String toString() =>
      'TextSearchResult{locator: $locator, chapterTitle: $chapterTitle, '
      'pageNumbers: $pageNumbers}';
}

extension TextSearchResultExtension on TextSearchResult {
  LocatorText? get text => locator.text;
}
