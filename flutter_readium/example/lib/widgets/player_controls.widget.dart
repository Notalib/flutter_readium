import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/player_controls_bloc.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.isAudioBook});

  final bool isAudioBook;

  @override
  Widget build(final BuildContext context) => BlocBuilder<PlayerControlsBloc, PlayerControlsState>(
        builder: (final context, final state) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: () => context.read<PlayerControlsBloc>().add(SkipToPreviousChapter()),
              tooltip: 'Skip to previous chapter',
            ),
            IconButton(
              icon: const Icon(Icons.fast_rewind),
              onPressed: () => context.read<PlayerControlsBloc>().add(
                    state.ttsEnabled || isAudioBook ? SkipToPrevious() : SkipToPreviousPage(),
                  ),
              tooltip: state.ttsEnabled ? 'Skip to previous paragraph' : 'Skip to previous page',
            ),
            IconButton(
              icon: state.playing ? const Icon(Icons.pause) : const Icon(Icons.play_arrow),
              onPressed: state.playing
                  ? () => context.read<PlayerControlsBloc>().add(Pause())
                  : () => isAudioBook
                      ? context.read<PlayerControlsBloc>().add(Play())
                      : context.read<PlayerControlsBloc>().add(PlayTTS()),
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
                    state.ttsEnabled || isAudioBook ? SkipToNext() : SkipToNextPage(),
                  ),
              tooltip: state.ttsEnabled ? 'Skip to next paragraph' : 'Skip to next page',
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: () => context.read<PlayerControlsBloc>().add(SkipToNextChapter()),
              tooltip: 'Skip to next chapter',
            ),
            IconButton(
              icon: const Icon(Icons.settings_voice),
              onPressed: () => context.read<PlayerControlsBloc>().add(GetAvailableVoices()),
              tooltip: 'Change voice',
            ),
          ],
        ),
      );
}
