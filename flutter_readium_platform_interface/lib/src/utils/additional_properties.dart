import 'package:collection/collection.dart';

abstract class AdditionalProperties {
  const AdditionalProperties({this.additionalProperties = const {}});

  final Map<String, dynamic> additionalProperties;

  /// Syntactic sugar to access the [additionalProperties] values by subscripting directly.
  /// `obj["layout"] == obj.additionalProperties["layout"]`
  dynamic operator [](String key) => additionalProperties[key];

  T? getAdditionalEnum<T extends Enum>(String key, List<T> enumValues) {
    final value = additionalProperties[key];
    return value is String ? enumValues.firstWhereOrNull((v) => v.name == value) : null;
  }

  /// Helper to get a DateTime from an additional property value.
  DateTime? getAdditionalDateTime(final String key) =>
      additionalProperties[key] != null ? DateTime.parse(additionalProperties[key] as String) : null;

  /// Safely get an additional property value of type [T].
  T? safeGetAdditionalValue<T>(final String key) {
    if (T is DateTime) {
      return getAdditionalDateTime(key) as T?;
    }
    if (T is Enum) {
      // This is a bit of a hack to get the enum values list from the type T.
      final enumValues = (T as dynamic).values as List<Enum>;
      return getAdditionalEnum(key, enumValues) as T?;
    }

    final value = additionalProperties[key];
    if (value is T) {
      return value;
    }
    return null;
  }
}
