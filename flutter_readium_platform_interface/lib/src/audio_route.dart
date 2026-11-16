import 'package:meta/meta.dart';

import 'utils/jsonable.dart';

/// The kind of output the device is currently playing audio to.
enum ReadiumAudioRouteType {
  builtIn,
  wired,
  bluetooth,
  airPlay,
  carPlay,
  other;

  static ReadiumAudioRouteType fromString(final String type) =>
      ReadiumAudioRouteType.values.asNameMap()[type] ?? ReadiumAudioRouteType.other;
}

/// The current audio output route, as emitted by
/// [FlutterReadiumPlatform.onAudioRouteChanged].
@immutable
class ReadiumAudioRoute implements JSONable {
  const ReadiumAudioRoute({required this.type, required this.name});

  factory ReadiumAudioRoute.fromJson(final Map<String, dynamic> map) => ReadiumAudioRoute(
    type: ReadiumAudioRouteType.fromString(map.optString('type')),
    name: map.optString('name'),
  );

  /// The kind of output device.
  final ReadiumAudioRouteType type;

  /// The user-visible name of the output, such as "Living Room".
  final String name;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('type', type.name)
    ..put('name', name);

  @override
  bool operator ==(Object other) => other is ReadiumAudioRoute && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);

  @override
  String toString() => 'ReadiumAudioRoute(type=$type, name=$name)';
}
