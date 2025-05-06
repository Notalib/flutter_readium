import 'dart:ui';

import 'package:collection/collection.dart';

import '../extensions/index.dart';

class ReadiumReaderProperties {
  const ReadiumReaderProperties({
    this.fontFamily = 'Original',
    this.fontSize = 100,
    this.verticalScroll = false,
    this.backgroundColor,
    this.textColor,
    this.highlightBackgroundColor,
    this.highlightForegroundColor,
  });

  final String fontFamily;
  final int fontSize;
  final bool verticalScroll;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? highlightBackgroundColor;
  final Color? highlightForegroundColor;

  Map<String, String> toJson() {
    return {
      'backgroundColor': backgroundColor.toCSS(),
      'textColor': textColor.toCSS(),
      'fontFamily': fontFamily,
      'fontSize': '${fontSize / 100}',
      'scroll': '$verticalScroll',
      'selectionBackgroundColor': highlightBackgroundColor.toCSS(),
      'selectionTextColor': highlightForegroundColor.toCSS(),
    };
  }

  // ignore: sort_constructors_first
  factory ReadiumReaderProperties.fromJson(final Map<String, dynamic> map) =>
      ReadiumReaderProperties(
        fontFamily: map['fontFamily'] as String,
        fontSize: map['fontSize'] as int,
        verticalScroll: map['verticalScroll'] as bool,
        backgroundColor:
            map['backgroundColor'] != null ? Color(map['backgroundColor'] as int) : null,
        textColor: map['textColor'] != null ? Color(map['textColor'] as int) : null,
        highlightBackgroundColor: map['highlightBackgroundColor'] != null
            ? Color(map['highlightBackgroundColor'] as int)
            : null,
        highlightForegroundColor: map['highlightForegroundColor'] != null
            ? Color(map['highlightForegroundColor'] as int)
            : null,
      );

  ReadiumReaderProperties copyWith({
    final String? fontFamily,
    final int? fontSize,
    final bool? verticalScroll,
    final Color? backgroundColor,
    final Color? textColor,
    final Color? highlightBackgroundColor,
    final Color? highlightForegroundColor,
    final Map<String, String>? extras,
  }) =>
      ReadiumReaderProperties(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        verticalScroll: verticalScroll ?? this.verticalScroll,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        textColor: textColor ?? this.textColor,
        highlightBackgroundColor: highlightBackgroundColor ?? this.highlightBackgroundColor,
        highlightForegroundColor: highlightForegroundColor ?? this.highlightForegroundColor,
      );

  @override
  bool operator ==(final other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
              other is ReadiumReaderProperties &&
              const DeepCollectionEquality().equals(other.fontFamily, fontFamily) &&
              const DeepCollectionEquality().equals(other.fontSize, fontSize)) &&
          const DeepCollectionEquality().equals(other.verticalScroll, verticalScroll) &&
          const DeepCollectionEquality().equals(other.backgroundColor, backgroundColor) &&
          const DeepCollectionEquality().equals(other.textColor, textColor) &&
          const DeepCollectionEquality()
              .equals(other.highlightBackgroundColor, highlightBackgroundColor) &&
          const DeepCollectionEquality()
              .equals(other.highlightForegroundColor, highlightForegroundColor);

  @override
  int get hashCode => Object.hash(
        runtimeType,
        const DeepCollectionEquality().hash(fontFamily),
        const DeepCollectionEquality().hash(fontSize),
        const DeepCollectionEquality().hash(verticalScroll),
        const DeepCollectionEquality().hash(backgroundColor),
        const DeepCollectionEquality().hash(textColor),
        const DeepCollectionEquality().hash(highlightBackgroundColor),
        const DeepCollectionEquality().hash(highlightForegroundColor),
      );

  @override
  String toString() => 'UserProperties${toJson()}';
}
