// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Colors;

import '../_index.dart';

enum DecorationStyle {
  highlight,
  underline,
}

DecorationStyle _styleFromString(String styleStr) {
  switch (styleStr) {
    case 'underline':
      return DecorationStyle.underline;
    case 'highlight':
    default:
      return DecorationStyle.highlight;
  }
}

class ReaderDecoration {
  ReaderDecoration({
    required this.id,
    required this.locator,
    required this.style,
    required this.tint,
  });

  String id;
  Locator locator;
  DecorationStyle style;
  Color tint;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'locator': locator.toJson(),
      'style': style.name,
      'tint': tint.toCSS(),
    };
  }

  factory ReaderDecoration.fromJsonMap(final Map<String, dynamic> map) => ReaderDecoration(
        id: map['id'] as String,
        locator: Locator.fromJson(map['locator']),
        style: _styleFromString(map['style']),
        tint: map['tint'] != null ? Color(map['tint'] as int) : Colors.red,
      );
}
