import 'package:meta/meta.dart';

import 'enums.dart';
import 'shared/publication/locator.dart';
import 'utils/jsonable.dart';

@immutable
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

    final state = TimebasedState.fromString(jsonObject.optString('state', remove: true)) ?? TimebasedState.none;

    final currentOffset = jsonObject.optNullableInt('currentOffset', remove: true);
    final currentBuffered = jsonObject.optNullableInt('currentBuffered', remove: true);
    final currentDuration = jsonObject.optNullableInt('currentDuration', remove: true);

    var currentLocator = Locator.fromJsonDynamic(jsonObject.opt('currentLocator', remove: true));

    if (state == TimebasedState.ended && currentLocator != null) {
      // Workaround rounding error from native layer.
      // Sometimes progression and totalProgression are very close to 1.0 but not exactly, which causes confusion for
      // the UI.
      currentLocator = currentLocator.copyWithLocations(
        progression: currentLocator.locations?.progression?.roundToIfCloseTo(1.0, epsilon: 0.01) ?? 1.0,
        totalProgression: currentLocator.locations?.totalProgression?.roundToIfCloseTo(1.0) ?? 1.0,
      );
    }

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
      'totalProgression=${currentLocator?.locations?.totalProgression}),'
      'title=${currentLocator?.title}),'
      'chapterPosition=${currentLocator?.locations?.position})';

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
  Map<String, dynamic> toJson() => {}
    ..put('state', state.name)
    ..putOpt('currentOffset', currentOffset?.inMilliseconds)
    ..putOpt('currentBuffered', currentBuffered?.inMilliseconds)
    ..putOpt('currentDuration', currentDuration?.inMilliseconds)
    ..putOpt('currentLocator', currentLocator?.toJson());

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
