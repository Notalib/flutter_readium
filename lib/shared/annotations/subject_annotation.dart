import '../index.dart';

const subjectJson = JsonKey(
  fromJson: subjectListFromJson,
  toJson: subjectListToJson,
);

List<Subject>? subjectListFromJson(final dynamic x) {
  if (x == null) {
    return null;
  }

  if (x is String) {
    return [
      Subject(name: localizeStringMapFromJson(x)),
    ];
  }

  if (x is Map) {
    return [Subject.fromJson(x as Map<String, dynamic>)];
  }

  if (x is List && x.isNotEmpty) {
    return [
      for (final e in x) ...subjectListFromJson(e)!,
    ];
  }

  return null;
}

dynamic subjectListToJson(final List<Subject>? x) {
  if (x == null) {
    return null;
  }

  if (x.length == 1) {
    return x[0].toJson();
  }

  return x.map((final e) => e.toJson()).toList();
}
