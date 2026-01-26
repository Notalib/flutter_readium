// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:collection/collection.dart';

import '../../utils/take.dart';
import '../mediatype.dart';
import 'link.dart';

extension LinkListExtension on List<Link> {
  /// Returns the first [Link] with the given [href], or null if not found.
  int? indexOfFirstWithHref(String href) => indexWhere((it) => it.href == href).takeUnless((it) => it == -1);

  /// Finds the first link matching the given HREF.
  Link? firstWithHref(String href) => firstWhereOrNull((it) => it.href == href);

  /// Finds the first link with the given relation.
  Link? firstWithRel(String rel) => firstWhereOrNull((it) => it.rels.contains(rel));

  /// Finds all the links with the given relation.
  List<Link> filterByRel(String rel) => where((it) => it.rels.contains(rel)).toList();

  /// Finds the first link matching the given media type.
  Link? firstWithMediaType(MediaType mediaType) => firstWhereOrNull((it) => it.mediaType.matches(mediaType));

  /// Finds all the links matching the given media type.
  List<Link> filterByMediaType(MediaType mediaType) => where((it) => it.mediaType.matches(mediaType)).toList();

  /// Finds all the links matching any of the given media types.
  List<Link> filterByMediaTypes(List<MediaType> mediaTypes) =>
      where((it) => mediaTypes.any((mediaType) => mediaType.matchesFromName(it.type))).toList();

  /// Returns whether all the resources in the collection are bitmaps.
  bool get allAreBitmap => isNotEmpty && every((it) => it.mediaType.isBitmap);

  /// Returns whether all the resources in the collection are audio clips.
  bool get allAreAudio => isNotEmpty && every((it) => it.mediaType.isAudio);

  /// Returns whether all the resources in the collection are video clips.
  bool get allAreVideo => isNotEmpty && every((it) => it.mediaType.isVideo);

  /// Returns whether all the resources in the collection are HTML documents.
  bool get allAreHtml => isNotEmpty && every((it) => it.mediaType.isHtml);

  /// Returns whether all the resources in the collection are matching the given media type.
  bool allMatchMediaType(MediaType mediaType) => isNotEmpty && every((it) => mediaType.matches(it.mediaType));

  /// Returns whether all the resources in the collection are matching any of the given media types.
  bool allMatchMediaTypes(List<MediaType> mediaTypes) =>
      isNotEmpty && every((it) => mediaTypes.any((mediaType) => mediaType.matches(it.mediaType)));

  Link? deepLinkWithHref(String href) {
    for (final l in this) {
      if (l.href.toLowerCase() == href.toLowerCase() || l.href.toLowerCase() == '/${href.toLowerCase()}') {
        return l;
      } else {
        final alternate = l.alternates.deepLinkWithHref(href);
        if (alternate != null) {
          return alternate;
        }
        final child = l.children.deepLinkWithHref(href);
        if (child != null) {
          return child;
        }
      }
    }
    return null;
  }
}
