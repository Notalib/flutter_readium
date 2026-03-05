// NOTE: This is a Nota type
import 'package:equatable/equatable.dart';

import '../../../utils/jsonable.dart';
import '../index.dart';

class TextSearchResult with EquatableMixin implements JSONable {
  const TextSearchResult({required this.locator, this.chapterTitle, this.pageNumbers});

  final Locator locator;
  final String? chapterTitle;
  final List<String>? pageNumbers;

  factory TextSearchResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw ArgumentError('json cannot be null');
    }

    final jsonObject = Map<String, dynamic>.of(json);

    return TextSearchResult(
      locator: Locator.fromJson(jsonObject['locator'] as Map<String, dynamic>)!,
      chapterTitle: jsonObject['chapterTitle'] as String?,
      pageNumbers: (jsonObject['pageNumbers'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{}
    ..put('locator', locator.toJson())
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
