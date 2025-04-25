import '../_index.dart';

extension ReadiumLinkExtension on Link {
  Link setCurrentToc(final Uri tocUri, {bool foundMatch = false}) {
    if (foundMatch) {
      return this;
    }

    final updated = copyWith(
      properties: (properties ?? const Properties()).copyWith(
        xIsCurrentToc: foundMatch = href.contains(tocUri.toString()),
      ),
    );

    final tocChildren = children;

    return !foundMatch && tocChildren != null
        ? copyWith(
            children: tocChildren
                .setCurrentTocItem(
                  tocUri,
                  tryWithoutFragment: false,
                )
                .toList(),
          )
        : updated;
  }

  Link setTocLevelNo([final int level = 0]) => copyWith(
        properties: (properties ?? const Properties()).copyWith(
          xTocLevel: level,
        ),
      );

  int get tocLevel => properties?.xTocLevel ?? 0;

  bool get isCurrentToc => properties?.xIsCurrentToc ?? false;

  List<Link> toFlattenedTocLink() => [
        this,
        ...?children?.toFlattenedToc(),
      ];
}
