import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../state/player_controls_bloc.dart';
import '../state/publication_bloc.dart';
import 'index.dart';

/// Playback settings for timebased audio: pure audiobooks as well as
/// Media Overlay / Guided Navigation EPUBs (pre-recorded narration synced to
/// text). The latter additionally get a [HighlightSettingsSection] since,
/// unlike a plain audiobook, there is visible text to highlight while it plays.
class AudioPlaybackSettingsWidget extends StatelessWidget {
  const AudioPlaybackSettingsWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    final playerControlsBloc = context.watch<PlayerControlsBloc>();
    final state = playerControlsBloc.state;
    final publication = context.watch<PublicationBloc>().state.publication;
    // A pure audiobook has no visible text, so there's nothing to highlight —
    // only Media Overlay / Guided Navigation publications get the section.
    final showHighlightSection = !(publication?.conformsToReadiumAudiobook ?? true);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Semantics(
                header: true,
                child: const Align(
                  alignment: Alignment.center,
                  child: Text('Playback Settings', style: TextStyle(fontSize: 25)),
                ),
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Speed: ${state.audioSpeed.toStringAsFixed(2)}x',
              child: Slider(
                key: const ValueKey('audiobook_speed_slider'),
                value: state.audioSpeed,
                min: 0.5,
                max: 3.0,
                divisions: 10,
                label: state.audioSpeed.toStringAsFixed(2),
                onChanged: (value) => playerControlsBloc.add(ChangeAudioSpeed(value)),
              ),
            ),
            // Pitch is plumbed through Dart/native on all three platforms (iOS,
            // Android, Web) but none of their audio navigators actually apply
            // it to playback — only TTS pitch (a separate code path) works.
            // Surface that honestly rather than let the slider silently no-op.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Pitch currently has no effect on audiobooks or MediaOverlay playback — '
                'not supported by Readium toolkit audio engines.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            ListItemWidget(
              label: 'Pitch: ${state.audioPitch.toStringAsFixed(2)}',
              child: Slider(
                key: const ValueKey('audiobook_pitch_slider'),
                value: state.audioPitch,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: state.audioPitch.toStringAsFixed(2),
                onChanged: (value) => playerControlsBloc.add(ChangeAudioPitch(value)),
              ),
            ),
            ListItemWidget(
              label: 'Seek Interval: ${state.audioSeekInterval.toStringAsFixed(0)}s',
              child: Slider(
                key: const ValueKey('audiobook_seek_interval_slider'),
                value: state.audioSeekInterval,
                min: 5.0,
                max: 60.0,
                divisions: 11,
                label: state.audioSeekInterval.toStringAsFixed(0),
                onChanged: (value) => playerControlsBloc.add(ChangeAudioSeekInterval(value)),
              ),
            ),
            if (showHighlightSection) ...[
              const Divider(),
              const HighlightSettingsSection(showRange: false),
            ],
            const Divider(),
            TextButton(
              key: const ValueKey('audiobook_settings_close_button'),
              onPressed: () => Navigator.of(context).pop(),
              style: ButtonStyle(
                padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(vertical: 16.0)),
                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(0.0)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8.0,
                children: [
                  Icon(Icons.close, size: 20),
                  Text('Close', style: TextStyle(fontSize: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
