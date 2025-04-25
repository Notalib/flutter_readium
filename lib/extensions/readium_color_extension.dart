import 'package:flutter/material.dart';

extension ReadiumColorExtension on Color {
  String toCSS({final bool leadingHashSign = true}) {
    final hexR = (r * 255).round().toRadixString(16).padLeft(2, '0');
    final hexG = (g * 255).round().toRadixString(16).padLeft(2, '0');
    final hexB = (b * 255).round().toRadixString(16).padLeft(2, '0');
    // TODO: Find out if it is our implementation of the Readium Swift-toolkit or if it is a limitation of the toolkit itself that opacity is not supported.
    // if sending opaque colors with opacity on an ios device, the colors will be changed, e.g. black will be blue
    final hexA = a < 1.0 ? (a * 255).round().toRadixString(16).padLeft(2, '0') : '';

    return '${leadingHashSign ? '#' : ''}$hexA$hexR$hexG$hexB';
  }
}

extension ReadiumColorExtensionNullable on Color? {
  String toCSS() => this?.toCSS() ?? 'inherit';
}
