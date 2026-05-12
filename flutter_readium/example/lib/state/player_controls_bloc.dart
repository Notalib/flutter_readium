// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'package:flutter_readium/flutter_readium.dart';

@immutable
abstract class PlayerControlsEvent {}

@immutable
class PlayTTS extends PlayerControlsEvent {
  PlayTTS({this.fromLocator});

  final Locator? fromLocator;
}

@immutable
class Play extends PlayerControlsEvent {
  Play({this.fromLocator});

  final Locator? fromLocator;
}

@immutable
class Pause extends PlayerControlsEvent {}

@immutable
class Stop extends PlayerControlsEvent {}

@immutable
class TogglePlayingState extends PlayerControlsEvent {
  TogglePlayingState({required this.isPlaying});
  final bool isPlaying;
}

@immutable
class SkipToNext extends PlayerControlsEvent {}

@immutable
class SkipToPrevious extends PlayerControlsEvent {}

@immutable
class SkipToNextChapter extends PlayerControlsEvent {
  SkipToNextChapter({required this.publication});
  final Publication publication;
}

@immutable
class SkipToPreviousChapter extends PlayerControlsEvent {
  SkipToPreviousChapter({required this.publication});
  final Publication publication;
}

@immutable
class SkipToNextPage extends PlayerControlsEvent {}

@immutable
class SkipToPreviousPage extends PlayerControlsEvent {}

@immutable
class GoToLocator extends PlayerControlsEvent {
  GoToLocator(this.locator);

  final Locator locator;
}

@immutable
class GoToProgression extends PlayerControlsEvent {
  GoToProgression(this.progression);

  final double progression;
}

@immutable
class GetAvailableVoices extends PlayerControlsEvent {}

@immutable
class UpdateCurrentTocHref extends PlayerControlsEvent {
  UpdateCurrentTocHref(this.tocHref);

  final String tocHref;
}

@immutable
class PlayerClosed extends PlayerControlsEvent {}

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
  List<StreamSubscription> subscriptions = [];
  Locator? currentLocator;

  /// Broadcasts the current resource [Locator] regardless of media type, retaining
  /// the latest value so late subscribers (e.g. a slider rebuilt by the parent
  /// `BlocBuilder`) immediately receive the current progression.
  final BehaviorSubject<Locator> _currentLocatorSubject = BehaviorSubject<Locator>();

  PlayerControlsBloc() : super(PlayerControlsState(playing: false, ttsEnabled: false, audioEnabled: false)) {
    subscriptions.add(
      Rx.merge<Locator>([
        instance.onTextLocatorChanged,
        instance.onTimebasedPlayerStateChanged.map((s) => s.currentLocator).whereNotNull(),
      ]).listen((val) {
        _currentLocatorSubject.add(val);
      }),
    );

    subscriptions.add(
      instance.onTimebasedPlayerStateChanged
          .map((state) {
            currentLocator = state.currentLocator;
            return state.state;
          })
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
                break;
              case TimebasedState.paused:
                if (state.playing != false) {
                  add(TogglePlayingState(isPlaying: false));
                }
                break;
              case TimebasedState.ended:
              case TimebasedState.failure:
              case TimebasedState.none:
                add(PlayerClosed());
                break;
            }
          }),
    );

    subscriptions.add(
      instance.onTextLocatorChanged.listen((locator) {
        debugPrint('onTextLocatorChanged: $locator');
      }),
    );

    // NOTE: This does not include the tocHref for the initial locator.
    subscriptions.add(
      Rx.merge([
        instance.onTimebasedPlayerStateChanged.map((s) => s.currentLocator?.locations?.tocHref),
        instance.onTextLocatorChanged.map((l) => l.locations?.tocHref),
      ]).whereNotNull().distinct().debounceTime(const Duration(milliseconds: 50)).listen((tocHref) {
        if (tocHref != state.currentTocHref) {
          debugPrint('Current TOC href: $tocHref');
          add(UpdateCurrentTocHref(tocHref));
        }
      }),
    );

    subscriptions.add(
      instance.onReaderStatusChanged.listen((status) {
        debugPrint('onReaderStatusChanged: ${status.name}');
      }),
    );

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
        await instance.play(event.fromLocator);
        emit(state.toggleAudioEnabled(true, event.fromLocator?.locations?.tocHref));
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

    on<PlayerClosed>((final event, final emit) async {
      emit(state.stop());
    });

    on<SkipToNext>((final event, final emit) {
      R2Log.i("SkipToNext, currentLocator: $currentLocator");
      if (currentLocator == null) {
        return instance.next();
      }

      final newProgression = (currentLocator?.locations?.progression ?? 0) + 0.2;
      if (newProgression > 1) {
        return instance.next();
      }

      return instance.goToProgression(newProgression);
    });

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

    on<SkipToNextPage>((final event, final emit) async => await instance.goForward());

    on<SkipToPreviousPage>((final event, final emit) async => await instance.goBackward());

    on<GoToLocator>((event, emit) async => await instance.goToLocator(event.locator));

    on<GoToProgression>((event, emit) async => await instance.goToProgression(event.progression));

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

    on<UpdateCurrentTocHref>((event, emit) async {
      emit(state.setTocHref(event.tocHref));
    });
  }

  @override
  Future<void> close() async {
    for (StreamSubscription sub in subscriptions) {
      await sub.cancel();
    }
    await _currentLocatorSubject.close();
    return super.close();
  }

  Stream<ReadiumTimebasedState> get timebasedStateStream => instance.onTimebasedPlayerStateChanged;

  /// Emits the current [Locator] for the active publication, regardless of media type.
  /// Backed by a [BehaviorSubject] so a single underlying subscription is reused and
  /// late subscribers receive the most recent value on subscribe.
  Stream<Locator> get currentLocatorStream => _currentLocatorSubject.stream;

  final FlutterReadium instance = FlutterReadium();
}
