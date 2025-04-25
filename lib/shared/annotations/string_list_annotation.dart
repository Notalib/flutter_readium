import '../index.dart';

const stringListJson = JsonKey(
  fromJson: stringListFromJson,
  toJson: stringListToJson,
);

List<String>? stringListFromJson(final dynamic x) {
  if (x == null) {
    return null;
  }

  if (x is String) {
    return [x];
  }

  if (x is List) {
    return [
      for (final y in x) ...?stringListFromJson(y),
    ];
  }

  return null;
}

dynamic stringListToJson(final List<String>? x) {
  if (x == null) {
    return null;
  }

  if (x.length == 1) {
    return x[0];
  }

  return x;
}
