import '../index.dart';

const contributorJson = JsonKey(
  fromJson: contributorListFromJson,
  toJson: contributorListToJson,
);

List<Contributor>? contributorListFromJson(final dynamic x) {
  if (x == null) {
    return null;
  }

  if (x is String) {
    return [
      Contributor(name: localizeStringMapFromJson(x)),
    ];
  }

  if (x is Map) {
    return [Contributor.fromJson(x as Map<String, dynamic>)];
  }

  if (x is List && x.isNotEmpty) {
    return [
      for (final e in x) ...contributorListFromJson(e)!,
    ];
  }

  return null;
}

dynamic contributorListToJson(final List<Contributor>? x) {
  if (x == null) {
    return null;
  }

  if (x.length == 1) {
    final contributor = x[0];

    final name = contributor.name;

    if (name is String &&
        contributor.sortAs == null &&
        (contributor.role == null || contributor.role!.isEmpty) &&
        contributor.position == null &&
        (contributor.links == null || contributor.links!.isEmpty)) {
      return contributor.name;
    }

    return contributor.toJson();
  }

  return x.map((final e) => e.toJson()).toList();
}
