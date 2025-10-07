import '_index.dart';

class ReadiumTimebasedState {
  ReadiumTimebasedState({
    required this.state,
    this.currentPosition,
    this.currentBuffered,
    this.currentDuration,
    this.currentLocator,
  });

  factory ReadiumTimebasedState.fromJsonMap(final Map<String, dynamic> map) => ReadiumTimebasedState(
        state: TimebasedState.values.firstWhereOrNull((v) => v == map['state']) ?? TimebasedState.failure,
        currentPosition: map['currentPosition'] is int ? Duration(milliseconds: map['currentPosition']) : null,
        currentBuffered: map['currentBuffered'] is int ? Duration(milliseconds: map['currentBuffered']) : null,
        currentDuration: map['currentDuration'] is int ? Duration(milliseconds: map['currentDuration']) : null,
        currentLocator: map['currentLocator'] is String ? Locator.fromJson(map['currentLocator']) : null,
      );

  TimebasedState state;
  Duration? currentPosition;
  Duration? currentBuffered;
  Duration? currentDuration;
  Locator? currentLocator;
}
