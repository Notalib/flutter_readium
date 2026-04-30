import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';

abstract class TextSettingsEvent {}

@immutable
class ChangeFontSize extends TextSettingsEvent {
  ChangeFontSize(this.value);
  final int value;
}

@immutable
class ToggleVerticalScroll extends TextSettingsEvent {}

@immutable
class ChangeTheme extends TextSettingsEvent {
  ChangeTheme(this.theme);
  final TextSettingsTheme theme;
}

@immutable
class ChangeHighlight extends TextSettingsEvent {
  ChangeHighlight(this.highlight);
  final TextSettingsTheme highlight;
}

@immutable
class OpenPubSuccess extends TextSettingsEvent {}

@immutable
class ToggleBlackAndWhiteComicMode extends TextSettingsEvent {}

@immutable
class ToggleDisableSynchronization extends TextSettingsEvent {}

@immutable
class TextSettingsState {
  const TextSettingsState({
    required this.verticalScroll,
    required this.fontSize,
    required this.theme,
    required this.highlight,
    this.pageMargins,
    this.paragraphSpacing = 1.0,
    this.blackAndWhiteComicMode = false,
    this.disableSynchronization = false,
    this.firstElementTopMargin = 40,
  });

  final bool verticalScroll;
  final int fontSize;
  final TextSettingsTheme theme;
  final TextSettingsTheme highlight;
  final double? pageMargins;
  final double? paragraphSpacing;
  final bool blackAndWhiteComicMode;
  final bool disableSynchronization;
  final int? firstElementTopMargin;

  @override
  String toString() =>
      'TextSettingsState(theme: $theme, fontSize: $fontSize, verticalScroll: $verticalScroll, highlight: $highlight)';

  TextSettingsState copyWith({
    final bool? verticalScroll,
    final int? fontSize,
    final TextSettingsTheme? theme,
    final TextSettingsTheme? highlight,
    final double? pageMargins,
    final double? paragraphSpacing,
    final bool? blackAndWhiteComicMode,
    final bool? disableSynchronization,
    final int? firstElementTopMargin,
  }) {
    final newState = TextSettingsState(
      verticalScroll: verticalScroll ?? this.verticalScroll,
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      highlight: highlight ?? this.highlight,
      pageMargins: pageMargins ?? this.pageMargins,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      blackAndWhiteComicMode: blackAndWhiteComicMode ?? this.blackAndWhiteComicMode,
      disableSynchronization: disableSynchronization ?? this.disableSynchronization,
      firstElementTopMargin: firstElementTopMargin ?? this.firstElementTopMargin,
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
      paragraphSpacing: state.paragraphSpacing,
      // Always disable publisher styles, in order for the user preferences to be applied correctly.
      publisherStyles: false,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
      firstElementTopMargin: state.firstElementTopMargin,
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
      paragraphSpacing: state.paragraphSpacing,
      publisherStyles: false,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
      firstElementTopMargin: state.firstElementTopMargin,
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
          firstElementTopMargin: 40,
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
