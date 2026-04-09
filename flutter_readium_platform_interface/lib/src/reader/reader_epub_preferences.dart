// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui' show Color;

import '../index.dart';

class EPUBPreferences implements JSONable {
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
    this.verticalScroll,
    this.spread,
    this.textAlign,
    this.textColor,
    this.textNormalization,
    this.theme,
    this.typeScale,
    this.verticalText,
    this.wordSpacing,
    this.blackAndWhiteComicMode = false,
  });

  final Color? backgroundColor;
  final EpubColumnCount? columnCount;
  final String? fontFamily;
  final int? fontSize;
  final double? fontWeight;
  final bool? hyphens;
  final EpubImageFilter? imageFilter;
  final String? language;
  final double? letterSpacing;
  final bool? ligatures;
  final double? lineHeight;
  final double? pageMargins;
  final double? paragraphIndent;
  final double? paragraphSpacing;
  final bool? publisherStyles;
  final EpubReadingProgression? readingProgression;
  final bool? verticalScroll;
  final String? spread;
  final EpubTextAlign? textAlign;
  final Color? textColor;
  final bool? textNormalization;
  final EpubThemeType? theme;
  final double? typeScale;
  final bool? verticalText;
  final double? wordSpacing;

  /// Black and white mode for Nota Comic Books.
  /// When enabled, this mode applies a black and white filter to the comic book pages.
  final bool blackAndWhiteComicMode;

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
    final verticalScroll = jsonObject.optNullableBoolean('verticalScroll', remove: true);
    final spread = jsonObject.opt('spread', remove: true); // Replace with actual parsing if needed
    final textAlign = jsonObject.opt('textAlign', remove: true); // Replace with actual parsing if needed
    final textColor = jsonObject.optNullableString('textColor', remove: true);
    final textNormalization = jsonObject.optNullableBoolean('textNormalization', remove: true);
    final themeStr = jsonObject.optNullableString('theme', remove: true);
    final theme = EpubThemeType.fromJson(themeStr);
    final typeScale = jsonObject.optNullableDouble('typeScale', remove: true);
    final verticalText = jsonObject.optNullableBoolean('verticalText', remove: true);
    final wordSpacing = jsonObject.optNullableDouble('wordSpacing', remove: true);
    final blackAndWhiteComicMode = jsonObject.optBoolean('blackAndWhiteComicMode', remove: true);

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
      readingProgression: readingProgression, // Replace with actual parsing if needed
      verticalScroll: verticalScroll,
      spread: spread, // Replace with actual parsing if needed
      textAlign: textAlign, // Replace with actual parsing if needed
      textColor: textColor != null ? ReadiumColorExtension.fromCSS(textColor) : null,
      textNormalization: textNormalization,
      theme: theme, // Replace with actual parsing if needed
      typeScale: typeScale,
      verticalText: verticalText,
      wordSpacing: wordSpacing,
      blackAndWhiteComicMode: blackAndWhiteComicMode,
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
    ..putOpt('verticalScroll', verticalScroll)
    ..putOpt('spread', spread)
    ..putOpt('textAlign', textAlign?.toJson())
    ..putOpt('textColor', textColor?.toCSS())
    ..putOpt('textNormalization', textNormalization)
    ..putOpt('theme', theme?.toJson())
    ..putOpt('typeScale', typeScale)
    ..putOpt('verticalText', verticalText)
    ..putOpt('wordSpacing', wordSpacing)
    ..put('blackAndWhiteComicMode', blackAndWhiteComicMode);
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

enum EpubTextAlign {
  center,
  justify,
  start,
  end,
  left,
  right;

  static EpubTextAlign? fromJson(String? value) {
    switch (value) {
      case 'center':
        return EpubTextAlign.center;
      case 'justify':
        return EpubTextAlign.justify;
      case 'start':
        return EpubTextAlign.start;
      case 'end':
        return EpubTextAlign.end;
      case 'left':
        return EpubTextAlign.left;
      case 'right':
        return EpubTextAlign.right;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case EpubTextAlign.center:
        return 'center';
      case EpubTextAlign.justify:
        return 'justify';
      case EpubTextAlign.start:
        return 'start';
      case EpubTextAlign.end:
        return 'end';
      case EpubTextAlign.left:
        return 'left';
      case EpubTextAlign.right:
        return 'right';
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
