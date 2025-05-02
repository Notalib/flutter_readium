import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../extensions/index.dart';
import '../state/index.dart';

class ThemeSelectorWidget extends StatelessWidget {
  const ThemeSelectorWidget({
    required this.themes,
    required this.isHighlight,
    super.key,
  });

  final List<TextSettingsTheme> themes;
  final bool isHighlight;

  @override
  Widget build(final BuildContext context) => BlocBuilder<TextSettingsBloc, TextSettingsState>(
        builder: (final context, final state) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ToggleButtons(
            isSelected: themes
                .map(
                  (final itemTheme) => itemTheme == (isHighlight ? state.highlight : state.theme),
                )
                .toList(),
            selectedBorderColor: (isHighlight ? state.highlight : state.theme).textColor,
            borderWidth: 4.0,
            borderColor: Colors.transparent,
            onPressed: (final index) {
              if (isHighlight) {
                context.read<TextSettingsBloc>().add(ChangeHighlight(themes[index]));
              } else {
                context.read<TextSettingsBloc>().add(ChangeTheme(themes[index]));
              }
            },
            children: themes
                .map(
                  (final itemTheme) => Container(
                    width: 80,
                    height: 80,
                    color: itemTheme.backgroundColor,
                    child: Center(
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: itemTheme.textColor,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );
}
