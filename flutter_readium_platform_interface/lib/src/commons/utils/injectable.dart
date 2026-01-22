class Injectable {
  const Injectable(this.rawValue);
  static const Injectable script = Injectable('scripts');
  static const Injectable font = Injectable('fonts');
  static const Injectable style = Injectable('styles');
  static const List<Injectable> values = [script, font, style];
  final String rawValue;

  @override
  String toString() => rawValue;
}
