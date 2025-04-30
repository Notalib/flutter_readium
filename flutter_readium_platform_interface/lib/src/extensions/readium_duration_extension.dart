extension ReadiumDurationExtension on Duration {
  double operator /(final Duration other) => inMicroseconds / other.inMicroseconds;

  String toSecondsString() => (inMicroseconds * 1e-6).toString();
}
