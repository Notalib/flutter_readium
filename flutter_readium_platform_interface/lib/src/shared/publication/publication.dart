// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/shared/lib/src/publication/manifest.dart
// renamed to Publication.

// ignore_for_file: must_be_immutable

import 'package:collection/collection.dart';
import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';

import '../../extensions/uri.dart';
import '../../utils/href.dart';
import '../../utils/jsonable.dart';
import '../mediatype.dart';
import 'link.dart';
import 'link_list_extension.dart';
import 'locator.dart';
import 'metadata.dart';
import 'publication_collection.dart';
import 'subcollection_map.dart';

/// Holds the metadata of a Readium publication, as described in the Readium Web Publication Manifest.
class Publication with EquatableMixin implements JSONable {
  Publication({
    required this.metadata,
    this.context = const [],
    this.links = const [],
    this.readingOrder = const [],
    this.resources = const [],
    this.tableOfContents = const [],
    this.subCollections = const {},
  });

  final List<String> context;
  final Metadata metadata;
  List<Link> links;
  final List<Link> readingOrder;
  final List<Link> resources;
  final List<Link> tableOfContents;
  final Map<String, List<PublicationCollection>> subCollections;

  List<Link> get toc => tableOfContents;

  String get identifier => metadata.identifier ?? 'unidentified';

  Publication copyWith({
    List<String>? context,
    Metadata? metadata,
    List<Link>? links,
    List<Link>? readingOrder,
    List<Link>? resources,
    List<Link>? tableOfContents,
    Map<String, List<PublicationCollection>>? subCollections,
  }) => Publication(
    context: context ?? this.context,
    metadata: metadata ?? this.metadata,
    links: links ?? this.links,
    readingOrder: readingOrder ?? this.readingOrder,
    resources: resources ?? this.resources,
    tableOfContents: tableOfContents ?? this.tableOfContents,
    subCollections: subCollections ?? this.subCollections,
  );

  @override
  List<Object> get props => [context, metadata, links, readingOrder, resources, tableOfContents, subCollections];

  /// Finds the first [Link] with the given relation in the manifest's links.
  Link? linkWithRel(String rel) =>
      readingOrder.firstWithRel(rel) ?? resources.firstWithRel(rel) ?? links.firstWithRel(rel);

  /// Finds all [Link]s having the given [rel] in the manifest's links.
  List<Link> linksWithRel(String rel) => (readingOrder + resources + links).filterByRel(rel);

  /// Serializes a [Publication] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putIterableIfNotEmpty('@context', context)
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson())
      ..put('readingOrder', readingOrder.toJson())
      ..putIterableIfNotEmpty('resources', resources)
      ..putIterableIfNotEmpty('toc', tableOfContents);
    subCollections.appendToJsonObject(json);
    return json;
  }

  @override
  String toString() => toJson().toString().replaceAll('\\/', '/');

  /// Returns the [links] of the first child [PublicationCollection] with the given role, or an
  /// empty list.
  List<Link> collectionLinks(String role) => subCollections[role]?.firstOrNull?.links ?? [];

  static LinkHrefNormalizer normalizeHref(String baseUrl) =>
      (href) => Href(href, baseHref: baseUrl).string;

  /// Parses a [Publication] from its RWPM JSON representation.
  ///
  /// If the publication can't be parsed, a warning will be logged with [warnings].
  /// https://readium.org/webpub-manifest/
  /// https://readium.org/webpub-manifest/schema/publication.schema.json
  static Publication? fromJson(Map<String, dynamic>? json, {bool packaged = false}) {
    if (json == null) {
      return null;
    }
    String baseUrl;
    if (packaged) {
      baseUrl = '/';
    } else {
      final href = Link.fromJSONArray(json.optJSONArray('links')).firstWithRel('self')?.href;
      baseUrl = href?.let((it) => Uri.tryParse(it)?.removeLastComponent().toString()) ?? '/';
    }

    final context = json.optStringsFromArrayOrSingle('@context', remove: true);
    final metadata = Metadata.fromJson(
      json.safeRemove<Map<String, dynamic>>('metadata'),
      normalizeHref: normalizeHref(baseUrl),
    );
    if (metadata == null) {
      Fimber.i('[metadata] is required $json');
      return null;
    }

    final links = Link.fromJSONArray(json.safeRemove<List<dynamic>>('links'), normalizeHref: normalizeHref(baseUrl))
        .map(
          (it) => (!packaged || !it.rels.contains('self'))
              ? it
              : it.copyWith(
                  rels: it.rels
                    ..remove('self')
                    ..add('alternate'),
                ),
        )
        .toList();
    // [readingOrder] used to be [spine], so we parse [spine] as a fallback.
    final readingOrderJSON = json.safeRemove<List<dynamic>>('readingOrder');
    final readingOrder = Link.fromJSONArray(
      readingOrderJSON,
      normalizeHref: normalizeHref(baseUrl),
    ).where((it) => it.type != null).toList();

    final resources = Link.fromJSONArray(
      json.safeRemove<List<dynamic>>('resources'),
      normalizeHref: normalizeHref(baseUrl),
    ).where((it) => it.type != null).toList();

    final tableOfContents = Link.fromJSONArray(
      json.safeRemove<List<dynamic>>('toc'),
      normalizeHref: normalizeHref(baseUrl),
    );

    // Parses subcollections from the remaining JSON properties.
    final subcollections = PublicationCollection.collectionsFromJSON(json, normalizeHref: normalizeHref(baseUrl));

    return Publication(
      context: context,
      metadata: metadata,
      links: links,
      readingOrder: readingOrder,
      resources: resources,
      tableOfContents: tableOfContents,
      subCollections: subcollections,
    );
  }

  Locator? locatorFromLink(final Link link, {final MediaType? typeOverride}) {
    final href = link.href;
    final hashIndex = href.indexOf(_hrefEnd);
    final hrefHead = hashIndex == -1 ? href : href.substring(0, hashIndex);
    final hrefTail = hashIndex == -1 ? null : href.substring(hashIndex + 1);
    final resourceLink = linkWithHref(hrefHead);
    final type = resourceLink?.type ?? typeOverride?.name;
    final linkIndex = resourceLink == null ? -1 : readingOrder.indexOf(resourceLink);
    return type == null
        ? null
        : Locator(
            href: hrefHead,
            type: type,
            title: resourceLink!.title ?? link.title,
            locations: Locations(
              cssSelector: hrefTail != null && hrefTail.isNotEmpty ? '#$hrefTail' : null,
              fragments: hrefTail == null ? [] : [hrefTail],
              progression: hrefTail == null ? 0 : null,
              position: linkIndex == -1 ? null : linkIndex + 1,
            ),
          );
  }

  /// Finds the first [Link] with the given HREF in the manifest's links.
  ///
  /// Searches through (in order) [readingOrder], [resources] and [links] recursively following
  /// alternate and children links.
  ///
  /// If there's no match, try again after removing any query parameter and anchor from the
  /// given [href].
  Link? linkWithHref(final String href) {
    Iterable<Link> deepLinks(final List<Link>? list) sync* {
      for (final link in list ?? const <Never>[]) {
        yield link;
        yield* deepLinks(link.alternates);
        yield* deepLinks(link.children);
      }
    }

    final allDeepLinks = [readingOrder, resources, links].expand(deepLinks);

    Link? find(final String href) => allDeepLinks.firstWhereOrNull((final link) => link.href == href);
    final full = find(href);
    if (full != null) {
      return full;
    }
    final split = href.indexOf(_hrefEnd);
    return split == -1 ? null : find(href.substring(0, split));
  }

  final _hrefEnd = RegExp('[#?]');
  Link? get coverLink => resources.firstWhereOrNull(
    (final r) =>
        (r.rels.contains('cover')) ||
        (r.href.contains('cover') && r.type == MediaType.jpeg.type || r.type == MediaType.png.type),
  );

  Uri? get coverUri => coverLink != null ? Uri.tryParse(coverLink!.href) : null;

  bool get conformsToReadiumAudiobook =>
      metadata.conformsTo?.any((c) => c == 'https://readium.org/webpub-manifest/profiles/audiobook') == true;

  bool get conformsToReadiumEbook =>
      metadata.conformsTo?.any((c) => c == 'https://readium.org/webpub-manifest/profiles/epub') == true;

  bool get containsMediaOverlays =>
      readingOrder.any((link) => link.alternates.any((alt) => alt.type == MediaType.syncMediaNarration.name));
}
