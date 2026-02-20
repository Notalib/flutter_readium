import 'package:equatable/equatable.dart';

import '../../flutter_readium_platform_interface.dart';

/// Represents a TTS voice from the Readium Speech repository, with properties that can be used to match against available platform voices.
/// See: https://github.com/readium/speech
class ReadiumSpeechVoice with EquatableMixin implements JSONable {
  factory ReadiumSpeechVoice.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final label = jsonObject.optString('label', remove: true);
    final name = jsonObject.optString('name', remove: true);
    final language = jsonObject.optString('language', remove: true);
    final gender = jsonObject.optString('gender', remove: true);
    final quality = (jsonObject.optJsonArray('quality', remove: true)?.cast<String>()) ?? [];
    final rate = jsonObject.optNullableDouble('rate', remove: true);
    final localizedName = jsonObject.optNullableString('localizedName', remove: true);
    final pitch = jsonObject.optNullableDouble('pitch', remove: true);
    final pitchControl = jsonObject.optNullableBoolean('pitchControl', remove: true);
    final browser = jsonObject.optJsonArray('browser', remove: true)?.cast<String>();
    final os = jsonObject.optJsonArray('os', remove: true)?.cast<String>().map((os) => os.toLowerCase()).toList();
    final preloaded = jsonObject.optNullableBoolean('preloaded', remove: true);
    final altNames = jsonObject.optJsonArray('altNames', remove: true)?.cast<String>();
    final nativeID = jsonObject
        .optJsonArray('nativeID', remove: true)
        ?.cast<String>()
        .map((e) => e.toLowerCase())
        .toList();

    return ReadiumSpeechVoice(
      label: label,
      name: name,
      localizedName: localizedName,
      language: language,
      gender: gender,
      quality: quality,
      rate: rate,
      pitch: pitch,
      pitchControl: pitchControl,
      browser: browser,
      os: os,
      preloaded: preloaded,
      altNames: altNames,
      nativeID: nativeID,
    );
  }

  const ReadiumSpeechVoice({
    required this.label,
    required this.name,
    required this.language,
    required this.gender,
    required this.quality,
    this.rate,
    this.localizedName,
    this.pitch,
    this.pitchControl,
    this.browser,
    this.os,
    this.preloaded,
    this.altNames,
    this.nativeID,
  });

  final String label;
  final String name;
  final String? localizedName;
  final String language;
  final String gender;
  final List<String> quality;
  final double? rate;
  final double? pitch;
  final bool? pitchControl;
  final List<String>? browser;
  final List<String>? os;
  final bool? preloaded;
  final List<String>? altNames;
  final List<String>? nativeID;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('label', label)
    ..put('name', name)
    ..putOpt('localizedName', localizedName)
    ..put('language', language)
    ..put('gender', gender)
    ..put('quality', quality)
    ..putOpt('rate', rate)
    ..putOpt('pitch', pitch)
    ..putOpt('pitchControl', pitchControl)
    ..putIterableIfNotEmpty('browser', browser)
    ..putIterableIfNotEmpty('os', os)
    ..putOpt('preloaded', preloaded)
    ..putIterableIfNotEmpty('altNames', altNames)
    ..putIterableIfNotEmpty('nativeID', nativeID);

  @override
  List<Object?> get props => [
    label,
    name,
    localizedName,
    language,
    gender,
    quality,
    rate,
    pitch,
    pitchControl,
    browser,
    os,
    preloaded,
    altNames,
    nativeID,
  ];
}
