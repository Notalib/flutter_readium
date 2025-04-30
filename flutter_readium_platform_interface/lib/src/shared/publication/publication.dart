import '../index.dart';
import '../../_index.dart';

part 'publication.freezed.dart';
part 'publication.g.dart';

/// Readium Web Publication Manifest
///
/// * [Publication Json Schema](https://readium.org/webpub-manifest/schema/publication.schema.json)
///
/// AllOf:
/// * [Epub Publication Json Schema](https://readium.org/webpub-manifest/schema/extensions/epub/subcollections.schema.json)
@freezedExcludeUnion
abstract class Publication with _$Publication {
  @r2JsonSerializable
  const factory Publication({
    /// Each Link Object in a publication collection must contain a `rel` with
    /// value:
    ///   "const": "self"
    ///
    /// "uniqueItems": true,
    required final List<Link> links,
    required final Metadata metadata,

    /// All resources listed in the reading order should contain a media `type`.
    ///
    /// "uniqueItems": true
    required final List<Link> readingOrder,

    /// anyOf:
    ///   String
    ///   List<String>
    ///
    /// "uniqueItems": true
    @JsonKey(name: '@context') @stringListJson final List<String>? context,

    /// All resources listed in the publication should contain a media `type`.
    ///
    /// "uniqueItems": true
    final List<Link>? resources,
    final List<Link>? toc,
    final List<Link>? landmarks,

    /// List of audio clips.
    final List<Link>? loa,

    /// List of illustrations.
    final List<Link>? loi,

    /// List of tables.
    final List<Link>? lot,

    /// List of video clips.
    final List<Link>? lov,
    @JsonKey(fromJson: _badPageListWorkaround) final List<Link>? pageList,
  }) = _Publication;

  factory Publication.fromJson(final Map<String, dynamic> json) =>
      _$PublicationFromJson(JsonUtils.trimStringsInMap(json));

  const Publication._();

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
        yield* deepLinks(link.alternate);
        yield* deepLinks(link.children);
      }
    }

    final allDeepLinks = [readingOrder, resources, links].expand(deepLinks);

    Link? find(final String href) =>
        allDeepLinks.firstWhereOrNull((final link) => link.href == href);

    final full = find(href);
    if (full != null) {
      return full;
    }
    final split = href.indexOf(_hrefEnd);
    return split == -1 ? null : find(href.substring(0, split));
  }

  /// Creates a new [Locator] object from a [Link] to a resource of this manifest.
  ///
  /// Returns null if the resource is not found in this manifest.
  Locator? locatorFromLink(
    final Link link, {
    final MediaType? typeOverride,
  }) {
    final href = link.href;
    final hashIndex = href.indexOf(_hrefEnd);
    final hrefHead = hashIndex == -1 ? href : href.substring(0, hashIndex);
    final hrefTail = hashIndex == -1 ? null : href.substring(hashIndex + 1);
    final resourceLink = linkWithHref(hrefHead);
    final type = resourceLink?.type ?? typeOverride?.value;
    final linkIndex = resourceLink == null ? -1 : readingOrder.indexOf(resourceLink);
    return type == null
        ? null
        : Locator(
            href: hrefHead,
            type: type,
            title: resourceLink!.title ?? link.title,
            locations: Locations(
              cssSelector: hrefTail != null && hrefTail.isNotEmpty ? '#$hrefTail' : null,
              fragments: hrefTail == null ? null : [hrefTail],
              progression: hrefTail == null ? 0 : null,
              position: linkIndex == -1 ? null : linkIndex + 1,
            ),
          );
  }
}

extension PublicationExtension on Publication {
  String get identifier => metadata.identifier ?? 'unidentified';

  String get title => metadata.title.values.first;

  String? get subtitle => metadata.subtitle?.values.first;

  String? get description => metadata.description;

  String? get author => metadata.author?.map((final a) => a.name.values.first).join(', ');

  String? get artist => metadata.artist?.map((final a) => a.name.values.first).join(', ');

  String? get subjects => metadata.subject?.join('; ');

  Link? get coverLink => resources?.firstWhereOrNull(
        (final r) =>
            (r.rel?.contains('cover') ?? false) ||
            (r.href.contains('cover') && r.type == MediaType.jpeg.type ||
                r.type == MediaType.png.type),
      );

  Uri? get coverUri => coverLink != null ? Uri.tryParse(coverLink!.href) : null;

  /// Estimates total progression duration in book, based on current chapter and current progression
  /// in chapter.
  Progressions calculateProgressions({
    required final int index,
    required final double progression,
  }) {
    //used to calculate totalProgression
    var numerator = 0.0;
    var denominator = 0.0;
    var progressionDuration = Duration.zero;
    var totalProgressionDuration = Duration.zero;
    readingOrder.forEachIndexed((final i, final link) {
      // Size of chapter in seconds or characters. As long as all chapters use the same unit as each
      // other, this works.
      final size = (link.duration ?? link.properties?.xCharacters ?? link.height ?? 1.0).toDouble();
      final chapterDuration = const Duration(seconds: 1) * (link.duration ?? .0);
      denominator += size;
      if (i < index) {
        numerator += size;
        totalProgressionDuration += chapterDuration;
      } else if (i == index) {
        numerator += progression * size;
        progressionDuration = chapterDuration * progression;
        totalProgressionDuration += progressionDuration;
      }
    });
    final haveTime = totalProgressionDuration != Duration.zero;

    return Progressions(
      progression: progression.clamp(0.0, 1.0),
      totalProgression: (numerator / denominator).clamp(0.0, 1.0),
      progressionDuration: haveTime ? progressionDuration : null,
      totalProgressionDuration: haveTime ? totalProgressionDuration : null,
    );
  }
}

List<Link>? _badPageListWorkaround(final dynamic shouldBeAList) =>
    ((shouldBeAList is Map<String, dynamic> ? shouldBeAList['links'] : shouldBeAList) as List?)
        ?.map((final x) => Link.fromJson(x as Map<String, dynamic>))
        .toList();

final _hrefEnd = RegExp('[#?]');
