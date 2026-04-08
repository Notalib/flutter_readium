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
  final ColumnCount? columnCount;
  final String? fontFamily;
  final int? fontSize;
  final double? fontWeight;
  final bool? hyphens;
  final ImageFilter? imageFilter;
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
  final TextAlign? textAlign;
  final Color? textColor;
  final bool? textNormalization;
  final ThemeType? theme;
  final double? typeScale;
  final bool? verticalText;
  final double? wordSpacing;
  final bool blackAndWhiteComicMode;

  factory EPUBPreferences.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);
    final backgroundColorStr = jsonObject.optNullableString('backgroundColor', remove: true);
    final columnCountStr = jsonObject.optNullableString('columnCount', remove: true);
    final columnCount = columnCountStr != null ? ColumnCount.fromJson(columnCountStr) : null;
    final fontFamily = jsonObject.optNullableString('fontFamily', remove: true);
    final fontSize = jsonObject.optNullableInt('fontSize', remove: true);
    final fontWeight = jsonObject.optNullableDouble('fontWeight', remove: true);
    final hyphens = jsonObject.optNullableBoolean('hyphens', remove: true);
    final imageFilterStr = jsonObject.optNullableString('imageFilter', remove: true);
    final imageFilter = imageFilterStr != null ? ImageFilter.fromJson(imageFilterStr) : null;
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
    final theme = ThemeType.fromJson(themeStr);
    final typeScale = jsonObject.optDouble('typeScale', remove: true);
    final verticalText = jsonObject.optNullableBoolean('verticalText', remove: true);
    final wordSpacing = jsonObject.optDouble('wordSpacing', remove: true);
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

enum ColumnCount {
  auto,
  one,
  two;

  static ColumnCount? fromJson(String? value) {
    switch (value) {
      case 'auto':
        return ColumnCount.auto;
      case 'one':
        return ColumnCount.one;
      case 'two':
        return ColumnCount.two;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case ColumnCount.auto:
        return 'auto';
      case ColumnCount.one:
        return 'one';
      case ColumnCount.two:
        return 'two';
    }
  }
}

enum ImageFilter {
  darken,
  invert;

  static ImageFilter? fromJson(String? value) {
    switch (value) {
      case 'darken':
        return ImageFilter.darken;
      case 'invert':
        return ImageFilter.invert;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case ImageFilter.darken:
        return 'darken';
      case ImageFilter.invert:
        return 'invert';
    }
  }
}

enum TextAlign {
  center,
  justify,
  start,
  end,
  left,
  right;

  static TextAlign? fromJson(String? value) {
    switch (value) {
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      case 'start':
        return TextAlign.start;
      case 'end':
        return TextAlign.end;
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case TextAlign.center:
        return 'center';
      case TextAlign.justify:
        return 'justify';
      case TextAlign.start:
        return 'start';
      case TextAlign.end:
        return 'end';
      case TextAlign.left:
        return 'left';
      case TextAlign.right:
        return 'right';
    }
  }
}

enum ThemeType {
  light,
  dark,
  sepia;

  static ThemeType? fromJson(String? value) {
    switch (value) {
      case 'light':
        return ThemeType.light;
      case 'dark':
        return ThemeType.dark;
      case 'sepia':
        return ThemeType.sepia;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case ThemeType.light:
        return 'light';
      case ThemeType.dark:
        return 'dark';
      case ThemeType.sepia:
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
