// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_readium/flutter_readium.dart';

abstract class PlayerControlsEvent {}

class PlayTTS extends PlayerControlsEvent {
  PlayTTS({this.fromLocator});

  Locator? fromLocator;
}

class Play extends PlayerControlsEvent {
  Play({this.fromLocator});

  Locator? fromLocator;
}

class Pause extends PlayerControlsEvent {}

class Stop extends PlayerControlsEvent {}

class SkipToNext extends PlayerControlsEvent {}

class SkipToPrevious extends PlayerControlsEvent {}

class SkipToNextChapter extends PlayerControlsEvent {}

class SkipToPreviousChapter extends PlayerControlsEvent {}

class SkipToNextPage extends PlayerControlsEvent {}

class SkipToPreviousPage extends PlayerControlsEvent {}

class GoToLocator extends PlayerControlsEvent {
  GoToLocator(this.locator);

  final Locator locator;
}

class GetAvailableVoices extends PlayerControlsEvent {}

class PlayerControlsState {
  PlayerControlsState({required this.playing, required this.ttsEnabled, required this.audioEnabled});
  final bool playing;
  final bool ttsEnabled;
  final bool audioEnabled;

  final FlutterReadium readium = FlutterReadium();

  Future<PlayerControlsState> togglePlay(final bool playing) async {
    final newState = PlayerControlsState(playing: playing, ttsEnabled: ttsEnabled, audioEnabled: audioEnabled);

    return newState;
  }

  Future<PlayerControlsState> toggleTTSEnabled(final bool ttsEnabled) async {
    final newState = PlayerControlsState(playing: playing, ttsEnabled: ttsEnabled, audioEnabled: audioEnabled);

    return newState;
  }

  Future<PlayerControlsState> toggleAudioEnabled(final bool audioEnabled) async {
    final newState = PlayerControlsState(playing: playing, ttsEnabled: ttsEnabled, audioEnabled: audioEnabled);

    return newState;
  }
}

class PlayerControlsBloc extends Bloc<PlayerControlsEvent, PlayerControlsState> {
  PlayerControlsBloc()
      : super(
          PlayerControlsState(
            playing: false,
            ttsEnabled: false,
            audioEnabled: false,
          ),
        ) {
    on<PlayTTS>((final event, final emit) async {
      if (!state.ttsEnabled) {
        await instance.ttsEnable(TTSPreferences(speed: 1.2));
        await instance.play(event.fromLocator);
        emit(await state.toggleTTSEnabled(true));
      } else {
        await instance.resume();
      }

      emit(await state.togglePlay(true));
    });

    on<Play>((final event, final emit) async {
      if (!state.audioEnabled) {
        await instance.audioEnable(
            prefs: AudioPreferences(speed: 1.5, seekInterval: 10), fromLocator: event.fromLocator);
        emit(await state.toggleAudioEnabled(true));
        await instance.play(event.fromLocator);
      } else {
        await instance.resume();
      }

      emit(await state.togglePlay(true));
    });

    on<Pause>((final event, final emit) async {
      if (state.playing) {
        await instance.pause();
      } else {
        await instance.resume();
      }
      emit(await state.togglePlay(false));
    });

    on<Stop>((final event, final emit) async {
      await instance.stop();
      emit(await state.toggleTTSEnabled(false));
      emit(await state.toggleAudioEnabled(false));
      emit(await state.togglePlay(false));
    });

    on<SkipToNext>((final event, final emit) => instance.next());

    on<SkipToPrevious>((final event, final emit) => instance.previous());

    on<SkipToNextChapter>((final event, final emit) => instance.skipToNext());

    on<SkipToPreviousChapter>((final event, final emit) => instance.skipToPrevious());

    on<SkipToNextPage>((final event, final emit) => instance.goRight());

    on<SkipToPreviousPage>((final event, final emit) => instance.goLeft());

    on<GoToLocator>((event, emit) => instance.goToLocator(event.locator));

    on<GetAvailableVoices>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();

      // Sort by identifer
      voices.sortBy((v) => v.identifier);

      for (final v in voices) {
        debugPrint(
            'Available language: ${v.identifier},name=${v.name},quality=${v.quality?.name},gender=${v.gender.name}');
      }

      // TODO: Demo: change to first voice matching "da-DK" language.
      final daVoice = voices.firstWhereOrNull((l) => l.language == "da-DK");
      if (daVoice != null) {
        await instance.ttsSetVoice(daVoice.identifier, null);
      }
    });
  }

  Stream<Locator> get audioLocatorStream => instance.onAudioLocatorChanged;

  Stream<ReadiumTimebasedState> get timebasedStateStream => instance.onTimebasedPlayerStateChanged;

  final FlutterReadium instance = FlutterReadium();
}
