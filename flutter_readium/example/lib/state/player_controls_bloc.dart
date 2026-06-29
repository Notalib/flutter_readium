// ignore_for_file: prefer_if_null_operators, public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'package:flutter_readium/flutter_readium.dart';

final _log = Logger('PlayerControlsBloc');

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
class SeekRelative extends PlayerControlsEvent {
  SeekRelative(this.seconds);

  final double seconds;
}

@immutable
class GetAvailableVoices extends PlayerControlsEvent {}

@immutable
class UpdateCurrentTocHref extends PlayerControlsEvent {
  UpdateCurrentTocHref(this.tocHref);

  final String tocHref;
}

@immutable
class SetSyncNarrationEnabled extends PlayerControlsEvent {
  SetSyncNarrationEnabled(this.enabled);

  final bool enabled;
}

@immutable
class PlayerClosed extends PlayerControlsEvent {}

class PlayerControlsState {
  PlayerControlsState({
    required this.playing,
    required this.ttsEnabled,
    required this.audioEnabled,
    required this.audioControlPanelTimebase,
    this.narrationSyncEnabled,
    this.currentTocHref,
  });

  final bool playing;
  final bool ttsEnabled;
  final bool audioEnabled;
  final ControlPanelTimebase audioControlPanelTimebase;
  final bool? narrationSyncEnabled;
  final String? currentTocHref;

  PlayerControlsState copyWith({
    bool? playing,
    bool? ttsEnabled,
    bool? audioEnabled,
    bool? narrationSyncEnabled,
    String? currentTocHref,
  }) => PlayerControlsState(
    playing: playing != null ? playing : this.playing,
    ttsEnabled: ttsEnabled != null ? ttsEnabled : this.ttsEnabled,
    audioEnabled: audioEnabled != null ? audioEnabled : this.audioEnabled,
    audioControlPanelTimebase: audioControlPanelTimebase ?? this.audioControlPanelTimebase,
    narrationSyncEnabled: narrationSyncEnabled != null ? narrationSyncEnabled : this.narrationSyncEnabled,
    currentTocHref: currentTocHref ?? this.currentTocHref,
  );

  PlayerControlsState togglePlay(final bool playing) => copyWith(playing: playing);

  PlayerControlsState toggleTTSEnabled(
    final bool ttsEnabled,
    final String? tocHref,
  ) => copyWith(
    playing: ttsEnabled && playing,
    ttsEnabled: ttsEnabled,
    currentTocHref: tocHref ?? currentTocHref,
  );

  PlayerControlsState toggleAudioEnabled(
    final bool audioEnabled,
    final String? tocHref,
  ) => copyWith(
    playing: audioEnabled && playing,
    audioEnabled: audioEnabled,
    currentTocHref: tocHref ?? currentTocHref,
  );

  PlayerControlsState setTocHref(final String tocHref) => copyWith(currentTocHref: tocHref);

  PlayerControlsState stop() => PlayerControlsState(
    playing: false,
    ttsEnabled: false,
    audioEnabled: false,
    audioControlPanelTimebase: audioControlPanelTimebase,
    currentTocHref: null,
  );
}

@immutable
class ToggleAudioControlPanelTimebase extends PlayerControlsEvent {}

class PlayerControlsBloc extends Bloc<PlayerControlsEvent, PlayerControlsState> {
  List<StreamSubscription> subscriptions = [];
  Locator? currentLocator;

  /// Broadcasts the current resource [Locator] regardless of media type, retaining
  /// the latest value so late subscribers (e.g. a slider rebuilt by the parent
  /// `BlocBuilder`) immediately receive the current progression.
  final BehaviorSubject<Locator> _currentLocatorSubject = BehaviorSubject<Locator>();

  PlayerControlsBloc()
    : super(
        PlayerControlsState(
          playing: false,
          ttsEnabled: false,
          audioEnabled: false,
          audioControlPanelTimebase: ControlPanelTimebase.chapter,
        ),
      ) {
    subscriptions.add(
      Rx.merge<Locator>([
        instance.onTextLocatorChanged,
        instance.onTimebasedPlayerStateChanged.map((s) => s.currentLocator).whereNotNull(),
      ]).listen((val) {
        currentLocator = val;
        _currentLocatorSubject.add(val);
      }),
    );

    subscriptions.add(
      instance.onNarrationSyncChanged.listen((syncEnabled) {
        _log.fine('onNarrationSyncChanged: $syncEnabled');
        add(SetSyncNarrationEnabled(syncEnabled));
      }),
    );

    subscriptions.add(
      instance.onTimebasedPlayerStateChanged
          .map((state) => state.state)
          .distinct()
          .debounceTime(const Duration(milliseconds: 50))
          .listen((playerState) {
            _log.fine('onTimebasedPlayerStateChanged: ${playerState.name}');

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
        _log.fine('onTextLocatorChanged: $locator');
      }),
    );

    // NOTE: This does not include the tocHref for the initial locator.
    subscriptions.add(
      Rx.merge([
        instance.onTimebasedPlayerStateChanged.map(
          (s) => s.currentLocator?.locations?.tocHref,
        ),
        instance.onTextLocatorChanged.map((l) => l.locations?.tocHref),
      ]).whereNotNull().distinct().debounceTime(const Duration(milliseconds: 50)).listen((tocHref) {
        if (tocHref != state.currentTocHref) {
          _log.fine('Current TOC href: $tocHref');
          add(UpdateCurrentTocHref(tocHref));
        }
      }),
    );

    subscriptions.add(
      instance.onReaderStatusChanged.listen((status) {
        _log.fine('onReaderStatusChanged: ${status.name}');
      }),
    );

    on<TogglePlayingState>((final event, final emit) async {
      emit(state.togglePlay(event.isPlaying));
    });

    on<PlayTTS>((final event, final emit) async {
      if (!state.ttsEnabled) {
        await instance.ttsEnable(TTSPreferences(speed: 1.2));
        await instance.play(event.fromLocator);
        emit(
          state.toggleTTSEnabled(true, event.fromLocator?.locations?.tocHref),
        );
      } else {
        await instance.resume();
      }
    });

    on<Play>((final event, final emit) async {
      if (!state.audioEnabled) {
        await instance.audioEnable(
          prefs: _buildAudioPreferences(state.audioControlPanelTimebase),
          fromLocator: event.fromLocator,
        );
        await instance.play(event.fromLocator);
        emit(
          state.toggleAudioEnabled(true, event.fromLocator?.locations?.tocHref),
        );
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

    on<SkipToNext>((final event, final emit) => instance.next());

    on<SkipToPrevious>((final event, final emit) => instance.previous());

    on<SkipToNextChapter>((final event, final emit) {
      if (state.currentTocHref == null) {
        ReadiumLog.e(
          "No currentTocHref in state, cannot skip to next TOC chapter",
        );
        return null;
      }
      return instance.skipToNextTOC(
        publication: event.publication,
        currentTocHref: state.currentTocHref!,
      );
    });

    on<SkipToPreviousChapter>((final event, final emit) {
      if (state.currentTocHref == null) {
        ReadiumLog.e(
          "No currentTocHref in state, cannot skip to previous TOC chapter",
        );
        return null;
      }
      return instance.skipToPreviousTOC(
        publication: event.publication,
        currentTocHref: state.currentTocHref!,
      );
    });

    on<SkipToNextPage>(
      (final event, final emit) async => await instance.goForward(),
    );

    on<SkipToPreviousPage>(
      (final event, final emit) async => await instance.goBackward(),
    );

    on<GoToLocator>(
      (event, emit) async => await instance.goToLocator(event.locator),
    );

    on<GoToProgression>(
      (event, emit) async => await instance.goToProgression(event.progression),
    );

    on<SeekRelative>(
      (event, emit) async => await instance.audioSeekBy(
        Duration(milliseconds: (event.seconds * 1000).round()),
      ),
    );

    on<UpdateCurrentTocHref>((event, emit) async {
      emit(state.setTocHref(event.tocHref));
    });

    on<SetSyncNarrationEnabled>((event, emit) async {
      emit(state.copyWith(narrationSyncEnabled: event.enabled));
    });

    on<GetAvailableVoices>((final event, final emit) async {
      final voices = await instance.ttsGetAvailableVoices();

      // Sort by identifer
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

    on<ToggleAudioControlPanelTimebase>((event, emit) async {
      final nextTimebase = state.audioControlPanelTimebase == ControlPanelTimebase.chapter
          ? ControlPanelTimebase.wholeBook
          : ControlPanelTimebase.chapter;

      emit(state.copyWith(audioControlPanelTimebase: nextTimebase));

      if (state.audioEnabled) {
        await instance.audioSetPreferences(_buildAudioPreferences(nextTimebase));
      }
    });
  }

  AudioPreferences _buildAudioPreferences(ControlPanelTimebase timebase) => AudioPreferences(
    speed: 1.5,
    seekInterval: 10,
    continuousSeeking: true,
    controlPanelTimebase: timebase,
  );

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
