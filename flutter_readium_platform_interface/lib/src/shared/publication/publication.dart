// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// Originally from https://github.com/Mantano/iridium/blob/main/components/shared/lib/src/publication/manifest.dart
// renamed to Publication.

// ignore_for_file: must_be_immutable

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

final _hrefEnd = RegExp('[#?]');

/// Holds the metadata of a Readium publication, as described in the Readium Web Publication Manifest.
@immutable
class Publication with Equatable implements JSONable {
  const Publication({
    required this.metadata,
    this.context = const [],
    this.links = const [],
    this.readingOrder = const [],
    this.resources = const [],
    this.tableOfContents = const [],
    this.subCollections = const {},
  });

  /// JSON-LD context URIs declaring the vocabulary used by this manifest.
  final List<String> context;

  /// Bibliographic and descriptive metadata (title, author, language, etc.).
  final Metadata metadata;

  /// Publication-level links (e.g. `self`, `alternate`, cover, guided navigation document).
  final List<Link> links;

  /// Ordered list of content documents that make up the reading experience.
  final List<Link> readingOrder;

  /// Resources referenced by the publication but not part of the reading order
  /// (images, audio files, stylesheets, etc.).
  final List<Link> resources;

  /// Hierarchical table of contents. Use [tocFlattened] for a flat list.
  final List<Link> tableOfContents;

  /// Named sub-collections beyond the standard manifest fields (e.g. page-list, landmarks).
  final Map<String, List<PublicationCollection>> subCollections;

  /// Alias for [tableOfContents].
  List<Link> get toc => tableOfContents;

  /// Returns a flattened version of the table of contents, where all children links are recursively.
  List<Link> get tocFlattened => tableOfContents.flatten();

  /// The publication's unique identifier, or `'unidentified'` if none is set.
  String get identifier => metadata.identifier ?? 'unidentified';

  /// Returns a copy of this publication with the given fields replaced.
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
  List<Object> get props => [
    context,
    metadata,
    links,
    readingOrder,
    resources,
    tableOfContents,
    subCollections,
  ];

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

  /// Parses a [Publication] from its RWPM JSON representation.
  ///
  /// If the publication can't be parsed, a warning will be logged.
  /// https://readium.org/webpub-manifest/
  /// https://readium.org/webpub-manifest/schema/publication.schema.json
  static Publication? fromJson(
    Map<String, dynamic>? json, {
    bool packaged = false,
  }) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final context = jsonObject.optStringsFromArrayOrSingle(
      '@context',
      remove: true,
    );
    final metadata = Metadata.fromJson(
      jsonObject.optNullableMap('metadata', remove: true),
    );
    if (metadata == null) {
      ReadiumLog.i('[metadata] is required $jsonObject');
      return null;
    }

    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true))
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
    final readingOrderJSON = jsonObject.safeRemove<List<dynamic>>(
      'readingOrder',
    );
    final readingOrder = Link.fromJsonArray(
      readingOrderJSON,
    ).where((it) => it.type != null).toList();

    final resources = Link.fromJsonArray(
      jsonObject.safeRemove<List<dynamic>>('resources'),
    ).where((it) => it.type != null).toList();

    final tableOfContents = Link.fromJsonArray(
      jsonObject.safeRemove<List<dynamic>>('toc'),
    );

    // Parses subcollections from the remaining JSON properties.
    final subcollections = PublicationCollection.collectionsFromJSON(
      jsonObject,
    );

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

  /// Creates a [Locator] pointing at the given [link].
  ///
  /// Resolves the resource type from the manifest when possible, falling back
  /// to [typeOverride]. Returns `null` if no type can be determined.
  Locator? locatorFromLink(final Link link, {final MediaType? typeOverride}) {
    final (href, fragments) = link.href.splitPathAndFragment();
    final resourceLink = linkWithHref(href);
    final type = resourceLink?.type ?? typeOverride?.name;
    final linkIndex = resourceLink == null ? -1 : readingOrder.indexOf(resourceLink);
    return type == null
        ? null
        : Locator(
            href: href,
            type: type,
            title: resourceLink!.title ?? link.title,
            text: LocatorText(),
            locations: Locations(
              cssSelector: fragments != null && fragments.isNotEmpty ? '#$fragments' : null,
              fragments: fragments == null ? [] : [fragments],
              progression: fragments == null ? 0 : null,
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

  /// The cover [Link], found by `rel=cover` or by href/type heuristics. `null` if not present.
  Link? get coverLink => resources.firstWhereOrNull(
    (final r) =>
        (r.rels.contains('cover')) ||
        (r.href.contains('cover') && r.type == MediaType.jpeg.type || r.type == MediaType.png.type),
  );

  /// The parsed URI of the cover resource, or `null` if no cover link is present.
  Uri? get coverUri => coverLink != null ? Uri.tryParse(coverLink!.href) : null;

  /// Whether the publication declares conformance to the Readium Audiobook profile.
  bool get conformsToReadiumAudiobook =>
      metadata.conformsTo?.any(
        (c) => c == 'https://readium.org/webpub-manifest/profiles/audiobook',
      ) ==
      true;

  /// Whether the publication declares conformance to the Readium EPUB profile.
  bool get conformsToReadiumEbook =>
      metadata.conformsTo?.any(
        (c) => c == 'https://readium.org/webpub-manifest/profiles/epub',
      ) ==
      true;

  bool get conformsToReadiumPDF =>
      metadata.conformsTo?.any(
        (c) => c == 'https://readium.org/webpub-manifest/profiles/pdf',
      ) ==
      true;

  /// Whether the publication declares conformance to the Readium DiViNa profile.
  /// This is true for CBZ comics and other image-based publications parsed by the ImageParser.
  bool get conformsToReadiumDivina =>
      metadata.conformsTo?.any(
        (c) => c == 'https://readium.org/webpub-manifest/profiles/divina',
      ) ==
      true;

  /// Whether any reading-order item carries a media overlay alternate —
  /// either the older `application/vnd.syncnarr+json` or the newer
  /// Readium Sync Narration `application/vnd.readium.narration+json` format.
  bool get containsMediaOverlays =>
      conformsToReadiumEbook &&
      readingOrder.any(
        (link) => link.alternates.any(
          (alt) =>
              MediaType.syncMediaNarration.matchesFromName(alt.type) ||
              MediaType.readiumNarration.matchesFromName(alt.type),
        ),
      );

  /// Whether the publication has a guided navigation document (`application/guided-navigation+json`),
  /// either as a publication-level link or as per-item alternates in the reading order.
  ///
  /// Recognised for both EPUB ebooks (narrated text) and DiViNa comics (narrated
  /// image panels) — guided navigation is profile-agnostic, and a DiViNa with a
  /// guided-navigation document is the native form of Nota's narrated comics.
  bool get containsGuidedNavigation =>
      (conformsToReadiumEbook || conformsToReadiumDivina) &&
      (links.any(
            (link) => MediaType.syncMediaNarrationManifest.matchesFromName(link.type),
          ) ||
          readingOrder.any(
            (link) => link.alternates.any(
              (alt) => MediaType.syncMediaNarrationManifest.matchesFromName(
                alt.type,
              ),
            ),
          ));

  /// Whether this publication should be treated as an audiobook — true for the Readium Audiobook
  /// profile and for any EPUB/WebPub that carries audio-text sync data (media overlays or guided navigation).
  bool get isAudioBook => conformsToReadiumAudiobook || containsMediaOverlays || containsGuidedNavigation;
}
