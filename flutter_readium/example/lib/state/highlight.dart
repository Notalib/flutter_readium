import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';

/// Decoration group that holds all user highlights in the reader.
const highlightsGroup = 'user_highlights';

/// Decoration group with one bookmark marker in the margin next to each highlight.
const highlightMarkersGroup = 'highlight-markers';

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

  /// A bookmark icon in the margin, level with the first line of the highlight.
  ///
  /// Untinted, so it takes the text colour and follows the reader theme.
  ReaderDecoration get marker => ReaderDecoration(
    id: '${id}_marker',
    locator: decoration.locator,
    style: const ReaderDecorationStyle(
      style: DecorationStyle.marginMarker,
      marker: MarginMarker.icon(MarginMarkerIcon.bookmark),
    ),
  );

  Highlight withTint(Color tint) => Highlight(
    decoration: decoration.copyWith(style: decoration.style.copyWith(tint: tint)),
    text: text,
  );
}
