// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'dart:ui';

import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/jsonable.dart';
import '../../utils/readium_log.dart';

@immutable
class Translation {
  const Translation(this.string);
  final String string;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Translation && runtimeType == other.runtimeType && string == other.string;

  @override
  int get hashCode => string.hashCode;

  @override
  String toString() => string;
}

/// A potentially localized (multilingual) string.
///
/// The translations are indexed by a BCP 47 language tag.
@immutable
class LocalizedString with EquatableMixin implements JSONable {
  const LocalizedString({this.translations = const {}});

  factory LocalizedString.fromJson(Map<String, dynamic> json) {
    final translations = <String?, String>{};
    for (final key in json.keys) {
      final string = json.optNullableString(key);
      if (string == null) {
        ReadiumLog.i('invalid localized string object $json');
      } else {
        translations[key] = string;
      }
    }

    return LocalizedString.fromStrings(translations);
  }

  /// BCP-47 tag for an undefined language.
  static const String undefinedLanguage = 'und';

  static LocalizedString fromStrings(Map<String?, String> strings) =>
      LocalizedString(translations: strings.map((key, value) => MapEntry(key, Translation(value))));

  static LocalizedString fromJsonString(String input) => fromString(input);

  static LocalizedString fromString(String input) => LocalizedString(translations: {null: Translation(input)});

  static LocalizedString empty() => const LocalizedString();

  /// Parses a [LocalizedString] from its RWPM JSON representation.
  /// If the localized string can't be parsed, a warning will be logged.
  ///
  /// The RWPM JSON shape (BCP 47 language tag pattern shortened for readability):
  ///
  /// ```json
  /// "anyOf": [
  ///   { "type": "string" },
  ///   {
  ///     "description": "The language in a language map must be a valid BCP 47 tag.",
  ///     "type": "object",
  ///     "patternProperties": {
  ///       "^<bcp47-tag>$": { "type": "string" }
  ///     },
  ///     "additionalProperties": false,
  ///     "minProperties": 1
  ///   }
  /// ]
  /// ```
  static LocalizedString? fromJsonDynamic(dynamic json) {
    if (json == null) {
      return null;
    }
    if (json is String) {
      return LocalizedString.fromJsonString(json);
    }
    if (json is Map<String, dynamic>) {
      return LocalizedString.fromJson(json);
    }
    ReadiumLog.i('invalid localized string object');
    return null;
  }

  final Map<String?, Translation> translations;

  /// The default translation for this localized string.
  Translation get defaultTranslation => getOrFallback(null) ?? Translation('');

  /// The default translation string for this localized string.
  /// This is a shortcut for apps.
  String get string => defaultTranslation.string;

  /// Returns the first translation for the given [language] BCP–47 tag.
  /// If not found, then fallback:
  ///    1. on the default [Locale]
  ///    2. on the undefined language
  ///    3. on the English language
  ///    4. the first translation found
  Translation? getOrFallback(String? language) =>
      translations[language] ??
      translations[PlatformDispatcher.instance.locale.toString()] ??
      translations[null] ??
      translations[undefinedLanguage] ??
      translations['en'] ??
      translations.keys.firstOrNull?.let((it) => translations[it]);

  /// Returns a new [LocalizedString] after adding (or replacing) the translation with the given
  /// [language].
  LocalizedString copyWithString(String language, String string) =>
      copyWith(translations: Map.from(translations)..putIfAbsent(language, () => Translation(string)));

  /// Returns a new [LocalizedString] after applying the [transform] function to each language.
  LocalizedString mapLanguages(String Function(String?, Translation) transform) => copyWith(
    translations: translations.map((language, translation) => MapEntry(transform(language, translation), translation)),
  );

  /// Returns a new [LocalizedString] after applying the [transform] function to each translation.
  LocalizedString mapTranslations(Translation Function(String?, Translation) transform) => copyWith(
    translations: translations.map((language, translation) => MapEntry(language, transform(language, translation))),
  );

  LocalizedString copyWith({Map<String?, Translation>? translations}) =>
      LocalizedString(translations: translations ?? {});

  /// Serializes a [LocalizedString] to its RWPM JSON representation.
  @override
  Map<String, String> toJson() =>
      translations.map((language, translation) => MapEntry(language ?? undefinedLanguage, translation.string));

  @override
  List get props => [translations];

  @override
  String toString() {
    ReadiumLog.w(
      'LocalizedString toString() is for debug purposes only, use .string or getOrFallback(language) instead',
    );

    return 'LocalizedString($translations)';
  }
}
