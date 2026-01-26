// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';

import '../../utils/jsonable.dart';
import '../../utils/take.dart';
import '../../extensions/readium_string_extensions.dart';
import '../epub.dart';
import '../mediatype/mediatype.dart';
import 'link.dart';

const int _emptyIntValue = -1;
const double _emptyDoubleValue = -1;

extension IntCheck on int? {
  int? check(int? defaultValue) => (this == _emptyIntValue) ? defaultValue : this;
}

extension DoubleCheck on double? {
  double? check(double? defaultValue) => (this == _emptyDoubleValue) ? defaultValue : this;
}

/// Provides a precise location in a publication in a format that can be stored and shared.
///
/// There are many different use cases for locators:
///  - getting back to the last position in a publication
///  - bookmarks
///  - highlights & annotations
///  - search results
///  - human-readable (and shareable) reference in a publication
///
/// https://github.com/readium/architecture/tree/master/locators
class Locator with EquatableMixin implements JSONable {
  const Locator({
    required this.href,
    required this.type,
    this.title,
    this.locations = const Locations(),
    this.text = const LocatorText(),
  });
  final String href;
  final String type;
  final String? title;
  final Locations locations;
  final LocatorText text;

  static Locator? fromJsonString(String jsonString) {
    try {
      //Fimber.d("jsonString $jsonString");
      final Map<String, dynamic> json = JsonCodec().decode(jsonString);
      return Locator.fromJson(json);
    } catch (ex, st) {
      Fimber.e('ERROR', ex: ex, stacktrace: st);
    }
    return null;
  }

  static Locator? fromJson(Map<String, dynamic>? json) {
    final href = json?.optNullableString('href');
    final type = json?.optNullableString('type');
    if (href == null || type == null) {
      Fimber.i('[href] and [type] are required $json');
      return null;
    }
    return Locator(
      href: href,
      type: type,
      title: json.optNullableString('title'),
      locations: Locations.fromJson(json.optJSONObject('locations')),
      text: LocatorText.fromJson(json.optJSONObject('text')),
    );
  }

  String get json => JsonCodec().encode(toJson());

  @override
  Map<String, dynamic> toJson() => {'href': href, 'type': type}
    ..putOpt('title', title)
    ..putJSONableIfNotEmpty('locations', locations)
    ..putJSONableIfNotEmpty('text', text);

  Locator copyWith({String? href, String? type, String? title, Locations? locations, LocatorText? text}) => Locator(
    href: href ?? this.href,
    type: type ?? this.type,
    title: title ?? this.title,
    locations: locations ?? this.locations,
    text: text ?? this.text,
  );

  /// Shortcut to get a copy of the [Locator] with different [Locations] sub-properties.
  Locator copyWithLocations({
    List<String>? fragments,
    double? progression = _emptyDoubleValue,
    int? position = _emptyIntValue,
    double? totalProgression = _emptyDoubleValue,
    Map<String, dynamic>? otherLocations,
  }) => copyWith(
    locations: locations.copyWith(
      fragments: fragments ?? locations.fragments,
      progression: progression.check(locations.progression),
      position: position.check(locations.position),
      totalProgression: totalProgression.check(locations.totalProgression),
      otherLocations: otherLocations ?? locations.otherLocations,
    ),
  );

  /// Returns /path from [href] without #fragment and query parameters.
  String get hrefPath {
    final path = href.path;

    if (path == null) {
      return href;
    }

    return path;
  }

  @override
  List<Object?> get props => [href, type, title, locations, text];

  @override
  String toString() =>
      'Locator{href: $href, type: $type, title: $title, '
      'locations: $locations, text: $text}';

  Locator toTextLocator() {
    // WORKAROUND:
    // Sometimes readium handled any fragments as an `id` fragment and tries to scroll
    // to it as fx. [readium.scrollToId('t=287.55899999999997')] which will cause the book
    // starts from the beginning.
    // Only set id fragments to less confusing readium.
    final selector = locations.cssSelector ?? locations.domRange?.start.cssSelector;
    final idFragment = selector?.startsWith('#') == true ? selector!.substring(1) : null;
    // Make sure href only contains path.
    final locationHref = hrefPath.startsWith('/') ? hrefPath.substring(1) : hrefPath;

    return copyWith(
      // Makes sure href only contains /path.
      href: locationHref,
      type: MediaType.html.name,
      locations: locations.copyWith(fragments: idFragment == null ? null : [idFragment]),
    );
  }
}

/// One or more alternative expressions of the location.
/// https://github.com/readium/architecture/tree/master/models/locators#the-location-object
///
/// @param fragments Contains one or more fragment in the resource referenced by the [Locator].
/// @param progression Progression in the resource expressed as a percentage (between 0 and 1).
/// @param position An index in the publication (>= 1).
/// @param totalProgression Progression in the publication expressed as a percentage (between 0
///        and 1).
/// @param otherLocations Additional locations for extensions.
class Locations with EquatableMixin implements JSONable {
  const Locations({
    this.position,
    this.progression,
    this.totalProgression,
    this.cssSelector,
    this.fragments = const [],
    this.otherLocations = const {},
  });

  factory Locations.fromJson(Map<String, dynamic>? json) {
    final fragments =
        json?.optStringsFromArrayOrSingle('fragments', remove: true).takeIf((it) => it.isNotEmpty) ??
        json?.optStringsFromArrayOrSingle('fragment', remove: true) ??
        [];

    final progression = json?.optNullableDouble('progression', remove: true)?.takeIf((it) => 0.0 <= it && it <= 1.0);

    final position = json?.optNullableInt('position', remove: true)?.takeIf((it) => it > 0);

    final totalProgression = json
        ?.optNullableDouble('totalProgression', remove: true)
        ?.takeIf((it) => 0.0 <= it && it <= 1.0);

    return Locations(
      fragments: fragments,
      progression: progression,
      position: position,
      totalProgression: totalProgression,
      otherLocations: json ?? {},
      cssSelector: json?.optNullableString('cssSelector', remove: true),
    );
  }
  final int? position;
  final double? progression;
  final double? totalProgression;
  final List<String> fragments;
  final Map<String, dynamic> otherLocations;
  final String? cssSelector;

  Locations copyWith({
    int? position = _emptyIntValue,
    double? progression = _emptyDoubleValue,
    double? totalProgression = _emptyDoubleValue,
    List<String>? fragments,
    Map<String, dynamic>? otherLocations,
    String? cssSelector,
  }) => Locations(
    progression: progression.check(this.progression),
    position: position.check(this.position),
    totalProgression: totalProgression.check(this.totalProgression),
    fragments: fragments ?? this.fragments,
    otherLocations: otherLocations ?? this.otherLocations,
    cssSelector: cssSelector ?? this.cssSelector,
  );

  int get timestamp {
    if (fragments.isEmpty) {
      return 0;
    }
    final timeFragment = fragments.firstWhere((e) => e.startsWith('t='), orElse: () => 't=0');
    return int.parse(timeFragment.replaceFirst('t=', ''));
  }

  /// Syntactic sugar to access the [otherLocations] values by subscripting [Locations] directly.
  /// `locations["cssSelector"] == locations.otherLocations["cssSelector"]`
  dynamic operator [](String key) => otherLocations[key];

  String get json => JsonCodec().encode(toJson());

  @override
  Map<String, dynamic> toJson() => Map.of(otherLocations)
    ..putIterableIfNotEmpty('fragments', fragments)
    ..putOpt('progression', progression)
    ..putOpt('position', position)
    ..putOpt('totalProgression', totalProgression)
    ..putOpt('cssSelector', cssSelector);

  @override
  List<Object?> get props => [position, progression, totalProgression, fragments, otherLocations, cssSelector];

  @override
  String toString() =>
      'Location{position: $position, progression: $progression, '
      'totalProgression: $totalProgression, fragments: $fragments}, '
      'otherLocations: $otherLocations, cssSelector: $cssSelector}';
}

/// Textual context of the locator.
///
/// A Locator Text Object contains multiple text fragments, useful to give a context to the
/// [Locator] or for highlights.
/// https://github.com/readium/architecture/tree/master/models/locators#the-text-object
///
/// @param before The text before the locator.
/// @param highlight The text at the locator.
/// @param after The text after the locator.
class LocatorText with EquatableMixin implements JSONable {
  factory LocatorText.fromJson(Map<String, dynamic>? json) => LocatorText(
    before: json?.optNullableString('before'),
    highlight: json?.optNullableString('highlight'),
    after: json?.optNullableString('after'),
  );

  const LocatorText({this.before, this.highlight, this.after});
  final String? before;
  final String? highlight;
  final String? after;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('before', before)
    ..putOpt('highlight', highlight)
    ..putOpt('after', after);

  @override
  List<Object?> get props => [before, highlight, after];
}

extension LinkLocator on Link {
  /// Creates a [Locator] from a reading order [Link].
  Locator toLocator() {
    final components = href.split('#');
    final fragment = (components.length > 1) ? components[1] : null;
    return Locator(
      href: components.firstOrDefault(href),
      type: type ?? '',
      title: title,
      locations: Locations(fragments: fragment?.let((it) => [it]) ?? []),
    );
  }
}

extension HTMLLocationsExtension on Locations {
  /// A CSS Selector.
  String? get cssSelector => this['cssSelector'] as String?;

  /// [partialCfi] is an expression conforming to the "right-hand" side of the EPUB CFI syntax, that is
  /// to say: without the EPUB-specific OPF spine item reference that precedes the first ! exclamation
  /// mark (which denotes the "step indirection" into a publication document). Note that the wrapping
  /// epubcfi(***) syntax is not used for the [partialCfi] string, i.e. the "fragment" part of the CFI
  /// grammar is ignored.
  String? get partialCfi => this['partialCfi'] as String?;

  /// An HTML DOM range.
  DomRange? get domRange => (this['domRange'] as Map<String, dynamic>?)?.let((it) => DomRange.fromJson(it));
}
