abstract class AdditionalProperties {
  const AdditionalProperties({this.additionalProperties = const {}});

  final Map<String, dynamic> additionalProperties;

  /// Syntactic sugar to access the [additionalProperties] values by subscripting directly.
  /// `obj["layout"] == obj.additionalProperties["layout"]`
  dynamic operator [](String key) => additionalProperties[key];

  /// Helper to get a DateTime from an additional property value.
  DateTime? getAdditionalDateTime(final String key) => additionalProperties[key] != null
      ? DateTime.parse(additionalProperties[key] as String)
      : null;

  /// Safely get an additional property value of type [T].
  T? safeGetAdditionalValue<T>(final String key) {
    if (T is DateTime) {
      return getAdditionalDateTime(key) as T?;
    }

    final value = additionalProperties[key];
    if (value is T) {
      return value;
    }
    return null;
  }
}
