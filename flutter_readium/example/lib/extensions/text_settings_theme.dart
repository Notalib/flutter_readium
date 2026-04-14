import 'package:flutter/material.dart';

@immutable
class TextSettingsTheme {
  const TextSettingsTheme({required this.textColor, required this.backgroundColor});
  final Color textColor;
  final Color backgroundColor;

  @override
  String toString() => 'backgroundColor: $backgroundColor, textColor: $textColor';
}

const List<TextSettingsTheme> themes = [
  TextSettingsTheme(textColor: Color(0xffeeeeee), backgroundColor: Color(0xff000000)),
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xffffffff)),
  TextSettingsTheme(textColor: Color(0xffffbb00), backgroundColor: Color(0xff000000)),
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xffffbb00)),
  TextSettingsTheme(textColor: Color(0xff116666), backgroundColor: Color(0xffffeeee)),
  TextSettingsTheme(textColor: Color(0xffffeeee), backgroundColor: Color(0xff116666)),
  TextSettingsTheme(textColor: Color(0XFF015298), backgroundColor: Color(0xffffffff)),
  TextSettingsTheme(textColor: Color(0xffffffff), backgroundColor: Color(0XFF015298)),
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xff88bbbb)),
  TextSettingsTheme(textColor: Color(0xff88bbbb), backgroundColor: Color(0xff000000)),
];

const List<TextSettingsTheme> highlights = [
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xccfdff00)),
  TextSettingsTheme(textColor: Color(0xffffffff), backgroundColor: Color(0xccff00a7)),
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xcc00c5ff)),
  TextSettingsTheme(textColor: Color(0xff000000), backgroundColor: Color(0xcc00ff04)),
];
