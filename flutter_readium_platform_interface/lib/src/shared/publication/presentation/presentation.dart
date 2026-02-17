// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../utils/jsonable.dart';
import '../link.dart';

/// The Presentation Hints extension defines a number of hints for User Agents about the way content
/// should be presented to the user.
///
/// https://readium.org/webpub-manifest/extensions/presentation.html
/// https://readium.org/webpub-manifest/schema/extensions/presentation/metadata.schema.json
///
/// These properties are nullable to avoid having default values when it doesn't make sense for a
/// given [Publication]. If a navigator needs a default value when not specified,
/// Presentation.DEFAULT_X and Presentation.X.DEFAULT can be used.
///
/// @param [clipped] Specifies whether or not the parts of a linked resource that flow out of the
///     viewport are clipped.
/// @param [continuous] Indicates how the progression between resources from the [readingOrder] should
///     be handled.
/// @param [fit] Suggested method for constraining a resource inside the viewport.
/// @param [orientation] Suggested orientation for the device when displaying the linked resource.
/// @param [overflow] Suggested method for handling overflow while displaying the linked resource.
/// @param [spread] Indicates the condition to be met for the linked resource to be rendered within a
///     synthetic spread.
/// @param [layout] Hints how the layout of the resource should be presented (EPUB extension).
@immutable
class Presentation with EquatableMixin implements JSONable {
  const Presentation({
    this.layout,
    this.orientation,
    this.overflow,
    this.spread,
    this.fit,
    this.clipped,
    this.continuous,
  });

  /// Creates a [Presentation] from its RWPM JSON representation.
  factory Presentation.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return Presentation();
    }

    final jsonObject = Map<String, dynamic>.of(json);
    return Presentation(
      clipped: jsonObject.optNullableBoolean('clipped', remove: true),
      continuous: jsonObject.optNullableBoolean('continuous', remove: true),
      fit: PresentationFit.fromString(jsonObject.optString('fit', remove: true)),
      orientation: PresentationOrientation.fromString(jsonObject.optString('orientation', remove: true)),
      overflow: PresentationOverflow.fromString(jsonObject.optString('overflow', remove: true)),
      spread: PresentationSpread.fromString(jsonObject.optString('spread', remove: true)),
      layout: EpubLayout.fromString(jsonObject.optString('layout', remove: true)),
    );
  }

  /// Hints how the layout of the resource should be presented.
  final EpubLayout? layout;

  /// Suggested orientation for the device when displaying the linked resource.
  final PresentationOrientation? orientation;

  /// Suggested method for handling overflow while displaying the linked resource.
  final PresentationOverflow? overflow;

  /// Indicates the condition to be met for the linked resource to be rendered within a synthetic spread.
  final PresentationSpread? spread;

  final PresentationFit? fit;
  final bool? clipped;
  final bool? continuous;

  @override
  List<Object?> get props => [layout, orientation, overflow, spread, fit, clipped, continuous];

  /// Determines the layout of the given resource in this publication.
  /// The default layout is reflowable.
  EpubLayout layoutOf(Link link) => link.properties.layout ?? layout ?? EpubLayout.reflowable;

  /// Serializes a [Presentation] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('clipped', clipped)
    ..putOpt('continuous', continuous)
    ..putOpt('fit', fit?.name)
    ..putOpt('orientation', orientation?.name)
    ..putOpt('overflow', overflow?.name)
    ..putOpt('spread', spread?.name)
    ..putOpt('layout', layout?.name);

  @override
  String toString() => 'Presentation(${toJson()})';
}

/// Suggested method for constraining a resource inside the viewport.
enum PresentationFit {
  width,
  height,
  contain,
  cover;

  const PresentationFit();

  static PresentationFit? fromString(String? value) =>
      PresentationFit.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}

/// Hints how the layout of the resource should be presented.
enum EpubLayout {
  fixed,
  reflowable;

  static EpubLayout? fromString(String? value) =>
      EpubLayout.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}

/// Suggested orientation for the device when displaying the linked resource.
enum PresentationOrientation {
  auto,
  landscape,
  portrait;

  static PresentationOrientation? fromString(String? value) =>
      PresentationOrientation.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}

/// Suggested method for handling overflow while displaying the linked resource.
enum PresentationOverflow {
  /// Indicates no preference for overflow content handling by the Author.
  auto,

  /// Indicates the Author preference is to dynamically paginate content overflow.
  paginated,

  /// Indicates the Author preference is to provide a scrolled view for overflow content, and each spine item with this property is to be rendered as separate scrollable document.
  scrolled;

  static PresentationOverflow? fromString(String? value) =>
      PresentationOverflow.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}

/// Indicates how the linked resource should be displayed in a reading
/// environment that displays synthetic spreads.
enum PresentationPage {
  left,
  right,
  center;

  static PresentationPage? fromString(String? value) =>
      PresentationPage.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}

/// Indicates the condition to be met for the linked resource to be rendered within a synthetic spread.
enum PresentationSpread {
  /// Specifies the Reading System can determine when to render a synthetic spread for the readingOrder item.
  auto,

  /// Specifies the Reading System should render a synthetic spread for the readingOrder item in both portrait and landscape orientations.
  both,

  /// Specifies the Reading System should not render a synthetic spread for the readingOrder item.
  none,

  /// Specifies the Reading System should render a synthetic spread for the readingOrder item only when in landscape orientation.
  landscape;

  static PresentationSpread? fromString(String? value) =>
      PresentationSpread.values.firstWhereOrNull((element) => element.name == value?.toLowerCase());
}
