import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Locator, Publication, RuntimePlatform, TimebasedState;
import 'package:flutter_readium_example/state/index.dart';
import 'package:flutter_readium_example/extensions/index.dart';

import '../state/player_controls_bloc.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.publication});

  final Publication publication;
  @override
  Widget build(final BuildContext context) => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
    builder: (final context, final state) {
      final isAudioBook = publication.conformsToReadiumAudiobook || publication.containsMediaOverlays == true;

      return Column(
        children: [
          SafeArea(top: false, bottom: false, child: _buildChapterProgressSlider(context, isAudioBook)),
          SafeArea(
            top: false,
            bottom: RuntimePlatform.isAndroid && !isAudioBook ? true : false,
            child: Padding(
              padding: EdgeInsets.only(bottom: isAudioBook ? 6.0 : 20.0),
              child: _buildChapterProgress(isAudioBook),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () =>
                    context.read<PlayerControlsBloc>().add(SkipToPreviousChapter(publication: publication)),
                tooltip: 'Skip to previous chapter',
              ),
              IconButton(
                icon: const Icon(Icons.fast_rewind),
                onPressed: () => context.read<PlayerControlsBloc>().add(
                  state.ttsEnabled || (state.audioEnabled && isAudioBook) ? SkipToPrevious() : SkipToPreviousPage(),
                ),
                tooltip: state.ttsEnabled ? 'Skip to previous paragraph' : 'Skip to previous page',
              ),
              IconButton(
                icon: state.playing ? const Icon(Icons.pause) : const Icon(Icons.play_arrow),
                onPressed: state.playing
                    ? () => context.read<PlayerControlsBloc>().add(Pause())
                    : () {
                        Locator? fakeInitialLocator;
                        // DEMO: Start from the 3rd item in readingOrder.
                        // final pub = context.read<PublicationBloc>().state.publication;
                        // final fakeInitialLink = pub?.readingOrder[2];
                        // fakeInitialLocator = pub?.locatorFromLink(fakeInitialLink!);
                        isAudioBook
                            ? context.read<PlayerControlsBloc>().add(Play(fromLocator: fakeInitialLocator))
                            : context.read<PlayerControlsBloc>().add(PlayTTS(fromLocator: fakeInitialLocator));
                      },
                tooltip: state.playing ? 'Pause' : 'Play',
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                onPressed: () => context.read<PlayerControlsBloc>().add(Stop()),
                tooltip: 'Stop',
              ),
              IconButton(
                icon: const Icon(Icons.fast_forward),
                onPressed: () => context.read<PlayerControlsBloc>().add(
                  state.ttsEnabled || (state.audioEnabled && isAudioBook) ? SkipToNext() : SkipToNextPage(),
                ),
                tooltip: state.ttsEnabled ? 'Skip to next paragraph' : 'Skip to next page',
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => context.read<PlayerControlsBloc>().add(SkipToNextChapter(publication: publication)),
                tooltip: 'Skip to next chapter',
              ),
              IconButton(
                icon: const Icon(Icons.settings_voice),
                onPressed: () => context.read<PlayerControlsBloc>().add(GetAvailableVoices()),
                tooltip: 'Change voice',
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _buildChapterProgressSlider(BuildContext context, bool isAudioBook) {
    if (isAudioBook) {
      return BlocSelector<PlayerControlsBloc, PlayerControlsState, double>(
        selector: (s) => s.audioChapterProgression,
        builder: (context, value) => Slider.adaptive(value: value.clamp(0.0, 1.0), onChanged: null),
      );
    }

    return BlocSelector<PlayerControlsBloc, PlayerControlsState, double>(
      selector: (s) => s.progression,
      builder: (context, value) => Slider.adaptive(value: value.clamp(0.0, 1.0), onChanged: null),
    );
  }

  Widget _buildChapterProgress(final bool isAudiobook) => isAudiobook ? _buildAudioPosition() : _buildTextPosition();

  Widget _buildAudioPosition() => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
    buildWhen: (p, c) =>
        p.audioState != c.audioState ||
        p.audioChapterTitle != c.audioChapterTitle ||
        p.audioOffset != c.audioOffset ||
        p.audioDuration != c.audioDuration ||
        p.playing != c.playing,
    builder: (context, state) {
      final remaining = state.audioDuration > state.audioOffset
          ? state.audioDuration - state.audioOffset
          : Duration.zero;

      final isBuffering =
          (state.audioState == TimebasedState.loading || state.audioState == TimebasedState.none) && state.playing;

      final semanticsLabel =
          '${state.audioChapterTitle}, ${state.audioOffset.toShortTimeString()} elapsed, ${remaining.toShortTimeString()} remaining';

      return Semantics(
        label: semanticsLabel,
        container: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 10.0),
          child: Row(
            children: [
              Text(state.audioOffset.toShortTimeString()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: Text(
                    isBuffering ? 'Buffering' : state.audioChapterTitle,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Text('-${remaining.toShortTimeString()}'),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildTextPosition() => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
    buildWhen: (previous, current) =>
        previous.ttsEnabled != current.ttsEnabled ||
        previous.currentChapter != current.currentChapter ||
        previous.progression != current.progression,
    builder: (context, state) => MergeSemantics(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, state.ttsEnabled ? 18.0 : 0.0),
        child: Row(
          children: [
            Expanded(
              child: Text(state.currentChapter, textAlign: TextAlign.left, overflow: TextOverflow.ellipsis),
            ),
            Text(
              state.progression.toStringPercentFloor(),
              semanticsLabel: 'Have read ${state.progression.toPercent()}',
            ),
          ],
        ),
      ),
    ),
  );
}
