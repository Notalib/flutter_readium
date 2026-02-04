// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui' show Color;

import '../index.dart';

class EPUBPreferences implements JSONable {
  const EPUBPreferences({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.verticalScroll,
    required this.backgroundColor,
    required this.textColor,
    this.pageMargins,
  });

  factory EPUBPreferences.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final backgroundColorStr = jsonObject.optNullableString('backgroundColor', remove: true);
    Color? backgroundColor;
    if (backgroundColorStr != null && backgroundColorStr.startsWith('#')) {
      backgroundColor = ReadiumColorExtension.fromCSS(backgroundColorStr);
    }

    final tint = jsonObject.optNullableInt('tint', remove: true);
    if (backgroundColor == null && tint != null && tint > 0) {
      backgroundColor = Color(tint);
    }

    return EPUBPreferences(
      fontFamily: jsonObject.optString('fontFamily', remove: true),
      fontSize: jsonObject.optInt('fontSize', remove: true),
      fontWeight: jsonObject.optDouble('fontWeight', remove: true),
      verticalScroll: jsonObject.optBoolean('verticalScroll', remove: true),
      backgroundColor: backgroundColor,
      textColor: jsonObject.opt('textColor') is int ? Color(jsonObject.opt('textColor') as int) : null,
    );
  }

  final String fontFamily;
  final int fontSize;
  final double? fontWeight;
  final bool? verticalScroll;
  final Color? backgroundColor;
  final Color? textColor;
  final double? pageMargins;

  // TODO: Add more preferences,
  //see https://github.com/readium/swift-toolkit/blob/develop/Sources/Navigator/EPUB/Preferences/EPUBPreferences.swift
  @override
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'fontFamily': fontFamily,
      'fontSize': '${fontSize / 100}',
      'fontWeight': fontWeight.toString(),
      'verticalScroll': verticalScroll.toString(),
      'backgroundColor': backgroundColor.toCSS(),
      'textColor': textColor.toCSS(),
    };
    if (pageMargins != null) {
      map['pageMargins'] = pageMargins.toString();
    }
    return map;
  }
}
