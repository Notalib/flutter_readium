import '../_index.dart';

/// Represents a cursor position in the document text.
class DomPosition {
  const DomPosition({required this.node, required this.charOffset});

  static DomPosition? fromBoundary({
    required final XmlDocument document,
    required final Boundary boundary,
  }) {
    final node = document.querySelector(boundary.cssSelector);
    final charOffset = boundary.charOffset;
    return node == null || charOffset == null
        ? null
        : DomPosition(node: node, charOffset: charOffset);
  }

  final XmlNode node;
  final int charOffset;

  /// Returns an equivalent `_DomPosition` where `node` is the actual text node at `offset`.
  DomPosition local() {
    var offset = charOffset;
    for (final n in node.depthFirstChildren()) {
      if (n.isTextNode) {
        final length = n.domText().length;
        if (offset < length) {
          return DomPosition(node: n, charOffset: offset);
        }
        offset -= length;
      }
    }
    R2Log.e('CharOffset out of bounds');

    // ignore: avoid_returning_this
    return this;
  }

  /// Returns an equivalent `_DomPosition` with `ancestor` as the node. Returns null if `ancestor`
  /// isn't an ancestor.
  DomPosition? offsetInAncestor(final XmlNode ancestor) {
    if (node != ancestor && !node.isAncestor(ancestor)) {
      // R2Log.e('!ancestor ${node.shortString()} ${ancestor.shortString()}');
      return null;
    }
    var offset = charOffset;
    for (final n in ancestor.depthFirstChildren()) {
      if (n == node) {
        return DomPosition(node: ancestor, charOffset: offset);
      }
      if (n.isTextNode) {
        offset += n.domText().length;
      }
    }
    R2Log.e('CharOffset out of bounds');

    return null;
  }

  /// Compares the text offsets of this and that, relative to a common ancestor.
  int? compareTo(final DomPosition that) {
    final ancestor = node.commonAncestor(that.node);
    return ancestor == null
        ? null
        : offsetInAncestor(ancestor)!
            .charOffset
            .compareTo(that.offsetInAncestor(ancestor)!.charOffset);
  }

  bool get isPageBreak => node.isPageBreak;

  bool get hasPageBreak => node.hasPageBreak;

  bool get isOrHasPageBreak => node.isOrHasPageBreak;

  @override
  String toString() => 'DomPosition(node: ${node.shortString()}, charOffset: $charOffset)';
}
