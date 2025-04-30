import '../index.dart';

const localizeStringMapJson = JsonKey(
  fromJson: localizeStringMapFromJson,
  toJson: localizeStringMapToJson,
);

const localizeStringMapJsonNullable = JsonKey(
  fromJson: localizeStringMapFromJsonNullable,
  toJson: localizeStringMapToJsonNullable,
);

const localizeStringListJson = JsonKey(
  fromJson: localizeStringListFromJson,
  toJson: localizeStringListToJson,
);

Map<String, String>? localizeStringMapFromJsonNullable(final dynamic x) {
  if (x == null) {
    return null;
  }

  return localizeStringMapFromJson(x);
}

dynamic localizeStringMapToJsonNullable(final Map<String, String>? x) {
  if (x == null) {
    return null;
  }

  return localizeStringMapToJson(x);
}

List<String>? localizeStringListFromJson(final dynamic x) {
  if (x == null) {
    return null;
  }

  if (x is String) {
    _isValidTag(x);

    return [x];
  }

  if (x is List) {
    return x.where((final e) => _isValidTag(e)).map((final e) => e.toString()).toList();
  }

  return null;
}

Map<String, String> localizeStringMapFromJson(final dynamic x) {
  if (x is Map) {
    if (x.isEmpty) {
      throw Exception('Map should have minimum 1 property!');
    }

    x.forEach((final k, final v) {
      _isValidTag(k);
    });

    return Map<String, String>.from(x);
  }

  return <String, String>{
    'und': x is String ? x : '',
  };
}

dynamic localizeStringMapToJson(final Map<String, String> x) {
  if (x.keys.length == 1 && x['und'] != null) {
    return x['und'];
  }

  return x;
}

dynamic localizeStringListToJson(final List<String>? x) {
  if (x == null) {
    return null;
  }

  if (x.length == 1) {
    return x[0];
  }

  return x;
}

final RegExp regExpBCP47Tag = RegExp(
  r'^((?<grandfathered>(en-GB-oed|i-ami|i-bnn|i-default|i-enochian|i-hak|i-klingon|i-lux|i-mingo|i-navajo|i-pwn|i-tao|i-tay|i-tsu|sgn-BE-FR|sgn-BE-NL|sgn-CH-DE)|(art-lojban|cel-gaulish|no-bok|no-nyn|zh-guoyu|zh-hakka|zh-min|zh-min-nan|zh-xiang))|((?<language>([A-Za-z]{2,3}(-(?<extlang>[A-Za-z]{3}(-[A-Za-z]{3}){0,2}))?)|[A-Za-z]{4}|[A-Za-z]{5,8})(-(?<script>[A-Za-z]{4}))?(-(?<region>[A-Za-z]{2}|[0-9]{3}))?(-(?<variant>[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3}))*(-(?<extension>[0-9A-WY-Za-wy-z](-[A-Za-z0-9]{2,8})+))*(-(?<privateUse>x(-[A-Za-z0-9]{1,8})+))?)|(?<privateUse2>x(-[A-Za-z0-9]{1,8})+))$',
);

bool _isValidTag(final dynamic x) {
  if (x is String && regExpBCP47Tag.hasMatch(x)) {
    return true;
  }

  throw Exception('Value is not a valid BCP 47 tag! value: $x');
}
