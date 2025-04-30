import '../index.dart';

/// Shared serialize config for readium objects.
const r2JsonSerializable = JsonSerializable(
  /// Don't serialize null members
  includeIfNull: false,

  /// Parse nested .toJson
  explicitToJson: true,
);
