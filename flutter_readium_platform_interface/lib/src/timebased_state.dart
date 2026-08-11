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
    this.totalProgressDuration,
    this.totalDuration,
    this.currentLocator,
  });

  static const _unset = Object();

  factory ReadiumTimebasedState.fromJson(final Map<String, dynamic> map) {
    final jsonObject = Map<String, dynamic>.of(map);

    final state = TimebasedState.fromString(
      jsonObject.optString('state', remove: true),
    );

    final currentOffset = jsonObject.optNullableInt(
      'currentOffset',
      remove: true,
    );
    final currentBuffered = jsonObject.optNullableInt(
      'currentBuffered',
      remove: true,
    );
    final currentDuration = jsonObject.optNullableInt(
      'currentDuration',
      remove: true,
    );
    final totalProgressDuration = jsonObject.optNullableInt(
      'totalProgressDuration',
      remove: true,
    );
    final totalDuration = jsonObject.optNullableInt(
      'totalDuration',
      remove: true,
    );

    var currentLocator = Locator.fromJsonDynamic(
      jsonObject.opt('currentLocator', remove: true),
    );

    if (state == TimebasedState.ended && currentLocator != null) {
      // Workaround rounding error from native layer.
      // Sometimes progression and totalProgression are very close to 1.0 but not exactly, which causes confusion for
      // the UI.
      currentLocator = currentLocator.copyWithLocations(
        progression:
            currentLocator.locations?.progression?.roundToIfCloseTo(
              1.0,
              epsilon: 0.01,
            ) ??
            1.0,
        totalProgression: currentLocator.locations?.totalProgression?.roundToIfCloseTo(1.0) ?? 1.0,
      );
    }

    return ReadiumTimebasedState(
      state: state,
      currentOffset: currentOffset != null ? Duration(milliseconds: currentOffset) : null,
      currentBuffered: currentBuffered != null ? Duration(milliseconds: currentBuffered) : null,
      currentDuration: currentDuration != null ? Duration(milliseconds: currentDuration) : null,
      totalProgressDuration: totalProgressDuration != null ? Duration(milliseconds: totalProgressDuration) : null,
      totalDuration: totalDuration != null ? Duration(milliseconds: totalDuration) : null,
      currentLocator: currentLocator,
    );
  }

  @override
  String toString() =>
      'ReadiumTimebasedState($state,offset=$currentOffset,duration=$currentDuration,buffered=$currentBuffered,'
      'totalProgressDuration=$totalProgressDuration,totalDuration=$totalDuration,'
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

  /// Playback offset in the full publication, derived from total progression.
  final Duration? totalProgressDuration;

  /// Total duration of the full publication.
  final Duration? totalDuration;

  /// Current Locator in the publication being played.
  final Locator? currentLocator;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('state', state.name)
    ..putOpt('currentOffset', currentOffset?.inMilliseconds)
    ..putOpt('currentBuffered', currentBuffered?.inMilliseconds)
    ..putOpt('currentDuration', currentDuration?.inMilliseconds)
    ..putOpt('totalProgressDuration', totalProgressDuration?.inMilliseconds)
    ..putOpt('totalDuration', totalDuration?.inMilliseconds)
    ..putOpt('currentLocator', currentLocator?.toJson());

  ReadiumTimebasedState copyWith({
    Object? state = _unset,
    Object? currentOffset = _unset,
    Object? currentBuffered = _unset,
    Object? currentDuration = _unset,
    Object? totalProgressDuration = _unset,
    Object? totalDuration = _unset,
    Object? currentLocator = _unset,
  }) => ReadiumTimebasedState(
    state: identical(state, _unset) ? this.state : (state as TimebasedState?)!,
    currentOffset: identical(currentOffset, _unset) ? this.currentOffset : (currentOffset as Duration?)!,
    currentBuffered: identical(currentBuffered, _unset) ? this.currentBuffered : (currentBuffered as Duration?)!,
    currentDuration: identical(currentDuration, _unset) ? this.currentDuration : (currentDuration as Duration?)!,
    totalProgressDuration: identical(totalProgressDuration, _unset)
        ? this.totalProgressDuration
        : (totalProgressDuration as Duration?)!,
    totalDuration: identical(totalDuration, _unset) ? this.totalDuration : (totalDuration as Duration?)!,
    currentLocator: identical(currentLocator, _unset) ? this.currentLocator : (currentLocator as Locator?)!,
  );
}
