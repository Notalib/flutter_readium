abstract class AdditionalProperties {
  const AdditionalProperties({this.additionalProperties = const {}});

  final Map<String, dynamic> additionalProperties;

  /// Syntactic sugar to access the [additionalProperties] values by subscripting directly.
  /// `obj["layout"] == obj.additionalProperties["layout"]`
  dynamic operator [](String key) => additionalProperties[key];
}
