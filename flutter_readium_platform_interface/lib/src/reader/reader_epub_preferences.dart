// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui' show Color;

import '../_index.dart';

class EPUBPreferences {
  EPUBPreferences({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.verticalScroll,
    required this.backgroundColor,
    required this.textColor,
  });

  factory EPUBPreferences.fromJsonMap(final Map<String, dynamic> map) => EPUBPreferences(
        fontFamily: map['fontFamily'] as String,
        fontSize: map['fontSize'] as int,
        fontWeight: map['fontSize'] as double,
        verticalScroll: map['verticalScroll'] as bool,
        backgroundColor: map['tint'] is int ? Color(map['tint'] as int) : null,
        textColor: map['tint'] is int ? Color(map['tint'] as int) : null,
      );

  String fontFamily;
  int fontSize;
  double? fontWeight;
  bool? verticalScroll;
  Color? backgroundColor;
  Color? textColor;

  // TODO: Add more preferences,
  //see https://github.com/readium/swift-toolkit/blob/develop/Sources/Navigator/EPUB/Preferences/EPUBPreferences.swift

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontSize': '${fontSize / 100}',
        'fontWeight': fontWeight.toString(),
        'verticalScroll': verticalScroll.toString(),
        'backgroundColor': backgroundColor.toCSS(),
        'textColor': textColor.toCSS(),
      };
}
