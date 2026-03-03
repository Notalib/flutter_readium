import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

@immutable
abstract class TtsSettingsEvent {
  const TtsSettingsEvent();
}

@immutable
class GetTtsVoicesEvent extends TtsSettingsEvent {
  const GetTtsVoicesEvent({this.fallbackLang});
  final List<String>? fallbackLang;
}

@immutable
class SetTtsVoiceEvent extends TtsSettingsEvent {
  const SetTtsVoiceEvent(this.selectedVoice);
  final ReaderTTSVoice selectedVoice;
}

/*
@immutable
class SetTtsHighlightModeEvent extends TtsSettingsEvent {
  const SetTtsHighlightModeEvent(this.highlightMode);
  final ReadiumHighlightMode highlightMode;
}

@immutable
class ToggleTtsHighlightModeEvent extends TtsSettingsEvent {
  const ToggleTtsHighlightModeEvent();
}

class SetTtsSpeakPhysicalPageIndexEvent extends TtsSettingsEvent {
  const SetTtsSpeakPhysicalPageIndexEvent(this.speak);
  final bool speak;
}
*/

@immutable
class TtsSettingsState {
  const TtsSettingsState({
    this.voices,
    this.loaded,
    this.preferredVoices,
    this.highlightMode,
    this.ttsSpeakPhysicalPageIndex,
  });
  final List<ReaderTTSVoice>? voices;
  final bool? loaded;
  final List<ReaderTTSVoice>? preferredVoices;
  final ReadiumHighlightMode? highlightMode;
  final bool? ttsSpeakPhysicalPageIndex;

  TtsSettingsState copyWith({
    final List<ReaderTTSVoice>? voices,
    final bool? loaded,
    final List<ReaderTTSVoice>? preferredVoices,
    final ReadiumHighlightMode? highlightMode,
    final bool? ttsSpeakPhysicalPageIndex,
  }) => TtsSettingsState(
    voices: voices ?? this.voices,
    loaded: loaded ?? this.loaded,
    preferredVoices: preferredVoices ?? this.preferredVoices,
    highlightMode: highlightMode ?? this.highlightMode,
    ttsSpeakPhysicalPageIndex: ttsSpeakPhysicalPageIndex ?? this.ttsSpeakPhysicalPageIndex,
  );

  TtsSettingsState updateVoices(final List<ReaderTTSVoice> voices) => copyWith(voices: voices, loaded: true);

  TtsSettingsState updatePreferredVoices(final ReaderTTSVoice selectedVoice) {
    final preferredVoicesList = preferredVoices ?? [];
    final updatedVoices = preferredVoicesList.where((final voice) => voice.language != selectedVoice.language).toList()
      ..add(selectedVoice);

    FlutterReadium().ttsSetVoice(selectedVoice.identifier, selectedVoice.language);

    return copyWith(preferredVoices: updatedVoices);
  }

  /*
  TtsSettingsState setHighlightMode(final ReadiumHighlightMode highlightMode) {
    FlutterReadium().setHighlightMode(highlightMode);
    return copyWith(highlightMode: highlightMode);
  }

  TtsSettingsState setTtsSpeakPhysicalPageIndex(final bool speak) {
    FlutterReadium().setTtsSpeakPhysicalPageIndex(speak: speak);
    return copyWith(ttsSpeakPhysicalPageIndex: speak);
  } */
}

class TtsSettingsBloc extends Bloc<TtsSettingsEvent, TtsSettingsState> {
  TtsSettingsBloc()
    : super(
        TtsSettingsState(
          voices: [],
          loaded: false,
          preferredVoices: [],
          highlightMode: ReadiumHighlightMode.paragraph, // to reflect default in ReadiumState
          ttsSpeakPhysicalPageIndex: false,
        ),
      ) {
    on<GetTtsVoicesEvent>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();
      emit(state.updateVoices(voices));
    });

    on<SetTtsVoiceEvent>((final event, final emit) async {
      await instance.ttsSetVoice(event.selectedVoice.identifier, event.selectedVoice.language);
      emit(state.updatePreferredVoices(event.selectedVoice));
    });

    /*     on<SetTtsHighlightModeEvent>((final event, final emit) async {
      emit(state.setHighlightMode(event.highlightMode));
    });

    on<ToggleTtsHighlightModeEvent>((final event, final emit) async {
      final newHighlightMode = state.highlightMode == ReadiumHighlightMode.word
          ? ReadiumHighlightMode.paragraph
          : ReadiumHighlightMode.word;
      emit(state.setHighlightMode(newHighlightMode));
    });

    on<SetTtsSpeakPhysicalPageIndexEvent>((final event, final emit) async {
      emit(state.setTtsSpeakPhysicalPageIndex(event.speak));
    }); */
  }

  final FlutterReadium instance = FlutterReadium();
}
