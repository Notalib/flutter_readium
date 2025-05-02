import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';

abstract class TextSettingsEvent {}

class ChangeFontSize extends TextSettingsEvent {
  ChangeFontSize(this.value);
  final int value;
}

class ToggleVerticalScroll extends TextSettingsEvent {}

class ChangeTheme extends TextSettingsEvent {
  ChangeTheme(this.theme);
  final TextSettingsTheme theme;
}

class ChangeHighlight extends TextSettingsEvent {
  ChangeHighlight(this.highlight);
  final TextSettingsTheme highlight;
}

class OpenPubSuccess extends TextSettingsEvent {}

class TextSettingsState {
  TextSettingsState({
    required this.verticalScroll,
    required this.fontSize,
    required this.theme,
    required this.highlight,
  });

  bool verticalScroll;
  int fontSize;
  TextSettingsTheme theme;
  TextSettingsTheme highlight;

  @override
  String toString() =>
      'TextSettingsState(theme: $theme, fontSize: $fontSize, verticalScroll: $verticalScroll, highlight: $highlight)';

  TextSettingsState copyWith({
    final bool? verticalScroll,
    final int? fontSize,
    final TextSettingsTheme? theme,
    final TextSettingsTheme? highlight,
  }) {
    final newState = TextSettingsState(
      verticalScroll: verticalScroll ?? this.verticalScroll,
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      highlight: highlight ?? this.highlight,
    );

    // FlutterReadium().setReaderProperties(
    //   ReadiumReaderProperties(
    //     fontFamily: 'Original',
    //     fontSize: newState.fontSize,
    //     verticalScroll: newState.verticalScroll,
    //     backgroundColor: newState.theme.backgroundColor,
    //     textColor: newState.theme.textColor,
    //     highlightBackgroundColor: newState.highlight.backgroundColor,
    //     highlightForegroundColor: newState.highlight.textColor,
    //   ),
    // );

    return newState;
  }
}

class TextSettingsBloc extends Bloc<TextSettingsEvent, TextSettingsState> {
  TextSettingsBloc()
      : super(
          TextSettingsState(
            verticalScroll: false,
            fontSize: 120,
            theme: TextSettingsTheme(
              textColor: themes[8].textColor,
              backgroundColor: themes[8].backgroundColor,
            ),
            highlight: TextSettingsTheme(
              textColor: highlights[0].textColor,
              backgroundColor: highlights[0].backgroundColor,
            ),
          ),
        ) {
    on<ChangeFontSize>((final event, final emit) {
      emit(state.copyWith(fontSize: event.value));
    });

    on<ToggleVerticalScroll>((final event, final emit) {
      emit(state.copyWith(verticalScroll: !state.verticalScroll));
    });

    on<ChangeTheme>((final event, final emit) {
      emit(state.copyWith(theme: event.theme));
    });

    on<ChangeHighlight>((final event, final emit) {
      emit(state.copyWith(highlight: event.highlight));
    });

    on<OpenPubSuccess>((final event, final emit) {
      // FlutterReadium.updateState(
      //   readerProperties: ReadiumReaderProperties(
      //     fontSize: state.fontSize,
      //     verticalScroll: state.verticalScroll,
      //     backgroundColor: state.theme.backgroundColor,
      //     textColor: state.theme.textColor,
      //     highlightForegroundColor: state.highlight.textColor,
      //     highlightBackgroundColor: state.highlight.backgroundColor,
      //   ),
      // );
    });
  }
}
