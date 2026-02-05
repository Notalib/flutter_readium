import 'package:json_annotation/json_annotation.dart';

import 'enums.dart';
import 'shared/publication/locator.dart';
import 'utils/jsonable.dart';

class ReadiumTimebasedState implements JSONable {
  const ReadiumTimebasedState({
    required this.state,
    this.currentOffset,
    this.currentBuffered,
    this.currentDuration,
    this.currentLocator,
  });

  factory ReadiumTimebasedState.fromJson(final Map<String, dynamic> map) {
    final jsonObject = Map<String, dynamic>.of(map);

    final state = jsonObject.optEnumFromString<TimebasedState>(
      'state',
      TimebasedState.values,
      fallback: TimebasedState.none,
      remove: true,
    )!;

    final currentOffset = jsonObject.optNullableInt('currentOffset', remove: true);
    final currentBuffered = jsonObject.optNullableInt('currentBuffered', remove: true);
    final currentDuration = jsonObject.optNullableInt('currentDuration', remove: true);

    final currentLocator = Locator.fromJsonDynamic(jsonObject.opt('currentLocator', remove: true));

    return ReadiumTimebasedState(
      state: state,
      currentOffset: currentOffset != null ? Duration(milliseconds: currentOffset) : null,
      currentBuffered: currentBuffered != null ? Duration(milliseconds: currentBuffered) : null,
      currentDuration: currentDuration != null ? Duration(milliseconds: currentDuration) : null,
      currentLocator: currentLocator,
    );
  }

  @override
  String toString() =>
      'ReadiumTimebasedState($state,offset=$currentOffset,duration=$currentDuration,buffered=$currentBuffered,'
      'href=${currentLocator?.href},'
      'progression=${currentLocator?.locations?.progression},'
      'totalProgression=${currentLocator?.locations?.totalProgression})';

  /// Current time-based player state.
  final TimebasedState state;

  /// Playback offset in the current audio file.
  final Duration? currentOffset;

  /// Duration buffered of the current file.
  final Duration? currentBuffered;

  /// Total duration of the current file.
  final Duration? currentDuration;

  /// Current Locator in the publication being played.
  final Locator? currentLocator;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'state': state.name,
    if (currentOffset != null) 'currentOffset': currentOffset!.inMilliseconds,
    if (currentBuffered != null) 'currentBuffered': currentBuffered!.inMilliseconds,
    if (currentDuration != null) 'currentDuration': currentDuration!.inMilliseconds,
    if (currentLocator != null) 'currentLocator': currentLocator?.toJson(),
  };

  ReadiumTimebasedState copyWith({
    TimebasedState? state,
    Duration? currentOffset,
    Duration? currentBuffered,
    Duration? currentDuration,
    Locator? currentLocator,
  }) => ReadiumTimebasedState(
    state: state ?? this.state,
    currentOffset: currentOffset ?? this.currentOffset,
    currentBuffered: currentBuffered ?? this.currentBuffered,
    currentDuration: currentDuration ?? this.currentDuration,
    currentLocator: currentLocator ?? this.currentLocator,
  );
}

class ReadiumTimebasedStateJsonConverter extends JsonConverter<ReadiumTimebasedState?, Map<String, dynamic>?> {
  const ReadiumTimebasedStateJsonConverter();

  @override
  ReadiumTimebasedState? fromJson(final Map<String, dynamic>? json) => ReadiumTimebasedState.fromJson(json ?? {});

  @override
  Map<String, dynamic>? toJson(final ReadiumTimebasedState? object) => object?.toJson();
}
