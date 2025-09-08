// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_readium/flutter_readium.dart';

abstract class PlayerControlsEvent {}

class PlayTTS extends PlayerControlsEvent {}

class PlayAudiobook extends PlayerControlsEvent {}

class Pause extends PlayerControlsEvent {}

class Stop extends PlayerControlsEvent {}

class SkipToNext extends PlayerControlsEvent {}

class SkipToPrevious extends PlayerControlsEvent {}

class SkipToNextChapter extends PlayerControlsEvent {}

class SkipToPreviousChapter extends PlayerControlsEvent {}

class SkipToNextPage extends PlayerControlsEvent {}

class SkipToPreviousPage extends PlayerControlsEvent {}

class GetAvailableVoices extends PlayerControlsEvent {}

class PlayerControlsState {
  PlayerControlsState({required this.playing, required this.ttsEnabled});
  final bool playing;
  final bool ttsEnabled;

  final FlutterReadium readium = FlutterReadium();

  Future<PlayerControlsState> togglePlay(final bool playing) async {
    final newState = PlayerControlsState(playing: playing, ttsEnabled: ttsEnabled);

    return newState;
  }

  Future<PlayerControlsState> toggleTTS(final bool ttsEnabled) async {
    final newState = PlayerControlsState(playing: playing, ttsEnabled: ttsEnabled);

    return newState;
  }
}

class PlayerControlsBloc extends Bloc<PlayerControlsEvent, PlayerControlsState> {
  PlayerControlsBloc()
      : super(
          PlayerControlsState(
            playing: false,
            ttsEnabled: false,
          ),
        ) {
    on<PlayTTS>((final event, final emit) async {
      if (!state.ttsEnabled) {
        await instance.ttsEnable(TTSPreferences(speed: 1.2));
        await instance.ttsStart(null);
        emit(await state.toggleTTS(true));
      } else {
        await instance.resume();
      }

      emit(await state.togglePlay(true));
    });

    on<PlayAudiobook>((final event, final emit) async {
      await instance.audioStart(speed: 1.5);
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
      emit(await state.toggleTTS(false));
      emit(await state.togglePlay(false));
    });

    on<SkipToNext>((final event, final emit) {
      instance.next();
    });

    on<SkipToPrevious>((final event, final emit) {
      instance.previous();
    });

    on<SkipToNextChapter>((final event, final emit) {
      instance.skipToNext();
    });

    on<SkipToPreviousChapter>((final event, final emit) {
      instance.skipToPrevious();
    });

    on<SkipToNextPage>((final event, final emit) {
      instance.goRight();
    });

    on<SkipToPreviousPage>((final event, final emit) {
      instance.goLeft();
    });

    on<GetAvailableVoices>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();

      // Sort by identifer
      voices.sortBy((v) => v.identifier);

      for (final v in voices) {
        debugPrint(
            'Available language: ${v.identifier},name=${v.name},quality=${v.quality?.name},gender=${v.gender.name}');
      }

      // Change to first voice matching "da-DK" language.
      final daVoice = voices.firstWhereOrNull((l) => l.language == "da-DK");
      if (daVoice != null) {
        await instance.ttsSetVoice(daVoice.identifier, null);
      }
    });
  }
  final FlutterReadium instance = FlutterReadium();
}
