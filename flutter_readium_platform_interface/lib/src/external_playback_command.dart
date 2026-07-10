import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'utils/jsonable.dart';

/// A playback command received from system media controls, such as headphones,
/// the iOS Control Center, or the Android media session / notification.
@immutable
class ReadiumExternalPlaybackCommand implements JSONable {
  const ReadiumExternalPlaybackCommand({
    required this.action,
    this.position,
  });

  factory ReadiumExternalPlaybackCommand.fromJson(final Map<String, dynamic> map) {
    final jsonObject = Map<String, dynamic>.of(map);
    final position = jsonObject.optNullableInt('position', remove: true);

    return ReadiumExternalPlaybackCommand(
      action: ExternalPlaybackCommandAction.fromString(
        jsonObject.optString('action', remove: true),
      ),
      position: position != null ? Duration(milliseconds: position) : null,
    );
  }

  /// The requested playback action.
  final ExternalPlaybackCommandAction action;

  /// Requested playback position for seek-to commands, relative to the
  /// configured control-panel timebase.
  final Duration? position;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('action', action.name)
    ..putOpt('position', position?.inMilliseconds);

  @override
  String toString() => 'ReadiumExternalPlaybackCommand(action=$action, position=$position)';
}

/// Playback commands emitted by [FlutterReadiumPlatform.onExternalPlaybackCommand].
enum ExternalPlaybackCommandAction {
  play,
  pause,
  seekForward,
  seekBackward,
  seekTo,
  next,
  previous,
  unknown;

  static ExternalPlaybackCommandAction fromString(final String action) =>
      ExternalPlaybackCommandAction.values.firstWhereOrNull(
        (e) => e.name.toLowerCase() == action.toLowerCase(),
      ) ??
      ExternalPlaybackCommandAction.unknown;
}
