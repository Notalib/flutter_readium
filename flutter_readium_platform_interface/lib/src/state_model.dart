import 'dart:convert';

import 'package:collection/collection.dart';

import 'index.dart';

// TODO: Use freezed for JSON mapping?
class ReadiumTimebasedState {
  ReadiumTimebasedState({
    required this.state,
    this.currentOffset,
    this.currentBuffered,
    this.currentDuration,
    this.currentLocator,
  });

  factory ReadiumTimebasedState.fromJsonMap(final Map<String, dynamic> map) => ReadiumTimebasedState(
    state:
        TimebasedState.values.firstWhereOrNull((v) => v.name.toLowerCase() == map['state'].toString().toLowerCase()) ??
        TimebasedState.failure,
    currentOffset: map['currentOffset'] is int ? Duration(milliseconds: map['currentOffset']) : null,
    currentBuffered: map['currentBuffered'] is int ? Duration(milliseconds: map['currentBuffered']) : null,
    currentDuration: map['currentDuration'] is int ? Duration(milliseconds: map['currentDuration']) : null,
    currentLocator: map['currentLocator'] is String
        ? Locator.fromJson(json.decode(map['currentLocator']) as Map<String, dynamic>)
        : (map['currentLocator'] is Map<String, dynamic>
              ? Locator.fromJson(map['currentLocator'] as Map<String, dynamic>)
              : null),
  );

  @override
  String toString() =>
      'ReadiumTimebasedState($state,offset=$currentOffset,duration=$currentDuration,buffered=$currentBuffered,'
      'href=${currentLocator?.href},'
      'progression=${currentLocator?.locations.progression},'
      'totalProgression=${currentLocator?.locations.totalProgression})';

  TimebasedState state;
  Duration? currentOffset;
  Duration? currentBuffered;
  Duration? currentDuration;
  Locator? currentLocator;
}
