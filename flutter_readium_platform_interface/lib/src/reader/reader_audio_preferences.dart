import 'package:collection/collection.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../flutter_readium_platform_interface.dart';

@immutable
class AudioPreferences with EquatableMixin implements JSONable {
  factory AudioPreferences.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final volume = jsonObject.optNullableDouble('volume', remove: true);
    final speed = jsonObject.optNullableDouble('speed', remove: true);
    final pitch = jsonObject.optNullableDouble('pitch', remove: true);
    final seekInterval = jsonObject.optNullableDouble(
      'seekInterval',
      remove: true,
    );
    final continuousSeeking = jsonObject.optNullableBoolean(
      'continuousSeeking',
      remove: true,
    );
    final allowExternalSeeking = jsonObject.optNullableBoolean(
      'allowExternalSeeking',
      remove: true,
    );
    final updateIntervalSecs = jsonObject.optNullableDouble(
      'updateIntervalSecs',
      remove: true,
    );
    final controlPanelInfoTypeStr = jsonObject.optNullableString(
      'controlPanelInfoType',
      remove: true,
    );
    final controlPanelTimebaseStr = jsonObject.optNullableString(
      'controlPanelTimebase',
      remove: true,
    );
    final controlPanelInfoType = controlPanelInfoTypeStr?.let(
      (it) => ControlPanelInfoType.fromOptString(it),
    );
    ControlPanelTimebase? controlPanelTimebase;
    if (controlPanelTimebaseStr != null) {
      controlPanelTimebase = ControlPanelTimebase.fromOptString(
        controlPanelTimebaseStr,
      );
      if (controlPanelTimebase == null) {
        ReadiumLog.w(
          'Unknown ControlPanelTimebase value: $controlPanelTimebaseStr, defaulting to ControlPanelTimebase.chapter.',
        );
        controlPanelTimebase = ControlPanelTimebase.chapter;
      }
    }
    return AudioPreferences(
      volume: volume,
      speed: speed,
      pitch: pitch,
      seekInterval: seekInterval,
      continuousSeeking: continuousSeeking,
      allowExternalSeeking: allowExternalSeeking,
      updateIntervalSecs: updateIntervalSecs,
      controlPanelInfoType: controlPanelInfoType,
      controlPanelTimebase: controlPanelTimebase,
    );
  }

  const AudioPreferences({
    this.volume,
    this.speed,
    this.pitch,
    this.seekInterval,
    this.continuousSeeking,
    this.allowExternalSeeking,
    this.controlPanelInfoType,
    this.controlPanelTimebase,
    this.updateIntervalSecs,
  });

  /// The volume for audio playback.
  final double? volume;

  /// The speech rate (speed) for text-to-speech. A value of 1.0 is the normal speed, less than 1.0 is slower, and greater than 1.0 is faster.
  final double? speed;

  /// The pitch for audio playback. A value of 1.0 is the normal pitch, less than 1.0 is lower, and greater than 1.0 is higher.
  final double? pitch;

  /// The interval in seconds for seeking forward/backward when the user performs a seek action (e.g., pressing a seek button).
  /// This is used to determine how much to seek when the user initiates a seek action.
  final double? seekInterval;

  /// Whether to allow continuous seeking. If true, then rewinding and fast forwarding will seek the
  /// exact specified seek interval even between resources.
  final bool? continuousSeeking;

  /// Whether to allow external seeking. If true, the app will allow seeking to positions in the audio that are not currently buffered.
  /// This may be used to enable features like chapter skipping or seeking to specific timestamps.
  final bool? allowExternalSeeking;

  /// The interval in seconds for updating the audio playback position. This is used to determine how frequently the app should update the UI or perform other actions based on the current playback position.
  final double? updateIntervalSecs;

  /// The type of information to display on the control panel during audio playback.
  final ControlPanelInfoType? controlPanelInfoType;

  /// Whether the system control panel timeline should use chapter or publication time.
  final ControlPanelTimebase? controlPanelTimebase;

  @override
  Map<String, dynamic> toJson() => {
    'volume': volume,
    'speed': speed,
    'pitch': pitch,
    'seekInterval': seekInterval,
    'continuousSeeking': continuousSeeking,
    'allowExternalSeeking': allowExternalSeeking,
    'updateIntervalSecs': updateIntervalSecs,
    'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
    'controlPanelTimebase': controlPanelTimebase?.toString().split('.').last,
  };

  @override
  List<Object?> get props => [
    volume,
    speed,
    pitch,
    seekInterval,
    continuousSeeking,
    allowExternalSeeking,
    updateIntervalSecs,
    controlPanelInfoType,
    controlPanelTimebase,
  ];

  AudioPreferences copyWith({
    double? volume,
    double? speed,
    double? pitch,
    double? seekInterval,
    bool? continuousSeeking,
    bool? allowExternalSeeking,
    double? updateIntervalSecs,
    ControlPanelInfoType? controlPanelInfoType,
    ControlPanelTimebase? controlPanelTimebase,
  }) => AudioPreferences(
    volume: volume ?? this.volume,
    speed: speed ?? this.speed,
    pitch: pitch ?? this.pitch,
    seekInterval: seekInterval ?? this.seekInterval,
    continuousSeeking: continuousSeeking ?? this.continuousSeeking,
    allowExternalSeeking: allowExternalSeeking ?? this.allowExternalSeeking,
    updateIntervalSecs: updateIntervalSecs ?? this.updateIntervalSecs,
    controlPanelInfoType: controlPanelInfoType ?? this.controlPanelInfoType,
    controlPanelTimebase: controlPanelTimebase ?? this.controlPanelTimebase,
  );
}

enum ControlPanelInfoType {
  standard,
  standardWCh,
  chapterTitleAuthor,
  chapterTitle,
  titleChapter;

  static ControlPanelInfoType? fromOptString(final String type) => ControlPanelInfoType.values.firstWhereOrNull(
    (e) => e.toString().split('.').last == type,
  );
}

enum ControlPanelTimebase {
  chapter,
  wholeBook;

  static ControlPanelTimebase? fromOptString(final String type) {
    final lower = type.toLowerCase();
    switch (lower) {
      case 'chapter':
        return ControlPanelTimebase.chapter;
      case 'wholebook':
      case 'whole_book':
        return ControlPanelTimebase.wholeBook;
      default:
        return null;
    }
  }
}
