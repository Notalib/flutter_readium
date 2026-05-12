import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show Locator, Publication;
import 'package:flutter_readium_example/state/index.dart';

import 'progression_slider.widget.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.publication});

  final Publication publication;
  @override
  Widget build(final BuildContext context) => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
    builder: (final context, final state) {
      final isAudioBook = publication.conformsToReadiumAudiobook || publication.containsMediaOverlays == true;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ProgressionSlider(),
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
                        // Use the saved initialLocator from PublicationBloc, which may be set when opening a publication.
                        Locator? initialLocator = context.read<PublicationBloc>().state.initialLocator;

                        // DEMO: Start from the 3rd item in readingOrder.
                        // final pub = context.read<PublicationBloc>().state.publication;
                        // final fakeInitialLink = pub?.readingOrder[2];
                        // fakeInitialLocator = pub?.locatorFromLink(fakeInitialLink!);
                        isAudioBook
                            ? context.read<PlayerControlsBloc>().add(Play(fromLocator: initialLocator))
                            : context.read<PlayerControlsBloc>().add(PlayTTS(fromLocator: initialLocator));
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
                onPressed: () {
                  context.read<PlayerControlsBloc>().add(
                    state.ttsEnabled || (state.audioEnabled && isAudioBook) ? SkipToNext() : SkipToNextPage(),
                  );
                },
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
}
