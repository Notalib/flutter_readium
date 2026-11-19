// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/painting.dart' show Color;

import '../index.dart';

enum DecorationStyle {
  /// Opaque filled rectangle placed **behind** text (`experimentalPositioning: true`, alpha 1.0). Default.
  highlight,

  /// Colored border-bottom under the active text line.
  underline,

  /// Tinted box behind text **and** all surrounding body text is dimmed, drawing the eye to the active range.
  spotlight,

  /// Small label or icon floated into the page margin, level with the first line of the range.
  ///
  /// Requires [ReaderDecorationStyle.marker]; a decoration without one is skipped. Supported on iOS, Android and web.
  marginMarker;

  static DecorationStyle fromString(String? styleStr) {
    switch (styleStr) {
      case 'underline':
        return DecorationStyle.underline;
      case 'spotlight':
        return DecorationStyle.spotlight;
      case 'marginMarker':
        return DecorationStyle.marginMarker;
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

  ReaderDecoration copyWith({Object id = unset, Object locator = unset, Object style = unset}) => ReaderDecoration(
    id: identical(id, unset) ? this.id : (id as String),
    locator: identical(locator, unset) ? this.locator : (locator as Locator),
    style: identical(style, unset) ? this.style : (style as ReaderDecorationStyle),
  );
}

/// Built-in icons for [MarginMarker.icon]. Icons are a closed set so that Dart never supplies markup.
enum MarginMarkerIcon { bookmark }

/// Which page margin a [MarginMarker] sits in. Logical: [start] is the left margin in LTR and the right margin in RTL.
enum MarginSide { start, end }

/// The content of a [DecorationStyle.marginMarker] decoration: a text label or a built-in icon.
class MarginMarker implements JSONable {
  const MarginMarker.label(String this.label, {this.side = MarginSide.start}) : icon = null;

  const MarginMarker.icon(MarginMarkerIcon this.icon, {this.side = MarginSide.start}) : label = null;

  const MarginMarker._({this.label, this.icon, this.side = MarginSide.start});

  factory MarginMarker.fromJson(final Map<String, dynamic> map) => MarginMarker._(
    label: map['label'] as String?,
    icon: MarginMarkerIcon.values.where((i) => i.name == map['icon']).firstOrNull,
    side: MarginSide.values.where((s) => s.name == map['side']).firstOrNull ?? MarginSide.start,
  );

  final String? label;
  final MarginMarkerIcon? icon;
  final MarginSide side;

  @override
  Map<String, dynamic> toJson() => {
    if (label != null) 'label': label,
    if (icon != null) 'icon': icon!.name,
    'side': side.name,
  };
}

class ReaderDecorationStyle implements JSONable {
  const ReaderDecorationStyle({required this.style, this.tint, this.isActive = false, this.marker});

  final DecorationStyle style;

  /// The tint colour used for the decoration fill.
  ///
  /// `null` means no background colour — the style's visual effect (e.g. the
  /// spotlight dim) still applies, but no tinted box is drawn over the range.
  final Color? tint;

  /// When `true`, the decoration is rendered in a visually distinct "active"
  /// state (e.g. brighter highlight) to indicate the currently focused item —
  /// for example, the search result being navigated to in a result list.
  ///
  /// Supported on iOS and Android. Ignored on web until decorations are
  /// implemented there.
  final bool isActive;

  /// The label or icon to show. Required when [style] is [DecorationStyle.marginMarker]; ignored otherwise.
  ///
  /// [tint] colours the marker, and [isActive] is ignored.
  final MarginMarker? marker;

  @override
  Map<String, dynamic> toJson() => {
    'style': style.name,
    if (tint != null) 'tint': tint!.toCSS(),
    'isActive': isActive,
    if (marker != null) 'marker': marker!.toJson(),
  };

  factory ReaderDecorationStyle.fromJson(final Map<String, dynamic> map) => ReaderDecorationStyle(
    style: DecorationStyle.fromString(map['style']),
    tint: map['tint'] is String ? ReadiumColorExtension.fromCSS(map['tint'] as String) : null,
    isActive: map['isActive'] as bool? ?? false,
    marker: map['marker'] is Map ? MarginMarker.fromJson(Map<String, dynamic>.from(map['marker'] as Map)) : null,
  );

  ReaderDecorationStyle copyWith({
    Object style = unset,
    Object? tint = unset,
    Object isActive = unset,
    Object? marker = unset,
  }) => ReaderDecorationStyle(
    style: identical(style, unset) ? this.style : (style as DecorationStyle),
    tint: identical(tint, unset) ? this.tint : tint as Color?,
    isActive: identical(isActive, unset) ? this.isActive : (isActive as bool),
    marker: identical(marker, unset) ? this.marker : marker as MarginMarker?,
  );
}
