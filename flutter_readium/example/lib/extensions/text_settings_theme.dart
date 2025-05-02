import 'package:flutter/material.dart';

class TextSettingsTheme {
  TextSettingsTheme({required this.textColor, required this.backgroundColor});
  final Color textColor;
  final Color backgroundColor;

  @override
  String toString() => 'backgroundColor: $backgroundColor, textColor: $textColor';
}

final List<TextSettingsTheme> themes = [
  TextSettingsTheme(textColor: const Color(0xffeeeeee), backgroundColor: const Color(0xff000000)),
  TextSettingsTheme(textColor: const Color(0xff000000), backgroundColor: const Color(0xffffffff)),
  TextSettingsTheme(textColor: const Color(0xffffbb00), backgroundColor: const Color(0xff000000)),
  TextSettingsTheme(textColor: const Color(0xff000000), backgroundColor: const Color(0xffffbb00)),
  TextSettingsTheme(textColor: const Color(0xff116666), backgroundColor: const Color(0xffffeeee)),
  TextSettingsTheme(textColor: const Color(0xffffeeee), backgroundColor: const Color(0xff116666)),
  TextSettingsTheme(textColor: const Color(0XFF015298), backgroundColor: const Color(0xffffffff)),
  TextSettingsTheme(textColor: const Color(0xffffffff), backgroundColor: const Color(0XFF015298)),
  TextSettingsTheme(textColor: const Color(0xff000000), backgroundColor: const Color(0xff88bbbb)),
  TextSettingsTheme(textColor: const Color(0xff88bbbb), backgroundColor: const Color(0xff000000)),
];

final List<TextSettingsTheme> highlights = [
  TextSettingsTheme(
    textColor: const Color(0xffffffff),
    backgroundColor: const Color(0xccff00a7),
  ),
  TextSettingsTheme(
    textColor: const Color(0xff000000),
    backgroundColor: const Color(0xcc00c5ff),
  ),
  TextSettingsTheme(
    textColor: const Color(0xff000000),
    backgroundColor: const Color(0xcc00ff04),
  ),
  TextSettingsTheme(
    textColor: const Color(0xff000000),
    backgroundColor: const Color(0xccfdff00),
  ),
];
