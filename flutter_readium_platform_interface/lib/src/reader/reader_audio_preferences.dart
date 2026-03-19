import 'package:collection/collection.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';

import '../../flutter_readium_platform_interface.dart';

class AudioPreferences with EquatableMixin implements JSONable {
  factory AudioPreferences.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final volume = jsonObject.optNullableDouble('volume', remove: true);
    final speed = jsonObject.optNullableDouble('speed', remove: true);
    final pitch = jsonObject.optNullableDouble('pitch', remove: true);
    final seekInterval = jsonObject.optNullableDouble('seekInterval', remove: true);
    final allowExternalSeeking = jsonObject.optNullableBoolean('allowExternalSeeking', remove: true);
    final updateIntervalSecs = jsonObject.optNullableDouble('updateIntervalSecs', remove: true);
    final controlPanelInfoTypeStr = jsonObject.optNullableString('controlPanelInfoType', remove: true);
    final controlPanelInfoType = controlPanelInfoTypeStr?.let((it) => ControlPanelInfoType.fromOptString(it));
    return AudioPreferences(
      volume: volume,
      speed: speed,
      pitch: pitch,
      seekInterval: seekInterval,
      allowExternalSeeking: allowExternalSeeking,
      updateIntervalSecs: updateIntervalSecs,
      controlPanelInfoType: controlPanelInfoType,
    );
  }

  const AudioPreferences({
    this.volume,
    this.speed,
    this.pitch,
    this.seekInterval,
    this.allowExternalSeeking,
    this.controlPanelInfoType,
    this.updateIntervalSecs,
  });

  final double? volume;
  final double? speed;
  final double? pitch;
  final double? seekInterval;
  final bool? allowExternalSeeking;
  final double? updateIntervalSecs;
  final ControlPanelInfoType? controlPanelInfoType;

  @override
  Map<String, dynamic> toJson() => {
    'volume': volume,
    'speed': speed,
    'pitch': pitch,
    'seekInterval': seekInterval,
    'allowExternalSeeking': allowExternalSeeking,
    'updateIntervalSecs': updateIntervalSecs,
    'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
  };

  @override
  List<Object?> get props => [
    volume,
    speed,
    pitch,
    seekInterval,
    allowExternalSeeking,
    updateIntervalSecs,
    controlPanelInfoType,
  ];

  AudioPreferences copyWith({
    double? volume,
    double? speed,
    double? pitch,
    double? seekInterval,
    bool? allowExternalSeeking,
    double? updateIntervalSecs,
    ControlPanelInfoType? controlPanelInfoType,
  }) => AudioPreferences(
    volume: volume ?? this.volume,
    speed: speed ?? this.speed,
    pitch: pitch ?? this.pitch,
    seekInterval: seekInterval ?? this.seekInterval,
    allowExternalSeeking: allowExternalSeeking ?? this.allowExternalSeeking,
    updateIntervalSecs: updateIntervalSecs ?? this.updateIntervalSecs,
    controlPanelInfoType: controlPanelInfoType ?? this.controlPanelInfoType,
  );
}

enum ControlPanelInfoType {
  standard,
  standardWCh,
  chapterTitleAuthor,
  chapterTitle,
  titleChapter;

  static ControlPanelInfoType? fromOptString(final String type) =>
      ControlPanelInfoType.values.firstWhereOrNull((e) => e.toString().split('.').last == type);
}
