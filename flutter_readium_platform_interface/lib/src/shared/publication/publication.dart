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
    Object context = unset,
    Object metadata = unset,
    Object links = unset,
    Object readingOrder = unset,
    Object resources = unset,
    Object tableOfContents = unset,
    Object subCollections = unset,
  }) => Publication(
    context: identical(context, unset) ? this.context : (context as List<String>),
    metadata: identical(metadata, unset) ? this.metadata : (metadata as Metadata),
    links: identical(links, unset) ? this.links : (links as List<Link>),
    readingOrder: identical(readingOrder, unset) ? this.readingOrder : (readingOrder as List<Link>),
    resources: identical(resources, unset) ? this.resources : (resources as List<Link>),
    tableOfContents: identical(tableOfContents, unset) ? this.tableOfContents : (tableOfContents as List<Link>),
    subCollections: identical(subCollections, unset)
        ? this.subCollections
        : (subCollections as Map<String, List<PublicationCollection>>),
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

  /// Resolves [locator] against this publication, for when the stored href is
  /// no longer part of the reading order — e.g. the publication was re-issued
  /// with different resource granularity (chapters split/merged, or a
  /// text-with-overlay reading order replaced by an audio-only one).
  ///
  /// Call this before navigating to any persisted [Locator] (last position,
  /// bookmark, highlight) once the publication it was recorded against might
  /// have changed shape. It's safe and cheap to call unconditionally: a
  /// locator whose href is still valid is returned unchanged, without
  /// touching [readingOrder].
  ///
  /// Resolution order:
  ///  1. [linkWithHref] on [Locator.hrefPath] — still valid, returned as-is.
  ///  2. [Locations.totalProgression] mapped onto accumulated [Link.duration]
  ///     across [readingOrder]. Segmentation-independent, so preferred
  ///     whenever every entry has a duration.
  ///  3. [Locations.position] as a 1-based index into [readingOrder]. Exact
  ///     only when the new segmentation happens to line up with the old one,
  ///     so tried last; an out-of-range position resolves to `null` instead
  ///     of throwing.
  ///
  /// Returns `null` when none of the above yields a position — callers
  /// should decide what to do next (e.g. fall back to the first reading-order
  /// link) rather than have this guess.
  Locator? resolveLocator(final Locator locator) {
    if (linkWithHref(locator.hrefPath) != null) {
      return locator;
    }

    final locations = locator.locations;
    final totalProgression = locations?.totalProgression;
    if (totalProgression != null && totalProgression > 0) {
      final resolved = _resolveLocatorByDuration(locator, totalProgression);
      if (resolved != null) {
        return resolved;
      }
    }

    final position = locations?.position;
    if (position == null || position <= 0) {
      return null;
    }

    final index = position - 1;
    return readingOrder.elementAtOrNull(index) == null ? null : _relocate(locator, index, progression: null);
  }

  /// Maps [totalProgression] onto the accumulated [Link.duration] of
  /// [readingOrder], returning the containing link and the offset within it.
  /// Returns `null` if any entry is missing a duration or the total duration
  /// is zero — the caller falls back to [Locations.position] in that case.
  Locator? _resolveLocatorByDuration(final Locator locator, final double totalProgression) {
    final durations = readingOrder.map((final link) => link.duration).toList();
    if (durations.isEmpty || durations.any((final duration) => duration == null)) {
      return null;
    }

    final total = durations.cast<double>().fold(0.0, (final sum, final duration) => sum + duration);
    if (total <= 0) {
      return null;
    }

    final target = totalProgression * total;
    var accumulated = 0.0;
    for (var i = 0; i < readingOrder.length; i++) {
      final duration = durations[i]!;
      final isLastLink = i == readingOrder.length - 1;
      if (target <= accumulated + duration || isLastLink) {
        final progression = duration > 0 ? ((target - accumulated) / duration).clamp(0.0, 1.0) : 0.0;
        return _relocate(locator, i, progression: progression);
      }
      accumulated += duration;
    }
    return null; // Unreachable: the loop always returns on the last link.
  }

  /// Rebuilds [locator] to point at `readingOrder[index]`: [Locator.href] and
  /// [Locator.type] become the resolved link's, [Locations.position] becomes
  /// `index + 1`, and [progression] (when known) replaces the old one.
  /// [Locations.cssSelector] and [Locations.fragments] described the old
  /// resource, so they are dropped rather than carried over.
  ///
  /// Takes the index rather than the [Link] because [Link] compares by value:
  /// a reading order containing two equal entries would resolve to the first
  /// one's index, reporting a position the locator was never at.
  Locator _relocate(final Locator locator, final int index, {required final double? progression}) {
    final link = readingOrder[index];

    return locator.copyWith(
      href: link.href,
      type: link.type ?? locator.type,
      locations: Locations(
        position: index + 1,
        progression: progression,
        totalProgression: locator.locations?.totalProgression,
      ),
    );
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
