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
                child: Text(
                  'Text settings',
                  style: TextStyle(fontSize: 25),
                ),
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
                    value: state.verticalScroll,
                    onChanged: (final value) {
                      textSettingsBloc.add(ToggleVerticalScroll());
                    },
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Theme',
                  child: ThemeSelectorWidget(
                    themes: themes,
                    isHighlight: false,
                  ),
                ),
                const Divider(),
                ListItemWidget(
                  label: 'Highlight',
                  child: ThemeSelectorWidget(
                    themes: highlights,
                    isHighlight: true,
                  ),
                ),
                const Divider(),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all<EdgeInsets>(
                        const EdgeInsets.symmetric(vertical: 16.0),
                      ),
                      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0.0),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 8.0,
                      children: [
                        Icon(Icons.close, size: 20),
                        // SizedBox(width: 10),
                        Text(
                          'Close',
                          style: TextStyle(fontSize: 20),
                        ),
                      ],
                    ))
              ],
            ),
          ),
        ],
      ),
    );
  }
}
