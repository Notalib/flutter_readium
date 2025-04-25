import '../_index.dart';

extension ReadiumLinksExtension on Iterable<Link> {
  Iterable<Link> setCurrentTocItem(
    final Uri tocUri, {
    final bool tryWithoutFragment = true,
  }) sync* {
    for (final link in this) {
      final updatedLink = link.setCurrentToc(tocUri);

      if (tryWithoutFragment) {
        // We are in the same link but no match toc were found. Try to highlight the link anyway
        // without fragment.
        final hasCurrent = updatedLink.toFlattenedTocLink().any((final link) => link.isCurrentToc);
        final linkHrefUri = Uri.tryParse(link.href);

        if (!hasCurrent && linkHrefUri != null && tocUri.path == linkHrefUri.path) {
          yield link.setCurrentToc(linkHrefUri.replace(fragment: null));
          continue;
        }
      }

      yield updatedLink;
    }
  }

  Iterable<Link> toFlattenedToc([final int level = 0]) sync* {
    for (final link in this) {
      yield link.setTocLevelNo(level);

      final children = link.children;
      if (children != null) {
        yield* children.toFlattenedToc(level + 1);
      }
    }
  }
}
