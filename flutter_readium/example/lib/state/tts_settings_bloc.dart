import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:logging/logging.dart';

final _log = Logger('TtsSettingsBloc');

abstract class TtsSettingsEvent {}

@immutable
class LoadAvailableVoices extends TtsSettingsEvent {}

@immutable
class ChangeSpeed extends TtsSettingsEvent {
  ChangeSpeed(this.value);
  final double value;
}

@immutable
class ChangePitch extends TtsSettingsEvent {
  ChangePitch(this.value);
  final double value;
}

@immutable
class ChangeVoiceForLanguage extends TtsSettingsEvent {
  ChangeVoiceForLanguage(this.language, this.voiceIdentifier);
  final String? language;
  final String voiceIdentifier;
}

@immutable
class TtsSettingsState {
  const TtsSettingsState({
    this.speed = 1.0,
    this.pitch = 1.0,
    this.voicesByLanguage = const {},
    this.availableVoices = const [],
    this.voicesLoaded = false,
  });

  /// Speech rate. 1.0 is normal speed.
  final double speed;

  /// Speech pitch. 1.0 is normal pitch.
  final double pitch;

  /// Selected voice identifier per publication language. A `null` key is used
  /// when the publication declares no language and a single default voice
  /// picker is shown instead.
  final Map<String?, String> voicesByLanguage;
  final List<ReaderTTSVoice> availableVoices;
  final bool voicesLoaded;

  TtsSettingsState copyWith({
    double? speed,
    double? pitch,
    Map<String?, String>? voicesByLanguage,
    List<ReaderTTSVoice>? availableVoices,
    bool? voicesLoaded,
  }) => TtsSettingsState(
    speed: speed ?? this.speed,
    pitch: pitch ?? this.pitch,
    voicesByLanguage: voicesByLanguage ?? this.voicesByLanguage,
    availableVoices: availableVoices ?? this.availableVoices,
    voicesLoaded: voicesLoaded ?? this.voicesLoaded,
  );
}

class TtsSettingsBloc extends Bloc<TtsSettingsEvent, TtsSettingsState> {
  TtsSettingsBloc() : super(const TtsSettingsState()) {
    on<LoadAvailableVoices>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();

      // Sort by identifier.
      voices.sortBy((v) => v.identifier);

      for (final i in voices.groupListsBy((v) => v.language).entries) {
        _log.info('Language: ${i.key}');
        _log.info('  Available voices:');
        for (final v in i.value) {
          _log.info(
            '    - ${v.identifier},name=${v.name},quality=${v.quality?.name},gender=${v.gender.name},active=${v.active},networkRequired=${v.networkRequired}',
          );
        }
      }

      emit(state.copyWith(availableVoices: voices, voicesLoaded: true));
    });

    on<ChangeSpeed>((final event, final emit) async {
      emit(state.copyWith(speed: event.value));
      await _applyPreferences();
    });

    on<ChangePitch>((final event, final emit) async {
      emit(state.copyWith(pitch: event.value));
      await _applyPreferences();
    });

    on<ChangeVoiceForLanguage>((final event, final emit) async {
      final voicesByLanguage = Map<String?, String>.of(state.voicesByLanguage)
        ..[event.language] = event.voiceIdentifier;
      emit(state.copyWith(voicesByLanguage: voicesByLanguage));
      await instance.ttsSetVoice(event.voiceIdentifier, event.language).catchError((e) {
        _log.warning('ttsSetVoice failed (TTS likely not active yet): $e');
      });
    });
  }

  final FlutterReadium instance = FlutterReadium();

  Future<void> _applyPreferences() async {
    await instance.ttsSetPreferences(buildPreferences()).catchError((e) {
      _log.warning('ttsSetPreferences failed (TTS likely not active yet): $e');
    });
  }

  /// Builds the [TTSPreferences] to pass to [FlutterReadium.ttsEnable]. The
  /// `null`-language fallback entry in [TtsSettingsState.voicesByLanguage] is
  /// dropped here, since [TTSPreferences.voices] is keyed by language only.
  TTSPreferences buildPreferences() => TTSPreferences(
    speed: state.speed,
    pitch: state.pitch,
    voices: {
      for (final entry in state.voicesByLanguage.entries)
        if (entry.key != null) entry.key!: entry.value,
    },
  );
}
