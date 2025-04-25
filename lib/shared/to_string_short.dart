mixin ToStringShort {
  /// Converts to a string, leaving out null values. In objects with lots of null properties, this
  /// is shorter. Uses RegExp, so may remove too much if one of the properties is a literal string
  /// containing ', foo: null'.
  String toStringShort() => toString().replaceAllMapped(_isNullString, _removeNullString);

// This approach is cleaner, but doesn't work since toJson apparently recursively calls toJson.
// Map<String, dynamic> toJson();
//
// /// Converts to a string, leaving out null values. In objects with lots of null properties, this
// /// is shorter.
// String toStringShort() => '$runtimeType($_contents)';
//
// String get _contents => toJson().entries.where((e) => e.value != null).map((e) {
//       final value = e.value;
//       return '${e.key}:${value is ToStringShort ? value.toStringShort() : value.toString()}';
//     }).join(',');
}

// Matches things like ', foo: null, bar: null, baz: null)', capturing the external ', ' and ')'.
final _isNullString =
    RegExp(r'(\(|, )[A-Za-z_$][0-9A-Za-z_$]*: null(?:, [A-Za-z_$][0-9A-Za-z_$]*: null)*(\)|, )');

String _removeNullString(final Match match) {
  // Handles the four possible cases:
  //   '(foo: null)'   -> '()'
  //   '(foo: null, '  -> '('
  //   ', foo: null)'  -> ')'
  //   ', foo: null, ' -> ', '
  final left = match[1]; // '(' or ', '
  final right = match[2]; // ')' or ', '
  return left == ', '
      ? right!
      : right == ', '
          ? '('
          : '()';
}
