import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';
import '../state/publication_bloc.dart';
import '../state/text_settings_bloc.dart';
import '../state/tts_settings_bloc.dart';
import 'index.dart';

class TtsSettingsWidget extends StatelessWidget {
  const TtsSettingsWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    final ttsSettingsBloc = context.watch<TtsSettingsBloc>();
    final state = ttsSettingsBloc.state;
    final languages = context.watch<PublicationBloc>().state.publication?.metadata.languages ?? [];
    // `null` stands in for "no declared language" — a single default voice picker.
    final voiceLanguages = languages.isEmpty ? <String?>[null] : languages;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
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
                  child: Text('Text-to-Speech Settings', style: TextStyle(fontSize: 25)),
                ),
              ),
            ),
            const Divider(),
            ListItemWidget(
              label: 'Speed: ${state.speed.toStringAsFixed(2)}x',
              child: Slider(
                key: const ValueKey('tts_speed_slider'),
                value: state.speed,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: state.speed.toStringAsFixed(2),
                onChanged: (value) => ttsSettingsBloc.add(ChangeSpeed(value)),
              ),
            ),
            ListItemWidget(
              label: 'Pitch: ${state.pitch.toStringAsFixed(2)}',
              child: Slider(
                key: const ValueKey('tts_pitch_slider'),
                value: state.pitch,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: state.pitch.toStringAsFixed(2),
                onChanged: (value) => ttsSettingsBloc.add(ChangePitch(value)),
              ),
            ),
            const Divider(),
            _SectionHeader(title: 'Voice'),
            if (!kIsWeb && Platform.isIOS)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'On iOS, only the most recently selected voice below takes effect — '
                  'per-language voice switching is not yet supported by the platform.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            if (!state.voicesLoaded)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              )
            else if (state.availableVoices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No voices available'),
              )
            else
              for (final language in voiceLanguages)
                ListItemWidget(
                  label: language ?? 'Default voice',
                  child: _VoiceDropdown(language: language),
                ),
            const Divider(),
            _SectionHeader(title: 'Highlight'),
            ListItemWidget(
              label: 'Color',
              child: ThemeSelectorWidget(themes: highlights, isHighlight: true),
            ),
            ListItemWidget(
              label: 'Utterance',
              child: BlocSelector<TextSettingsBloc, TextSettingsState, DecorationStyle?>(
                selector: (state) => state.utteranceStyle,
                builder: (context, utteranceStyle) => SegmentedButton<DecorationStyle?>(
                  key: const ValueKey('utterance_style_selector'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: null, label: Text('Off')),
                    ButtonSegment(value: DecorationStyle.highlight, label: Text('Fill')),
                    ButtonSegment(value: DecorationStyle.underline, label: Text('Line')),
                    ButtonSegment(value: DecorationStyle.spotlight, label: Text('Spot')),
                  ],
                  selected: {utteranceStyle},
                  onSelectionChanged: (values) =>
                      context.read<TextSettingsBloc>().add(ChangeUtteranceStyle(values.isEmpty ? null : values.first)),
                ),
              ),
            ),
            ListItemWidget(
              label: 'Range',
              child: BlocSelector<TextSettingsBloc, TextSettingsState, DecorationStyle?>(
                selector: (state) => state.rangeStyle,
                builder: (context, rangeStyle) => SegmentedButton<DecorationStyle?>(
                  key: const ValueKey('range_style_selector'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: null, label: Text('Off')),
                    ButtonSegment(value: DecorationStyle.highlight, label: Text('Fill')),
                    ButtonSegment(value: DecorationStyle.underline, label: Text('Line')),
                    ButtonSegment(value: DecorationStyle.spotlight, label: Text('Spot')),
                  ],
                  selected: {rangeStyle},
                  onSelectionChanged: (values) =>
                      context.read<TextSettingsBloc>().add(ChangeRangeStyle(values.isEmpty ? null : values.first)),
                ),
              ),
            ),
            const Divider(),
            TextButton(
              key: const ValueKey('tts_settings_close_button'),
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

class _VoiceDropdown extends StatelessWidget {
  const _VoiceDropdown({required this.language});

  final String? language;

  @override
  Widget build(BuildContext context) {
    final ttsSettingsBloc = context.watch<TtsSettingsBloc>();
    final state = ttsSettingsBloc.state;

    final matchingVoices = state.availableVoices.where((v) => v.language == language).toList();
    final voices = matchingVoices.isNotEmpty ? matchingVoices : state.availableVoices;

    final selected = state.voicesByLanguage[language];
    final selectedVoice = voices.firstWhereOrNull((v) => v.identifier == selected);

    return DropdownButton<ReaderTTSVoice>(
      value: selectedVoice,
      hint: const Text('Select voice'),
      onChanged: (voice) {
        if (voice != null) {
          ttsSettingsBloc.add(ChangeVoiceForLanguage(language, voice.identifier));
        }
      },
      items: voices
          .map(
            (voice) => DropdownMenuItem<ReaderTTSVoice>(
              value: voice,
              child: Text(voice.name),
            ),
          )
          .toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
