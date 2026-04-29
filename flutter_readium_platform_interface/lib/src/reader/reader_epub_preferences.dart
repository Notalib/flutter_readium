// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui' show Color, TextAlign;

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../index.dart';

@immutable
class EPUBPreferences with EquatableMixin implements JSONable {
  const EPUBPreferences({
    this.backgroundColor,
    this.columnCount,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.hyphens,
    this.imageFilter,
    this.language,
    this.letterSpacing,
    this.ligatures,
    this.lineHeight,
    this.pageMargins,
    this.paragraphIndent,
    this.paragraphSpacing,
    this.publisherStyles,
    this.readingProgression,
    this.scroll,
    this.spread,
    this.textAlign,
    this.textColor,
    this.textNormalization,
    this.theme,
    this.typeScale,
    this.verticalText,
    this.wordSpacing,
    this.blackAndWhiteComicMode = false,
    this.disableSynchronization = false,
    this.firstElementTopMargin,
  });

  /// Default page background color.
  final Color? backgroundColor;

  /// Number of columns to display in reflowable content.
  final EpubColumnCount? columnCount;

  /// Font family for text content.
  final String? fontFamily;

  /// Font size for text content.
  final int? fontSize;

  /// Font weight for text content.
  final double? fontWeight;

  /// Hyphenation for text content.
  final bool? hyphens;

  /// Image filter to apply to images in the content. Note [blackAndWhiteComicMode] takes precedence over this setting for Nota comic books.
  final EpubImageFilter? imageFilter;

  /// Language for the content, specified as a BCP 47 language tag (e.g., "en", "fr", "zh-CN").
  final String? language;

  /// Letter spacing for text content.
  final double? letterSpacing;

  /// Ligatures for text content.
  final bool? ligatures;

  /// Line height for text content.
  final double? lineHeight;

  /// Page margins for the content.
  final double? pageMargins;

  /// Text indent for paragraphs.
  final double? paragraphIndent;

  /// Paragraph spacing for the content.
  final double? paragraphSpacing;

  /// Indicates whether the original publisher styles should be observed. Many settings require this to be off.
  final bool? publisherStyles;

  /// Direction of the reading progression across resources
  final EpubReadingProgression? readingProgression;

  /// Vertical scroll for reflowable content. Default is false, meaning horizontal pagination.
  final bool? scroll;

  /// Indicates if the fixed-layout publication should be rendered with a synthetic spread (dual-page).
  final String? spread;

  /// Text alignment
  final TextAlign? textAlign;

  /// Text color.
  final Color? textColor;

  /// Normalize text styles to increase accessibility
  final bool? textNormalization;

  /// Reader theme.
  final EpubThemeType? theme;

  /// Scale applied to all element font sizes.
  final double? typeScale;

  /// Indicates whether the text should be laid out vertically. This is used
  /// for example with CJK languages. This setting is automatically derived from the language if
  /// no preference is given.
  final bool? verticalText;

  /// Space between words.
  final double? wordSpacing;

  /// Black and white mode for Nota Comic Books.
  /// When enabled, this mode applies a black and white filter to the comic book pages.
  /// Note: ImageFilter is not supported when this mode is enabled.
  final bool blackAndWhiteComicMode;

  /// Disabled position synchronization between the TTS / SyncAudio navigators and the EPUB navigator.
  /// Highlight decorations will still be applied, but it won't scroll it into view or switch current chapter/file.
  final bool disableSynchronization;

  /// Margin applied to the top of the first element in the content.
  /// This is used to create space for UI elements like a toolbar without overlapping the content.
  final int? firstElementTopMargin;

  factory EPUBPreferences.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);
    final backgroundColorStr = jsonObject.optNullableString('backgroundColor', remove: true);
    final columnCountStr = jsonObject.optNullableString('columnCount', remove: true);
    final columnCount = columnCountStr != null ? EpubColumnCount.fromJson(columnCountStr) : null;
    final fontFamily = jsonObject.optNullableString('fontFamily', remove: true);
    final fontSize = jsonObject.optNullableInt('fontSize', remove: true);
    final fontWeight = jsonObject.optNullableDouble('fontWeight', remove: true);
    final hyphens = jsonObject.optNullableBoolean('hyphens', remove: true);
    final imageFilterStr = jsonObject.optNullableString('imageFilter', remove: true);
    final imageFilter = imageFilterStr != null ? EpubImageFilter.fromJson(imageFilterStr) : null;
    final language = jsonObject.optNullableString('language', remove: true);
    final letterSpacing = jsonObject.optNullableDouble('letterSpacing', remove: true);
    final ligatures = jsonObject.optNullableBoolean('ligatures', remove: true);
    final lineHeight = jsonObject.optNullableDouble('lineHeight', remove: true);
    final pageMargins = jsonObject.optNullableDouble('pageMargins', remove: true);
    final paragraphIndent = jsonObject.optNullableDouble('paragraphIndent', remove: true);
    final paragraphSpacing = jsonObject.optNullableDouble('paragraphSpacing', remove: true);
    final publisherStyles = jsonObject.optNullableBoolean('publisherStyles', remove: true);
    final readingProgressionStr = jsonObject.optNullableString('readingProgression', remove: true);
    final readingProgression = readingProgressionStr != null
        ? EpubReadingProgression.fromJson(readingProgressionStr)
        : null;
    final scroll = jsonObject.optNullableBoolean('scroll', remove: true);
    final spread = jsonObject.opt('spread', remove: true);
    final textAlign = jsonObject.optEnumFromString('textAlign', TextAlign.values, remove: true);
    final textColorStr = jsonObject.optNullableString('textColor', remove: true);
    final textColor = textColorStr != null ? ReadiumColorExtension.fromCSS(textColorStr) : null;
    final textNormalization = jsonObject.optNullableBoolean('textNormalization', remove: true);
    final themeStr = jsonObject.optNullableString('theme', remove: true);
    final theme = EpubThemeType.fromJson(themeStr);
    final typeScale = jsonObject.optNullableDouble('typeScale', remove: true);
    final verticalText = jsonObject.optNullableBoolean('verticalText', remove: true);
    final wordSpacing = jsonObject.optNullableDouble('wordSpacing', remove: true);
    final blackAndWhiteComicMode = jsonObject.optBoolean('blackAndWhiteComicMode', remove: true);
    final disableSynchronization = jsonObject.optBoolean('disableSynchronization', remove: true);
    final firstElementTopMargin = jsonObject.optNullableInt('firstElementTopMargin', remove: true);

    return EPUBPreferences(
      backgroundColor: backgroundColorStr != null ? ReadiumColorExtension.fromCSS(backgroundColorStr) : null,
      columnCount: columnCount,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      hyphens: hyphens,
      imageFilter: imageFilter,
      language: language,
      letterSpacing: letterSpacing,
      ligatures: ligatures,
      lineHeight: lineHeight,
      pageMargins: pageMargins,
      paragraphIndent: paragraphIndent,
      paragraphSpacing: paragraphSpacing,
      publisherStyles: publisherStyles,
      readingProgression: readingProgression,
      scroll: scroll,
      spread: spread,
      textAlign: textAlign,
      textColor: textColor,
      textNormalization: textNormalization,
      theme: theme,
      typeScale: typeScale,
      verticalText: verticalText,
      wordSpacing: wordSpacing,
      blackAndWhiteComicMode: blackAndWhiteComicMode,
      disableSynchronization: disableSynchronization,
      firstElementTopMargin: firstElementTopMargin,
    );
  }

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('backgroundColor', backgroundColor?.toCSS())
    ..putOpt('columnCount', columnCount?.toJson())
    ..putOpt('fontFamily', fontFamily)
    ..putOpt('fontSize', fontSize)
    ..putOpt('fontWeight', fontWeight)
    ..putOpt('hyphens', hyphens)
    ..putOpt('imageFilter', imageFilter?.toJson())
    ..putOpt('language', language)
    ..putOpt('letterSpacing', letterSpacing)
    ..putOpt('ligatures', ligatures)
    ..putOpt('lineHeight', lineHeight)
    ..putOpt('pageMargins', pageMargins)
    ..putOpt('paragraphIndent', paragraphIndent)
    ..putOpt('paragraphSpacing', paragraphSpacing)
    ..putOpt('publisherStyles', publisherStyles)
    ..putOpt('readingProgression', readingProgression?.toJson())
    ..putOpt('scroll', scroll)
    ..putOpt('spread', spread)
    ..putOpt('textAlign', textAlign?.name)
    ..putOpt('textColor', textColor?.toCSS())
    ..putOpt('textNormalization', textNormalization)
    ..putOpt('theme', theme?.toJson())
    ..putOpt('typeScale', typeScale)
    ..putOpt('verticalText', verticalText)
    ..putOpt('wordSpacing', wordSpacing)
    ..put('blackAndWhiteComicMode', blackAndWhiteComicMode)
    ..put('disableSynchronization', disableSynchronization)
    ..putOpt('firstElementTopMargin', firstElementTopMargin);

  EPUBPreferences copyWith({
    Color? backgroundColor,
    EpubColumnCount? columnCount,
    String? fontFamily,
    int? fontSize,
    double? fontWeight,
    bool? hyphens,
    EpubImageFilter? imageFilter,
    String? language,
    double? letterSpacing,
    bool? ligatures,
    double? lineHeight,
    double? pageMargins,
    double? paragraphIndent,
    double? paragraphSpacing,
    bool? publisherStyles,
    EpubReadingProgression? readingProgression,
    bool? scroll,
    String? spread,
    TextAlign? textAlign,
    Color? textColor,
    bool? textNormalization,
    EpubThemeType? theme,
    double? typeScale,
    bool? verticalText,
    double? wordSpacing,
    bool? blackAndWhiteComicMode,
    bool? disableSynchronization,
  }) => EPUBPreferences(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    columnCount: columnCount ?? this.columnCount,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    hyphens: hyphens ?? this.hyphens,
    imageFilter: imageFilter ?? this.imageFilter,
    language: language ?? this.language,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    ligatures: ligatures ?? this.ligatures,
    lineHeight: lineHeight ?? this.lineHeight,
    pageMargins: pageMargins ?? this.pageMargins,
    paragraphIndent: paragraphIndent ?? this.paragraphIndent,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    publisherStyles: publisherStyles ?? this.publisherStyles,
    readingProgression: readingProgression ?? this.readingProgression,
    scroll: scroll ?? this.scroll,
    spread: spread ?? this.spread,
    textAlign: textAlign ?? this.textAlign,
    textColor: textColor ?? this.textColor,
    textNormalization: textNormalization ?? this.textNormalization,
    theme: theme ?? this.theme,
    typeScale: typeScale ?? this.typeScale,
    verticalText: verticalText ?? this.verticalText,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    blackAndWhiteComicMode: blackAndWhiteComicMode ?? this.blackAndWhiteComicMode,
    disableSynchronization: disableSynchronization ?? this.disableSynchronization,
  );

  @override
  List<Object?> get props => [
    backgroundColor,
    columnCount,
    fontFamily,
    fontSize,
    fontWeight,
    hyphens,
    imageFilter,
    language,
    letterSpacing,
    ligatures,
    lineHeight,
    pageMargins,
    paragraphIndent,
    paragraphSpacing,
    publisherStyles,
    readingProgression,
    scroll,
    spread,
    textAlign,
    textColor,
    textNormalization,
    theme,
    typeScale,
    verticalText,
    wordSpacing,
    blackAndWhiteComicMode,
    disableSynchronization,
  ];
}

enum EpubColumnCount {
  auto,
  one,
  two;

  static EpubColumnCount? fromJson(String? value) {
    switch (value) {
      case 'auto':
        return EpubColumnCount.auto;
      case 'one':
        return EpubColumnCount.one;
      case 'two':
        return EpubColumnCount.two;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case EpubColumnCount.auto:
        return 'auto';
      case EpubColumnCount.one:
        return 'one';
      case EpubColumnCount.two:
        return 'two';
    }
  }
}

enum EpubImageFilter {
  darken,
  invert;

  static EpubImageFilter? fromJson(String? value) {
    switch (value) {
      case 'darken':
        return EpubImageFilter.darken;
      case 'invert':
        return EpubImageFilter.invert;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case EpubImageFilter.darken:
        return 'darken';
      case EpubImageFilter.invert:
        return 'invert';
    }
  }
}

enum EpubThemeType {
  light,
  dark,
  sepia;

  static EpubThemeType? fromJson(String? value) {
    switch (value) {
      case 'light':
        return EpubThemeType.light;
      case 'dark':
        return EpubThemeType.dark;
      case 'sepia':
        return EpubThemeType.sepia;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case EpubThemeType.light:
        return 'light';
      case EpubThemeType.dark:
        return 'dark';
      case EpubThemeType.sepia:
        return 'sepia';
    }
  }
}

enum EpubReadingProgression {
  ltr,
  rtl;

  static EpubReadingProgression? fromJson(String? value) {
    switch (value) {
      case 'ltr':
        return EpubReadingProgression.ltr;
      case 'rtl':
        return EpubReadingProgression.rtl;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case EpubReadingProgression.ltr:
        return 'ltr';
      case EpubReadingProgression.rtl:
        return 'rtl';
    }
  }
}
