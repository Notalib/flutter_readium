// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'package:flutter_readium/flutter_readium.dart';

@immutable
abstract class PlayerControlsEvent {
  const PlayerControlsEvent();
}

@immutable
class PlayTTS extends PlayerControlsEvent {
  const PlayTTS({this.fromLocator, this.ttsPreferences});

  final Locator? fromLocator;
  final TTSPreferences? ttsPreferences;
}

@immutable
class Play extends PlayerControlsEvent {
  const Play({this.fromLocator, this.audioPreferences});

  final Locator? fromLocator;
  final AudioPreferences? audioPreferences;
}

@immutable
class Pause extends PlayerControlsEvent {}

@immutable
class Stop extends PlayerControlsEvent {}

@immutable
class TogglePlayingState extends PlayerControlsEvent {
  const TogglePlayingState({required this.isPlaying});
  final bool isPlaying;
}

@immutable
class SkipToNext extends PlayerControlsEvent {
  const SkipToNext();
}

@immutable
class SkipToPrevious extends PlayerControlsEvent {
  const SkipToPrevious();
}

@immutable
class SkipToNextChapter extends PlayerControlsEvent {
  const SkipToNextChapter();
}

@immutable
class SkipToPreviousChapter extends PlayerControlsEvent {}

@immutable
class SkipToNextPage extends PlayerControlsEvent {}

@immutable
class SkipToPreviousPage extends PlayerControlsEvent {}

@immutable
class GoToLocator extends PlayerControlsEvent {
  const GoToLocator(this.locator);

  final Locator locator;
}

@immutable
class PlayerControlsState {
  const PlayerControlsState({required this.playing, required this.ttsEnabled, required this.audioEnabled});

  final bool playing;
  final bool ttsEnabled;
  final bool audioEnabled;

  Future<PlayerControlsState> togglePlay(final bool playing) async {
    return copyWith(playing: playing);
  }

  Future<PlayerControlsState> toggleTTSEnabled(final bool ttsEnabled) async {
    return copyWith(ttsEnabled: ttsEnabled, playing: ttsEnabled && playing);
  }

  Future<PlayerControlsState> toggleAudioEnabled(final bool audioEnabled) async {
    return copyWith(audioEnabled: audioEnabled, playing: audioEnabled && playing);
  }

  PlayerControlsState copyWith({final bool? playing, final bool? ttsEnabled, final bool? audioEnabled}) =>
      PlayerControlsState(
        playing: playing ?? this.playing,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
        audioEnabled: audioEnabled ?? this.audioEnabled,
      );
}

class PlayerControlsBloc extends Bloc<PlayerControlsEvent, PlayerControlsState> {
  StreamSubscription? timebasedStateSub;
  StreamSubscription? readerStatusSub;

  PlayerControlsBloc() : super(PlayerControlsState(playing: false, ttsEnabled: false, audioEnabled: false)) {
    timebasedStateSub = instance.onTimebasedPlayerStateChanged
        .map((state) => state.state)
        .distinct()
        .debounceTime(const Duration(milliseconds: 50))
        .listen((playerState) {
          debugPrint('onTimebasedPlayerStateChanged: ${playerState.name}');

          switch (playerState) {
            case TimebasedState.playing:
            case TimebasedState.loading:
              if (state.playing != true) {
                add(TogglePlayingState(isPlaying: true));
              }
            case TimebasedState.paused:
            case TimebasedState.ended:
            case TimebasedState.failure:
            case TimebasedState.none:
              add(TogglePlayingState(isPlaying: false));
          }
        });

    readerStatusSub = instance.onReaderStatusChanged.listen((status) {
      debugPrint('onReaderStatusChanged: ${status.name}');
    });

    on<TogglePlayingState>((final event, final emit) async {
      emit(await state.togglePlay(event.isPlaying));
    });

    on<PlayTTS>((final event, final emit) async {
      if (!state.ttsEnabled) {
        await instance.ttsEnable(event.ttsPreferences ?? TTSPreferences(speed: 1.2));
        await instance.play(event.fromLocator);
        emit(await state.toggleTTSEnabled(true));
      } else {
        await instance.resume();
      }
    });

    on<Play>((final event, final emit) async {
      if (!state.audioEnabled) {
        await instance.audioEnable(
          prefs: event.audioPreferences ?? AudioPreferences(speed: 1.5, seekInterval: 10),
          fromLocator: event.fromLocator,
        );
        emit(await state.toggleAudioEnabled(true));
        await instance.play(event.fromLocator);
      } else {
        await instance.resume();
      }
    });

    on<Pause>((final event, final emit) async {
      if (state.playing) {
        await instance.pause();
      } else {
        await instance.resume();
      }
    });

    on<Stop>((final event, final emit) async {
      await instance.stop();
      emit(await state.toggleTTSEnabled(false));
      emit(await state.toggleAudioEnabled(false));
    });

    on<SkipToNext>((final event, final emit) => instance.next());

    on<SkipToPrevious>((final event, final emit) => instance.previous());

    on<SkipToNextChapter>((final event, final emit) => instance.skipToNext());

    on<SkipToPreviousChapter>((final event, final emit) => instance.skipToPrevious());

    on<SkipToNextPage>((final event, final emit) => instance.goForward());

    on<SkipToPreviousPage>((final event, final emit) => instance.goBackward());

    on<GoToLocator>((event, emit) => instance.goToLocator(event.locator));

    @override
    // ignore: unused_element
    Future<void> close() async {
      await timebasedStateSub?.cancel();
      await readerStatusSub?.cancel();
      super.close();
    }
  }

  Stream<ReadiumTimebasedState> get timebasedStateStream => instance.onTimebasedPlayerStateChanged;

  final FlutterReadium instance = FlutterReadium();
}
