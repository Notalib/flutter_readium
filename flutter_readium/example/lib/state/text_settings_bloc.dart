import 'package:flutter/foundation.dart';
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

class ToggleBlackAndWhiteComicMode extends TextSettingsEvent {}

class ToggleDisableSynchronization extends TextSettingsEvent {}

@immutable
class TextSettingsState {
  const TextSettingsState({
    required this.verticalScroll,
    required this.fontSize,
    required this.theme,
    required this.highlight,
    this.pageMargins,
    this.blackAndWhiteComicMode = false,
    this.disableSynchronization = false,
  });

  final bool verticalScroll;
  final int fontSize;
  final TextSettingsTheme theme;
  final TextSettingsTheme highlight;
  final double? pageMargins;
  final bool blackAndWhiteComicMode;
  final bool disableSynchronization;

  @override
  String toString() =>
      'TextSettingsState(theme: $theme, fontSize: $fontSize, verticalScroll: $verticalScroll, highlight: $highlight)';

  TextSettingsState copyWith({
    final bool? verticalScroll,
    final int? fontSize,
    final TextSettingsTheme? theme,
    final TextSettingsTheme? highlight,
    final double? pageMargins,
    final bool? blackAndWhiteComicMode,
    final bool? disableSynchronization,
  }) {
    final newState = TextSettingsState(
      verticalScroll: verticalScroll ?? this.verticalScroll,
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      highlight: highlight ?? this.highlight,
      pageMargins: pageMargins ?? this.pageMargins,
      blackAndWhiteComicMode: blackAndWhiteComicMode ?? this.blackAndWhiteComicMode,
      disableSynchronization: disableSynchronization ?? this.disableSynchronization,
    );

    return newState;
  }
}

class TextSettingsBloc extends Bloc<TextSettingsEvent, TextSettingsState> {
  final FlutterReadium instance = FlutterReadium();

  void submitPreferenceUpdate() async {
    final epubPreferences = EPUBPreferences(
      fontFamily: 'Original',
      fontSize: state.fontSize,
      fontWeight: 1.0,
      scroll: state.verticalScroll,
      backgroundColor: state.theme.backgroundColor,
      textColor: state.theme.textColor,
      pageMargins: state.pageMargins,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
    );
    instance.setEPUBPreferences(epubPreferences);
  }

  void setDefaultPreferences() {
    final defaultPreferences = EPUBPreferences(
      fontFamily: 'Original',
      fontSize: state.fontSize,
      fontWeight: 1.0,
      scroll: state.verticalScroll,
      backgroundColor: state.theme.backgroundColor,
      textColor: state.theme.textColor,
      pageMargins: state.pageMargins,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
    );
    instance.setDefaultPreferences(defaultPreferences);
  }

  TextSettingsBloc()
    : super(
        TextSettingsState(
          verticalScroll: false,
          fontSize: 120,
          theme: themes[1],
          highlight: highlights[0],
          pageMargins: kIsWeb ? 35 : null,
          blackAndWhiteComicMode: false,
          disableSynchronization: false,
        ),
      ) {
    on<ChangeFontSize>((final event, final emit) {
      emit(state.copyWith(fontSize: event.value));
      submitPreferenceUpdate();
    });

    on<ToggleVerticalScroll>((final event, final emit) {
      emit(state.copyWith(verticalScroll: !state.verticalScroll));
      submitPreferenceUpdate();
    });

    on<ToggleBlackAndWhiteComicMode>((final event, final emit) {
      emit(state.copyWith(blackAndWhiteComicMode: !state.blackAndWhiteComicMode));
      submitPreferenceUpdate();
    });

    on<ToggleDisableSynchronization>((final event, final emit) {
      emit(state.copyWith(disableSynchronization: !state.disableSynchronization));
      submitPreferenceUpdate();
    });

    on<ChangeTheme>((final event, final emit) {
      emit(state.copyWith(theme: event.theme));
      submitPreferenceUpdate();
    });

    on<ChangeHighlight>((final event, final emit) async {
      emit(state.copyWith(highlight: event.highlight));

      await FlutterReadium().setDecorationStyle(
        ReaderDecorationStyle(style: DecorationStyle.highlight, tint: event.highlight.backgroundColor),
        ReaderDecorationStyle(style: DecorationStyle.underline, tint: event.highlight.textColor),
      );
    });

    on<OpenPubSuccess>((final event, final emit) {
      submitPreferenceUpdate();
    });
  }
}
