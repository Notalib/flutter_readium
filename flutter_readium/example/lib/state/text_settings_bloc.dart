import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../extensions/text_settings_theme.dart';

// Sentinel for copyWith parameters that are nullable but where null is a meaningful value.
// Using `field ?? this.field` would make it impossible to explicitly clear a field back to null,
// so instead the parameter type is widened to Object? with this sentinel as default.
// Inside copyWith: `field == _sentinel ? this.field : field as T?`
const _sentinel = Object();

abstract class TextSettingsEvent {}

@immutable
class ChangeFontSize extends TextSettingsEvent {
  ChangeFontSize(this.value);
  final int value;
}

@immutable
class ToggleScrollMode extends TextSettingsEvent {}

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
class ChangeFontFamily extends TextSettingsEvent {
  ChangeFontFamily(this.value);
  final String value;
}

@immutable
class ChangeFontWeight extends TextSettingsEvent {
  ChangeFontWeight(this.value);
  final double value;
}

@immutable
class ChangeLetterSpacing extends TextSettingsEvent {
  ChangeLetterSpacing(this.value);
  final double value;
}

@immutable
class ChangeWordSpacing extends TextSettingsEvent {
  ChangeWordSpacing(this.value);
  final double value;
}

@immutable
class ChangeLineHeight extends TextSettingsEvent {
  ChangeLineHeight(this.value);
  final double value;
}

@immutable
class ChangeTextAlign extends TextSettingsEvent {
  ChangeTextAlign(this.value);
  final TextAlign? value;
}

@immutable
class ChangeColumnCount extends TextSettingsEvent {
  ChangeColumnCount(this.value);
  final EpubColumnCount value;
}

@immutable
class ChangeReadingProgression extends TextSettingsEvent {
  ChangeReadingProgression(this.value);
  final EpubReadingProgression value;
}

@immutable
class ChangeParagraphIndent extends TextSettingsEvent {
  ChangeParagraphIndent(this.value);
  final double value;
}

@immutable
class TogglePublisherStyles extends TextSettingsEvent {}

@immutable
class ToggleHyphens extends TextSettingsEvent {}

@immutable
class ToggleLigatures extends TextSettingsEvent {}

@immutable
class ToggleTextNormalization extends TextSettingsEvent {}

@immutable
class ChangeImageFilter extends TextSettingsEvent {
  ChangeImageFilter(this.value);
  final EpubImageFilter? value;
}

@immutable
class TextSettingsState {
  const TextSettingsState({
    required this.scroll,
    required this.fontSize,
    required this.theme,
    required this.highlight,
    this.pageMargins,
    this.paragraphSpacing = 1.0,
    this.blackAndWhiteComicMode = false,
    this.disableSynchronization = false,
    this.firstElementTopMargin = 40,
    this.fontFamily = 'Original',
    this.fontWeight = 1.0,
    this.letterSpacing,
    this.wordSpacing,
    this.lineHeight,
    this.textAlign,
    this.columnCount,
    this.readingProgression,
    this.paragraphIndent,
    this.publisherStyles = false,
    this.hyphens,
    this.ligatures,
    this.textNormalization,
    this.imageFilter,
  });

  final bool scroll;
  final int fontSize;
  final TextSettingsTheme theme;
  final TextSettingsTheme highlight;
  final double? pageMargins;
  final double? paragraphSpacing;
  final bool blackAndWhiteComicMode;
  final bool disableSynchronization;
  final int? firstElementTopMargin;
  final String fontFamily;
  final double fontWeight;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? lineHeight;
  final TextAlign? textAlign;
  final EpubColumnCount? columnCount;
  final EpubReadingProgression? readingProgression;
  final double? paragraphIndent;
  final bool publisherStyles;
  final bool? hyphens;
  final bool? ligatures;
  final bool? textNormalization;
  final EpubImageFilter? imageFilter;

  @override
  String toString() => 'TextSettingsState(theme: $theme, fontSize: $fontSize, scroll: $scroll, highlight: $highlight)';

  TextSettingsState copyWith({
    final bool? scroll,
    final int? fontSize,
    final TextSettingsTheme? theme,
    final TextSettingsTheme? highlight,
    final double? pageMargins,
    final double? paragraphSpacing,
    final bool? blackAndWhiteComicMode,
    final bool? disableSynchronization,
    final int? firstElementTopMargin,
    final String? fontFamily,
    final double? fontWeight,
    final double? letterSpacing,
    final double? wordSpacing,
    final double? lineHeight,
    final Object? textAlign = _sentinel,
    final EpubColumnCount? columnCount,
    final EpubReadingProgression? readingProgression,
    final double? paragraphIndent,
    final bool? publisherStyles,
    final bool? hyphens,
    final bool? ligatures,
    final bool? textNormalization,
    final Object? imageFilter = _sentinel,
  }) {
    return TextSettingsState(
      scroll: scroll ?? this.scroll,
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
      highlight: highlight ?? this.highlight,
      pageMargins: pageMargins ?? this.pageMargins,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      blackAndWhiteComicMode: blackAndWhiteComicMode ?? this.blackAndWhiteComicMode,
      disableSynchronization: disableSynchronization ?? this.disableSynchronization,
      firstElementTopMargin: firstElementTopMargin ?? this.firstElementTopMargin,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlign: textAlign == _sentinel ? this.textAlign : textAlign as TextAlign?,
      columnCount: columnCount ?? this.columnCount,
      readingProgression: readingProgression ?? this.readingProgression,
      paragraphIndent: paragraphIndent ?? this.paragraphIndent,
      publisherStyles: publisherStyles ?? this.publisherStyles,
      hyphens: hyphens ?? this.hyphens,
      ligatures: ligatures ?? this.ligatures,
      textNormalization: textNormalization ?? this.textNormalization,
      imageFilter: imageFilter == _sentinel ? this.imageFilter : imageFilter as EpubImageFilter?,
    );
  }
}

class TextSettingsBloc extends Bloc<TextSettingsEvent, TextSettingsState> {
  final FlutterReadium instance = FlutterReadium();

  void submitPreferenceUpdate() async {
    final epubPreferences = EPUBPreferences(
      fontFamily: state.fontFamily,
      fontSize: state.fontSize,
      fontWeight: state.fontWeight,
      scroll: state.scroll,
      backgroundColor: state.theme.backgroundColor,
      textColor: state.theme.textColor,
      pageMargins: state.pageMargins,
      paragraphSpacing: state.paragraphSpacing,
      publisherStyles: state.publisherStyles,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
      firstElementTopMargin: state.firstElementTopMargin,
      letterSpacing: state.letterSpacing,
      wordSpacing: state.wordSpacing,
      lineHeight: state.lineHeight,
      textAlign: state.textAlign,
      columnCount: state.columnCount,
      readingProgression: state.readingProgression,
      paragraphIndent: state.paragraphIndent,
      hyphens: state.hyphens,
      ligatures: state.ligatures,
      textNormalization: state.textNormalization,
      imageFilter: state.imageFilter,
    );
    instance.setEPUBPreferences(epubPreferences);
  }

  void setDefaultPreferences() {
    final defaultPreferences = EPUBPreferences(
      fontFamily: state.fontFamily,
      fontSize: state.fontSize,
      fontWeight: state.fontWeight,
      scroll: state.scroll,
      backgroundColor: state.theme.backgroundColor,
      textColor: state.theme.textColor,
      pageMargins: state.pageMargins,
      paragraphSpacing: state.paragraphSpacing,
      publisherStyles: state.publisherStyles,
      blackAndWhiteComicMode: state.blackAndWhiteComicMode,
      disableSynchronization: state.disableSynchronization,
      firstElementTopMargin: state.firstElementTopMargin,
      letterSpacing: state.letterSpacing,
      wordSpacing: state.wordSpacing,
      lineHeight: state.lineHeight,
      textAlign: state.textAlign,
      columnCount: state.columnCount,
      readingProgression: state.readingProgression,
      paragraphIndent: state.paragraphIndent,
      hyphens: state.hyphens,
      ligatures: state.ligatures,
      textNormalization: state.textNormalization,
      imageFilter: state.imageFilter,
    );
    instance.setDefaultPreferences(defaultPreferences);
  }

  TextSettingsBloc()
    : super(
        TextSettingsState(
          scroll: false,
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

    on<ToggleScrollMode>((final event, final emit) {
      emit(state.copyWith(scroll: !state.scroll));
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
      emit(state.copyWith(theme: event.theme, publisherStyles: false));
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

    on<ChangeFontFamily>((event, emit) {
      emit(state.copyWith(fontFamily: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeFontWeight>((event, emit) {
      emit(state.copyWith(fontWeight: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeLetterSpacing>((event, emit) {
      emit(state.copyWith(letterSpacing: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeWordSpacing>((event, emit) {
      emit(state.copyWith(wordSpacing: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeLineHeight>((event, emit) {
      emit(state.copyWith(lineHeight: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeTextAlign>((event, emit) {
      emit(state.copyWith(textAlign: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ChangeColumnCount>((event, emit) {
      emit(state.copyWith(columnCount: event.value));
      submitPreferenceUpdate();
    });

    on<ChangeReadingProgression>((event, emit) {
      emit(state.copyWith(readingProgression: event.value));
      submitPreferenceUpdate();
    });

    on<ChangeParagraphIndent>((event, emit) {
      emit(state.copyWith(paragraphIndent: event.value, publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<TogglePublisherStyles>((event, emit) {
      emit(state.copyWith(publisherStyles: !state.publisherStyles));
      submitPreferenceUpdate();
    });

    on<ToggleHyphens>((event, emit) {
      emit(state.copyWith(hyphens: !(state.hyphens ?? false), publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ToggleLigatures>((event, emit) {
      emit(state.copyWith(ligatures: !(state.ligatures ?? false), publisherStyles: false));
      submitPreferenceUpdate();
    });

    on<ToggleTextNormalization>((event, emit) {
      emit(state.copyWith(textNormalization: !(state.textNormalization ?? false)));
      submitPreferenceUpdate();
    });

    on<ChangeImageFilter>((event, emit) {
      emit(state.copyWith(imageFilter: event.value));
      submitPreferenceUpdate();
    });
  }
}
