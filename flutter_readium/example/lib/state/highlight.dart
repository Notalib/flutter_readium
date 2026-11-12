import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';

/// Decoration group that holds all user highlights in the reader.
const highlightsGroup = 'user_highlights';

/// A user highlight: the decoration sent to the reader plus the selected text.
///
/// The text is kept here because the selection locator's `text.highlight`
/// isn't guaranteed to be filled on every platform.
@immutable
class Highlight {
  const Highlight({required this.decoration, this.text});

  final ReaderDecoration decoration;
  final String? text;

  String get id => decoration.id;

  Color? get tint => decoration.style.tint;

  Highlight withTint(Color tint) => Highlight(
    decoration: decoration.copyWith(style: decoration.style.copyWith(tint: tint)),
    text: text,
  );
}
