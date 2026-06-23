import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart' show ControlPanelTimebase, Locator, Publication;
import 'package:flutter_readium_example/state/index.dart';

import 'progression_slider.widget.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.publication});

  final Publication publication;
  @override
  Widget build(
    final BuildContext context,
  ) => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
    builder: (final context, final state) {
      final isAudioBook = publication.isAudioBook;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ProgressionSlider(),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () => context.read<PlayerControlsBloc>().add(
                  SkipToPreviousChapter(publication: publication),
                ),
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
                        // Prefer the latest visual/timebased reader locator so playback resumes where the
                        // user actually is; fall back to the saved initialLocator from PublicationBloc
                        // (only set at open time) for the very first play after open.
                        final playerControls = context.read<PlayerControlsBloc>();
                        final Locator? fromLocator =
                            playerControls.currentLocator ?? context.read<PublicationBloc>().state.initialLocator;

                        // DEMO: Start from the 3rd item in readingOrder.
                        // final pub = context.read<PublicationBloc>().state.publication;
                        // final fakeInitialLink = pub?.readingOrder[2];
                        // fakeInitialLocator = pub?.locatorFromLink(fakeInitialLink!);
                        isAudioBook
                            ? playerControls.add(Play(fromLocator: fromLocator))
                            : playerControls.add(
                                PlayTTS(fromLocator: fromLocator),
                              );
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
                onPressed: () => context.read<PlayerControlsBloc>().add(
                  SkipToNextChapter(publication: publication),
                ),
                tooltip: 'Skip to next chapter',
              ),
              if (state.audioEnabled) ...[
                IconButton(
                  key: const ValueKey('seek_back_10s'),
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => context.read<PlayerControlsBloc>().add(SeekRelative(-10)),
                  tooltip: 'Seek back 10 s',
                ),
                IconButton(
                  key: const ValueKey('seek_forward_10s'),
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => context.read<PlayerControlsBloc>().add(SeekRelative(10)),
                  tooltip: 'Seek forward 10 s',
                ),
              ],
              if (isAudioBook)
                TextButton.icon(
                  key: const ValueKey('toggle_control_panel_timebase'),
                  icon: Icon(
                    state.audioControlPanelTimebase == ControlPanelTimebase.wholeBook
                        ? Icons.menu_book
                        : Icons.list_alt,
                  ),
                  label: Text(
                    state.audioControlPanelTimebase == ControlPanelTimebase.wholeBook
                        ? 'Timebase: Whole book'
                        : 'Timebase: chapter',
                  ),
                  onPressed: () => context.read<PlayerControlsBloc>().add(
                    ToggleAudioControlPanelTimebase(),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.settings_voice),
                onPressed: () => context.read<PlayerControlsBloc>().add(
                  GetAvailableVoices(),
                ),
                tooltip: 'Change voice',
              ),
            ],
          ),
        ],
      );
    },
  );
}
