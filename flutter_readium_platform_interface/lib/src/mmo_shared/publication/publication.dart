// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: must_be_immutable

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartx/dartx.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';

import '../../commons/extensions/strings.dart';
import '../../commons/extensions/uri.dart';
import '../mediatype.dart';
import '../publication.dart' show Manifest;
import 'link.dart';
import 'link_list_extension.dart';
import 'link_pagination.dart';
import 'metadata.dart';
import 'publication_collection.dart';

/// The Publication shared model is the entry-point for all the metadata and services
/// related to a Readium publication.
///
/// @param manifest The manifest holding the publication metadata extracted from the publication file.
/// @param fetcher The underlying fetcher used to read publication resources.
/// The default implementation returns Resource.Exception.NotFound for all HREFs.
/// @param servicesBuilder Holds the list of service factories used to create the instances of
/// Publication.Service attached to this Publication.
/// @param positionsFactory Factory used to build lazily the [positions].
class Publication with EquatableMixin {
  Publication({required this.manifest, this.cssStyle});

  final Manifest manifest;

  String? cssStyle;

  TYPE? _type;
  int nbPages = 0;
  Map<Link, LinkPagination> paginationInfo = {};

  // Shortcuts to manifest properties

  List<String> get context => manifest.context;

  Metadata get metadata => manifest.metadata;

  List<Link> get links => manifest.links;

  /// Identifies a list of resources in reading order for the publication.
  List<Link> get readingOrder => manifest.readingOrder;

  /// Identifies resources that are necessary for rendering the publication.
  List<Link> get resources => manifest.resources;

  /// Identifies the collection that contains a table of contents.
  List<Link> get tableOfContents => manifest.tableOfContents;

  Map<String, List<PublicationCollection>> get subcollections => manifest.subcollections;

  // FIXME: To be refactored, with the TYPE and EXTENSION enums as well
  TYPE get type {
    if (_type == null) {
      if (metadata.type == 'http://schema.org/Audiobook' || readingOrder.allAreAudio) {
        _type = TYPE.audio;
      } else if (readingOrder.allAreBitmap) {
        _type = TYPE.divina;
      } else {
        _type = TYPE.webpub;
      }
    }
    return _type!;
  }

  set type(TYPE type) => _type = type;

  /// Returns the RWPM JSON representation for this [Publication]'s manifest, as a string.
  String get jsonManifest => JsonCodec().encode(manifest.toJson()).replaceAll('\\/', '/');

  /// The URL where this publication is served, computed from the [Link] with `self` relation.
  Uri? get baseUrl => links.firstWithRel('self')?.let((it) => it.href.toUrlOrNull()?.removeLastComponent());

  /// Finds the first [Link] with the given HREF in the publication's links.
  ///
  /// Searches through (in order) [readingOrder], [resources] and [links] recursively following
  /// [alternate] and [children] links.
  ///
  /// If there's no match, try again after removing any query parameter and anchor from the
  /// given [href].
  Link? linkWithHref(String href) {
    Link? find(String href) =>
        readingOrder.deepLinkWithHref(href) ?? resources.deepLinkWithHref(href) ?? links.deepLinkWithHref(href);

    return find(href) ?? find(href.takeWhile((it) => !'#?'.contains(it)));
  }

  /// Finds the first [Link] having the given [rel] in the publications's links.
  Link? linkWithRel(String rel) => manifest.linkWithRel(rel);

  /// Finds all [Link]s having the given [rel] in the publications's links.
  List<Link> linksWithRel(String rel) => manifest.linksWithRel(rel);

  /// Finds the first [Link] to the publication's cover (rel = cover).
  Link? get coverLink => linkWithRel('cover');

  /// Finds the first resource [Link] (asset or [readingOrder] item) at the given relative path.
  Link? resourceWithHref(String href) => readingOrder.deepLinkWithHref(href) ?? resources.deepLinkWithHref(href);

  /// Sets the URL where this [Publication]'s RWPM manifest is served.
  void setSelfLink(String href) {
    final list = manifest.links.toList()
      ..removeWhere((it) => it.rels.contains('self'))
      ..add(Link(href: href, type: MediaType.readiumWebpubManifest.toString(), rels: {'self'}));
    manifest.links = list;
  }

  /// Returns the [links] of the first child [PublicationCollection] with the given role, or an
  /// empty list.
  List<Link> linksWithRole(String role) => subcollections[role]?.firstOrNull?.links ?? [];

  @override
  List<Object?> get props => [manifest, cssStyle, nbPages];

  @override
  String toString() => 'Publication{metadata: $metadata, nbPages: $nbPages}';

  /// Creates the base URL for a [Publication] locally served through HTTP, from the
  /// publication's [filename] and the HTTP server [port].
  ///
  /// Note: This is used for backward-compatibility, but ideally this should be handled by the
  /// Server, and set in the self [Link]. Unfortunately, the self [Link] is not available
  /// in the navigator at the moment without changing the code in reading apps.
  static String localBaseUrlOf(String filename, int port) {
    final sanitizedFilename = filename.removePrefix('/').hashWith(crypto.md5).let((it) => Uri.encodeComponent(it));
    return 'http://127.0.0.1:$port/$sanitizedFilename';
  }

  /// Gets the absolute URL of a resource locally served through HTTP.
  static String localUrlOf(String filename, int port, String href) => localBaseUrlOf(filename, port) + href;
}

enum TYPE { epub, cbz, fxl, webpub, audio, divina }

class EXTENSION {
  const EXTENSION._(this.value);
  static const EXTENSION epub = EXTENSION._('.epub');
  static const EXTENSION cbz = EXTENSION._('.cbz');
  static const EXTENSION json = EXTENSION._('.json');
  static const EXTENSION divina = EXTENSION._('.divina');
  static const EXTENSION audio = EXTENSION._('.audiobook');
  static const EXTENSION lcpl = EXTENSION._('.lcpl');
  static const EXTENSION unknown = EXTENSION._('');
  static const List<EXTENSION> _values = [epub, cbz, json, divina, audio, lcpl, unknown];

  final String value;

  static EXTENSION? fromString(String type) => _values.firstOrNullWhere((element) => element.value == type);
}
