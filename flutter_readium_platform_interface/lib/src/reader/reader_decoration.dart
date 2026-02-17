// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart' show Color, Colors;

import '../index.dart';

enum DecorationStyle {
  highlight,
  underline;

  static DecorationStyle fromString(String? styleStr) {
    switch (styleStr) {
      case 'underline':
        return DecorationStyle.underline;
      case 'highlight':
      default:
        return DecorationStyle.highlight;
    }
  }
}

class ReaderDecoration implements JSONable {
  const ReaderDecoration({required this.id, required this.locator, required this.style});

  factory ReaderDecoration.fromJson(final Map<String, dynamic> map) {
    final jsonObject = Map<String, dynamic>.of(map);

    final id = jsonObject.optString('id', remove: true);
    final locatorJson = jsonObject.optNullableMap('locator', remove: true);
    final styleJson = jsonObject.optNullableMap('style', remove: true) ?? {};

    return ReaderDecoration(
      id: id,
      locator: Locator.fromJson(locatorJson!)!,
      style: ReaderDecorationStyle.fromJson(styleJson),
    );
  }

  final String id;
  final Locator locator;
  final ReaderDecorationStyle style;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'locator': locator.toJson(), 'style': style.toJson()};

  ReaderDecoration copyWith({String? id, Locator? locator, ReaderDecorationStyle? style}) =>
      ReaderDecoration(id: id ?? this.id, locator: locator ?? this.locator, style: style ?? this.style);
}

class ReaderDecorationStyle implements JSONable {
  const ReaderDecorationStyle({required this.style, required this.tint});

  final DecorationStyle style;
  final Color tint;

  @override
  Map<String, dynamic> toJson() => {'style': style.name, 'tint': tint.toCSS()};

  factory ReaderDecorationStyle.fromJson(final Map<String, dynamic> map) => ReaderDecorationStyle(
    style: DecorationStyle.fromString(map['style']),
    tint: map['tint'] != null ? Color(map['tint'] as int) : Colors.red,
  );

  ReaderDecorationStyle copyWith({DecorationStyle? style, Color? tint}) =>
      ReaderDecorationStyle(style: style ?? this.style, tint: tint ?? this.tint);
}
