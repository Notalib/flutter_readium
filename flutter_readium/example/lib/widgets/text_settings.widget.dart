import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../extensions/text_settings_theme.dart';
import '../state/text_settings_bloc.dart';
import 'index.dart';

class TextSettingsWidget extends StatelessWidget {
  const TextSettingsWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    final textSettingsBloc = context.watch<TextSettingsBloc>();
    final state = textSettingsBloc.state;

    return SafeArea(
      child: Wrap(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Semantics(
              header: true,
              child: const Align(
                alignment: Alignment.center,
                child: Text('Text settings', style: TextStyle(fontSize: 25)),
              ),
            ),
          ),
          const Divider(),
          SingleChildScrollView(
            child: Column(
              children: [
                ListItemWidget(
                  label: 'Font size',
                  child: Slider(
                    key: const ValueKey('font_size_slider'),
                    value: state.fontSize.toDouble(),
                    min: 70.0,
                    max: 200.0,
                    divisions: 10,
                    label: state.fontSize.toString(),
                    onChanged: (final value) {
                      textSettingsBloc.add(ChangeFontSize(value.toInt()));
                    },
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Vertical Scroll',
                  isVerticalAlignment: true,
                  child: Switch(
                    key: const ValueKey('vertical_scroll_switch'),
                    value: state.scroll,
                    onChanged: (final value) {
                      textSettingsBloc.add(ToggleScrollMode());
                    },
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Black and White Comic Mode',
                  isVerticalAlignment: true,
                  child: Switch(
                    key: const ValueKey('bw_comic_mode_switch'),
                    value: state.blackAndWhiteComicMode,
                    onChanged: (final value) {
                      textSettingsBloc.add(ToggleBlackAndWhiteComicMode());
                    },
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Disable Synchronization',
                  isVerticalAlignment: true,
                  child: Switch(
                    key: const ValueKey('disable_sync_switch'),
                    value: state.disableSynchronization,
                    onChanged: (final value) {
                      textSettingsBloc.add(ToggleDisableSynchronization());
                    },
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Theme',
                  child: ThemeSelectorWidget(themes: themes, isHighlight: false),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Highlight',
                  child: ThemeSelectorWidget(themes: highlights, isHighlight: true),
                ),
                const Divider(),
                TextButton(
                  key: const ValueKey('text_settings_close_button'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
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
                      // SizedBox(width: 10),
                      Text('Close', style: TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
