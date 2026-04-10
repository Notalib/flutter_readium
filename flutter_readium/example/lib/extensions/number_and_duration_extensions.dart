extension DoubleExtension on double {
  int toPercent() => (this * 100).round();

  int toPercentFloor() => (this * 100).floor();

  String toStringPercent() => '${toPercent()}%';

  String toStringPercentFloor() => '${toPercentFloor()}%';
}

extension DurationExtension on Duration {
  String _twoDigitStr(final num n) => n.toString().padLeft(2, '0');

  int get hours => inHours;
  int get minutes => inMinutes.remainder(60);
  int get seconds => inSeconds.remainder(60);

  String get hoursString => _twoDigitStr(hours);
  String get minutesString => _twoDigitStr(minutes);
  String get secondsString => _twoDigitStr(seconds);

  String toTimeString() => '$hoursString:$minutesString:$secondsString';

  String toShortTimeString() {
    final buff = StringBuffer();
    if (inHours > 0) {
      buff.write('$hoursString:');
    }
    buff
      ..write('$minutesString:')
      ..write(secondsString);

    return buff.toString();
  }
}
