import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';
import '../state/text_settings_bloc.dart';
import 'index.dart';

/// The decoration color + style pickers shared by the TTS and audio-playback
/// settings sheets. TTS has two independently-styled decorations (Utterance,
/// the currently-spoken chunk, and Range, the currently-spoken word); Media
/// Overlay / Guided Navigation playback only ever highlights one level (its
/// native `requestsHighlightAt` callback never supplies a word locator), so
/// [showRange] hides the second picker in that case.
class HighlightSettingsSection extends StatelessWidget {
  const HighlightSettingsSection({required this.showRange, super.key});

  final bool showRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeader(title: 'Highlight'),
        ListItemWidget(
          label: 'Color',
          child: ThemeSelectorWidget(themes: highlights, isHighlight: true),
        ),
        ListItemWidget(
          label: showRange ? 'Utterance' : 'Style',
          child: _DecorationStyleSelector(
            buttonKey: const ValueKey('utterance_style_selector'),
            selector: (state) => state.utteranceStyle,
            onChanged: (value) => context.read<TextSettingsBloc>().add(ChangeUtteranceStyle(value)),
          ),
        ),
        if (showRange)
          ListItemWidget(
            label: 'Range',
            child: _DecorationStyleSelector(
              buttonKey: const ValueKey('range_style_selector'),
              selector: (state) => state.rangeStyle,
              onChanged: (value) => context.read<TextSettingsBloc>().add(ChangeRangeStyle(value)),
            ),
          ),
      ],
    );
  }
}

class _DecorationStyleSelector extends StatelessWidget {
  const _DecorationStyleSelector({required this.buttonKey, required this.selector, required this.onChanged});

  final Key buttonKey;
  final DecorationStyle? Function(TextSettingsState state) selector;
  final void Function(DecorationStyle? value) onChanged;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<TextSettingsBloc, TextSettingsState, DecorationStyle?>(
      selector: selector,
      builder: (context, style) => SegmentedButton<DecorationStyle?>(
        key: buttonKey,
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(value: null, label: Text('Off')),
          ButtonSegment(value: DecorationStyle.highlight, label: Text('Fill')),
          ButtonSegment(value: DecorationStyle.underline, label: Text('Line')),
          ButtonSegment(value: DecorationStyle.spotlight, label: Text('Spot')),
        ],
        selected: {style},
        onSelectionChanged: (values) => onChanged(values.isEmpty ? null : values.first),
      ),
    );
  }
}
