import 'dart:ui';

import '../index.dart';

const localeAnnotation = LocaleConverter();

class LocaleConverter implements JsonConverter<Locale, Map<String, dynamic>> {
  const LocaleConverter();

  @override
  Locale fromJson(final Map<String, dynamic> json) {
    if (json.containsKey('countryCode')) {
      return Locale(json['languageCode'], json['countryCode']);
    }

    return Locale(json['languageCode']);
  }

  @override
  Map<String, dynamic> toJson(final Locale locale) {
    final jsonMap = <String, dynamic>{'languageCode': locale.languageCode};
    if (locale.countryCode != null) {
      jsonMap['countryCode'] = locale.countryCode;
    }

    return jsonMap;
  }
}
