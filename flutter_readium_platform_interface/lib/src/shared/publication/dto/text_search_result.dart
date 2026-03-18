// NOTE: This is a Nota type
import 'dart:convert' show JsonCodec;

import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';

import '../../../utils/jsonable.dart';
import '../index.dart';

class TextSearchResult with EquatableMixin implements JSONable {
  const TextSearchResult({required this.locator, this.chapterTitle, this.pageNumbers});

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
      _logger.e('fromJsonString: Failed to decode TextSearchResult: $jsonString', ex: ex, stacktrace: st);
    }
    return null;
  }

  static TextSearchResult? fromJsonDynamic(dynamic json) {
    if (json is String) {
      return fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return TextSearchResult.fromJson(json);
    }

    _logger.e('fromJsonDynamic: Unsupported json type: ${json.runtimeType}');
    return null;
  }

  static final FimberLog _logger = FimberLog('TextSearchResult');

  final Locator locator;
  final String? chapterTitle;
  final List<String>? pageNumbers;

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
