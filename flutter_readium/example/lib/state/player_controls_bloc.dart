// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

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

class TogglePlayingState extends PlayerControlsEvent {
  TogglePlayingState({required this.isPlaying});
  bool isPlaying;
}

class SkipToNext extends PlayerControlsEvent {}

class SkipToPrevious extends PlayerControlsEvent {}

class SkipToNextChapter extends PlayerControlsEvent {
  SkipToNextChapter({required this.publication});
  Publication publication;
}

class SkipToPreviousChapter extends PlayerControlsEvent {
  SkipToPreviousChapter({required this.publication});
  Publication publication;
}

class SkipToNextPage extends PlayerControlsEvent {}

class SkipToPreviousPage extends PlayerControlsEvent {}

class GoToLocator extends PlayerControlsEvent {
  GoToLocator(this.locator);

  final Locator locator;
}

class GetAvailableVoices extends PlayerControlsEvent {}

class UpdateCurrentTocHref extends PlayerControlsEvent {
  UpdateCurrentTocHref(this.tocHref);

  final String tocHref;
}

class PlayerControlsState {
  PlayerControlsState({
    required this.playing,
    required this.ttsEnabled,
    required this.audioEnabled,
    this.currentTocHref,
  });

  final bool playing;
  final bool ttsEnabled;
  final bool audioEnabled;
  final String? currentTocHref;

  PlayerControlsState copyWith({bool? playing, bool? ttsEnabled, bool? audioEnabled, String? currentTocHref}) =>
      PlayerControlsState(
        playing: playing ?? this.playing,
        ttsEnabled: ttsEnabled ?? this.ttsEnabled,
        audioEnabled: audioEnabled ?? this.audioEnabled,
        currentTocHref: currentTocHref ?? this.currentTocHref,
      );

  PlayerControlsState togglePlay(final bool playing) => copyWith(playing: playing);

  PlayerControlsState toggleTTSEnabled(final bool ttsEnabled, final String? tocHref) =>
      copyWith(playing: ttsEnabled && playing, ttsEnabled: ttsEnabled, currentTocHref: tocHref ?? currentTocHref);

  PlayerControlsState toggleAudioEnabled(final bool audioEnabled, final String? tocHref) =>
      copyWith(playing: audioEnabled && playing, audioEnabled: audioEnabled, currentTocHref: tocHref ?? currentTocHref);

  PlayerControlsState setTocHref(final String tocHref) => copyWith(currentTocHref: tocHref);

  PlayerControlsState stop() =>
      PlayerControlsState(playing: false, ttsEnabled: false, audioEnabled: false, currentTocHref: null);
}

class PlayerControlsBloc extends Bloc<PlayerControlsEvent, PlayerControlsState> {
  StreamSubscription? timebasedStateSub;
  StreamSubscription? currentTocHrefSub;
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

    // NOTE: This does not include the tocHref for the initial locator.
    currentTocHrefSub =
        Rx.merge([
          instance.onTimebasedPlayerStateChanged.map((s) => s.currentLocator?.locations?.tocHref),
          instance.onTextLocatorChanged.map((l) => l.locations?.tocHref),
        ]).whereNotNull().distinct().debounceTime(const Duration(milliseconds: 50)).listen((tocHref) {
          if (tocHref != state.currentTocHref) {
            debugPrint('Current TOC href: $tocHref');
            add(UpdateCurrentTocHref(tocHref));
          }
        });

    readerStatusSub = instance.onReaderStatusChanged.listen((status) {
      debugPrint('onReaderStatusChanged: ${status.name}');
    });

    on<TogglePlayingState>((final event, final emit) async {
      emit(state.togglePlay(event.isPlaying));
    });

    on<PlayTTS>((final event, final emit) async {
      if (!state.ttsEnabled) {
        await instance.ttsEnable(TTSPreferences(speed: 1.2));
        await instance.play(event.fromLocator);
        emit(state.toggleTTSEnabled(true, event.fromLocator?.locations?.tocHref));
      } else {
        await instance.resume();
      }
    });

    on<Play>((final event, final emit) async {
      if (!state.audioEnabled) {
        await instance.audioEnable(
          prefs: AudioPreferences(speed: 1.5, seekInterval: 10),
          fromLocator: event.fromLocator,
        );
        emit(state.toggleAudioEnabled(true, event.fromLocator?.locations?.tocHref));
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
      emit(state.stop());
    });

    on<SkipToNext>((final event, final emit) => instance.next());

    on<SkipToPrevious>((final event, final emit) => instance.previous());

    on<SkipToNextChapter>((final event, final emit) {
      if (state.currentTocHref == null) {
        R2Log.e("No currentTocHref in state, cannot skip to next TOC chapter");
        return null;
      }
      return instance.skipToNextTOC(publication: event.publication, currentTocHref: state.currentTocHref!);
    });

    on<SkipToPreviousChapter>((final event, final emit) {
      if (state.currentTocHref == null) {
        R2Log.e("No currentTocHref in state, cannot skip to previous TOC chapter");
        return null;
      }
      return instance.skipToPreviousTOC(publication: event.publication, currentTocHref: state.currentTocHref!);
    });

    on<SkipToNextPage>((final event, final emit) => instance.goForward());

    on<SkipToPreviousPage>((final event, final emit) => instance.goBackward());

    on<GoToLocator>((event, emit) => instance.goToLocator(event.locator));

    on<UpdateCurrentTocHref>((event, emit) async {
      emit(state.setTocHref(event.tocHref));
    });

    on<GetAvailableVoices>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();

      // Sort by identifer
      voices.sortBy((v) => v.identifier);

      for (final i in voices.groupListsBy((v) => v.language).entries) {
        debugPrint('Language: ${i.key}');
        debugPrint('  Available voices:');
        for (final v in i.value) {
          debugPrint(
            '    - ${v.identifier},name=${v.name},quality=${v.quality?.name},gender=${v.gender.name},active=${v.active},networkRequired=${v.networkRequired}',
          );
        }
      }

      final dkVoices = voices.where((v) => v.language == "da-DK").toList();

      // TODO: Demo: change to first voice matching "da-DK" language.
      final daVoice = dkVoices.lastOrNull;
      if (daVoice != null) {
        await instance.ttsSetVoice(daVoice.identifier, daVoice.language);
      }
    });

    @override
    // ignore: unused_element
    Future<void> close() async {
      await timebasedStateSub?.cancel();
      await readerStatusSub?.cancel();
      await currentTocHrefSub?.cancel();
      super.close();
    }
  }

  Stream<ReadiumTimebasedState> get timebasedStateStream => instance.onTimebasedPlayerStateChanged;

  final FlutterReadium instance = FlutterReadium();
}
