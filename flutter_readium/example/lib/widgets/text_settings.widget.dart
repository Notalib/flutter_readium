import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';
import '../state/text_settings_bloc.dart';
import 'index.dart';

const List<String> _fontFamilies = ['Original', 'serif', 'sans-serif', 'monospace'];

class TextSettingsWidget extends StatelessWidget {
  const TextSettingsWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    final textSettingsBloc = context.watch<TextSettingsBloc>();
    final state = textSettingsBloc.state;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.8,
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
                    child: Text('EPUB Settings', style: TextStyle(fontSize: 25)),
                  ),
                ),
              ),
              const Divider(),

              // --- Basic Typography ---
              _SectionHeader(title: 'Typography'),
              ListItemWidget(
                label: 'Font Size',
                child: Slider(
                  key: const ValueKey('font_size_slider'),
                  value: state.fontSize.toDouble(),
                  min: 70.0,
                  max: 200.0,
                  divisions: 13,
                  label: state.fontSize.toString(),
                  onChanged: (value) {
                    textSettingsBloc.add(ChangeFontSize(value.toInt()));
                  },
                ),
              ),
              ListItemWidget(
                label: 'Font Family',
                child: DropdownMenu<String>(
                  key: const ValueKey('font_family_selector'),
                  initialSelection: state.fontFamily,
                  dropdownMenuEntries: _fontFamilies
                      .map((f) => DropdownMenuEntry(value: f, label: f))
                      .toList(),
                  onSelected: (value) {
                    if (value != null) textSettingsBloc.add(ChangeFontFamily(value));
                  },
                ),
              ),
              ListItemWidget(
                label: 'Text Align',
                child: SegmentedButton<TextAlign>(
                  key: const ValueKey('text_align_selector'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: TextAlign.start, icon: Icon(Icons.format_align_left), tooltip: 'Start'),
                    ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right), tooltip: 'Right'),
                    ButtonSegment(value: TextAlign.justify, icon: Icon(Icons.format_align_justify), tooltip: 'Justify'),
                  ],
                  selected: state.textAlign != null ? {state.textAlign!} : {},
                  onSelectionChanged: (values) {
                    textSettingsBloc.add(ChangeTextAlign(values.isEmpty ? null : values.first));
                  },
                ),
              ),
              const Divider(),

              // --- Advanced Typography (collapsible) ---
              _CollapsibleSection(
                title: 'Advanced Typography',
                children: [
                  ListItemWidget(
                    label: 'Font Weight',
                    child: Slider(
                      key: const ValueKey('font_weight_slider'),
                      value: state.fontWeight,
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      label: state.fontWeight.toStringAsFixed(1),
                      onChanged: (value) {
                        textSettingsBloc.add(ChangeFontWeight(value));
                      },
                    ),
                  ),
                  ListItemWidget(
                    label: 'Letter Spacing',
                    child: Slider(
                      key: const ValueKey('letter_spacing_slider'),
                      value: state.letterSpacing ?? 0.0,
                      min: -0.1,
                      max: 0.5,
                      divisions: 6,
                      label: (state.letterSpacing ?? 0.0).toStringAsFixed(2),
                      onChanged: (value) {
                        textSettingsBloc.add(ChangeLetterSpacing(value));
                      },
                    ),
                  ),
                  ListItemWidget(
                    label: 'Word Spacing',
                    child: Slider(
                      key: const ValueKey('word_spacing_slider'),
                      value: state.wordSpacing ?? 0.0,
                      min: 0.0,
                      max: 1.0,
                      divisions: 5,
                      label: (state.wordSpacing ?? 0.0).toStringAsFixed(2),
                      onChanged: (value) {
                        textSettingsBloc.add(ChangeWordSpacing(value));
                      },
                    ),
                  ),
                  ListItemWidget(
                    label: 'Line Height',
                    child: Slider(
                      key: const ValueKey('line_height_slider'),
                      value: state.lineHeight ?? 1.2,
                      min: 1.0,
                      max: 3.0,
                      divisions: 8,
                      label: (state.lineHeight ?? 1.2).toStringAsFixed(1),
                      onChanged: (value) {
                        textSettingsBloc.add(ChangeLineHeight(value));
                      },
                    ),
                  ),
                  ListItemWidget(
                    label: 'Paragraph Indent',
                    child: Slider(
                      key: const ValueKey('paragraph_indent_slider'),
                      value: state.paragraphIndent ?? 0.0,
                      min: 0.0,
                      max: 3.0,
                      divisions: 6,
                      label: (state.paragraphIndent ?? 0.0).toStringAsFixed(1),
                      onChanged: (value) {
                        textSettingsBloc.add(ChangeParagraphIndent(value));
                      },
                    ),
                  ),
                ],
              ),
              const Divider(),

              // --- Layout Section ---
              _SectionHeader(title: 'Layout'),
              ListItemWidget(
                label: 'Vertical Scroll',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('vertical_scroll_switch'),
                  value: state.verticalScroll,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleVerticalScroll());
                  },
                ),
              ),
              ListItemWidget(
                label: 'Columns',
                child: SegmentedButton<EpubColumnCount>(
                  key: const ValueKey('column_count_selector'),
                  segments: const [
                    ButtonSegment(value: EpubColumnCount.auto, label: Text('Auto')),
                    ButtonSegment(value: EpubColumnCount.one, label: Text('One')),
                    ButtonSegment(value: EpubColumnCount.two, label: Text('Two')),
                  ],
                  selected: {state.columnCount ?? EpubColumnCount.auto},
                  onSelectionChanged: (values) {
                    textSettingsBloc.add(ChangeColumnCount(values.first));
                  },
                ),
              ),
              ListItemWidget(
                label: 'Reading Direction',
                child: SegmentedButton<EpubReadingProgression>(
                  key: const ValueKey('reading_progression_selector'),
                  segments: const [
                    ButtonSegment(value: EpubReadingProgression.ltr, label: Text('LTR')),
                    ButtonSegment(value: EpubReadingProgression.rtl, label: Text('RTL')),
                  ],
                  selected: {state.readingProgression ?? EpubReadingProgression.ltr},
                  onSelectionChanged: (values) {
                    textSettingsBloc.add(ChangeReadingProgression(values.first));
                  },
                ),
              ),
              const Divider(),

              // --- Styling Override Section ---
              _SectionHeader(title: 'Styling'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'When Publisher Styles is ON, the book\u2019s original CSS is preserved and most custom '
                  'typography settings (font, spacing, alignment) will have no effect. '
                  'Turn it OFF to allow your custom settings to override the publisher\u2019s styles.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 4),
              ListItemWidget(
                label: 'Publisher Styles',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('publisher_styles_switch'),
                  value: state.publisherStyles,
                  onChanged: (value) {
                    textSettingsBloc.add(TogglePublisherStyles());
                  },
                ),
              ),
              ListItemWidget(
                label: 'Hyphens',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('hyphens_switch'),
                  value: state.hyphens ?? false,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleHyphens());
                  },
                ),
              ),
              ListItemWidget(
                label: 'Ligatures',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('ligatures_switch'),
                  value: state.ligatures ?? false,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleLigatures());
                  },
                ),
              ),
              ListItemWidget(
                label: 'Text Normalization',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('text_normalization_switch'),
                  value: state.textNormalization ?? false,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleTextNormalization());
                  },
                ),
              ),
              ListItemWidget(
                label: 'B&W Comic Mode',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('bw_comic_mode_switch'),
                  value: state.blackAndWhiteComicMode,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleBlackAndWhiteComicMode());
                  },
                ),
              ),
              ListItemWidget(
                label: 'Disable Synchronization',
                isVerticalAlignment: true,
                child: Switch(
                  key: const ValueKey('disable_sync_switch'),
                  value: state.disableSynchronization,
                  onChanged: (value) {
                    textSettingsBloc.add(ToggleDisableSynchronization());
                  },
                ),
              ),
              const Divider(),

              // --- Theme Section ---
              _SectionHeader(title: 'Theme'),
              ListItemWidget(
                label: 'Quick Theme',
                child: SegmentedButton<EpubThemeType?>(
                  key: const ValueKey('epub_theme_type_selector'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: EpubThemeType.light, label: Text('Light')),
                    ButtonSegment(value: EpubThemeType.dark, label: Text('Dark')),
                    ButtonSegment(value: EpubThemeType.sepia, label: Text('Sepia')),
                  ],
                  selected: {state.epubThemeType}.whereType<EpubThemeType?>().toSet(),
                  onSelectionChanged: (values) {
                    textSettingsBloc.add(ChangeEpubThemeType(values.isEmpty ? null : values.first));
                  },
                ),
              ),
              ListItemWidget(
                label: 'Color Theme',
                child: ThemeSelectorWidget(themes: themes, isHighlight: false),
              ),
              ListItemWidget(
                label: 'Image Filter',
                child: SegmentedButton<EpubImageFilter?>(
                  key: const ValueKey('image_filter_selector'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: EpubImageFilter.darken, label: Text('Darken')),
                    ButtonSegment(value: EpubImageFilter.invert, label: Text('Invert')),
                  ],
                  selected: {state.imageFilter}.whereType<EpubImageFilter?>().toSet(),
                  onSelectionChanged: (values) {
                    textSettingsBloc.add(ChangeImageFilter(values.isEmpty ? null : values.first));
                  },
                ),
              ),
              const Divider(),
              ListItemWidget(
                label: 'Highlight',
                child: ThemeSelectorWidget(themes: highlights, isHighlight: true),
              ),
              const Divider(),
              TextButton(
                key: const ValueKey('text_settings_close_button'),
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

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        initiallyExpanded: false,
        children: children,
      ),
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
