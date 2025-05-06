import '../_index.dart';

/// ================================
///
/// XmlDocument Extension
///
/// ================================
extension ReadiumXmlDocumentExtension on XmlDocument {
  /// Should be some library function for this, but can't find one.
  XmlElement? querySelector(final String selector) => CssSelector(selector).query(this);

  /// Should be some library function for this, but can't find one.
  Iterable<XmlElement> querySelectorAll(final String selector) =>
      CssSelector(selector).queryAll(this);
}

/// ================================
///
/// XmlElement Extension
///
/// ================================
extension ReadiumXmlElementExtension on XmlElement {
  /// Number of text characters in `ancestor` before the start of `element`.
  int? offsetInAncestor(final XmlElement ancestor) {
    if (!isAncestor(ancestor)) {
      return null;
    }
    var offset = 0;
    for (final n in ancestor.depthFirstChildren()) {
      if (n == this) {
        return offset;
      }
      if (n is XmlText) {
        offset += n.value.length;
      }
    }
    assert(false);
    return null;
  }
}

/// ================================
///
/// XmlNode Extension
///
/// ================================
extension ReadiumXmlNodeExtension on XmlNode {
  /// If node is either a regular text node or a CDATA (unescaped text) node.
  bool get isTextNode {
    final type = nodeType;
    return type == XmlNodeType.TEXT || type == XmlNodeType.CDATA;
  }

  bool get isPageBreak => attributes.any(
        (final attr) => attr.localName == 'type' && attr.value.toLowerCase().contains('pagebreak'),
      );

  String? get id => getAttribute('id');

  // TODO: removed use of FlutterReadium.state
  String? get lang => getAttribute('lang');

  String? get idCssSelector => id != null ? '#$id' : null;

  bool get hasPageBreak => children.any((final child) => child.isPageBreak);

  bool get isOrHasPageBreak => isPageBreak || hasPageBreak;

  // TODO: removed use of FlutterReadium.state
  String get physicalPageIndexSemanticsLabel => altOrText;

  String get altOrText => getAttribute('alt') ?? domText();

  /// Recursively returns all children of node in document order.
  Iterable<XmlNode> depthFirstChildren() sync* {
    yield this;
    for (final child in nodes) {
      yield* child.depthFirstChildren();
    }
  }

  /// True if `ancestor` is an ancestor of `node`.
  bool isAncestor(final XmlNode ancestor) => ancestors.contains(ancestor);

  /// Returns nearest common ancestor element of e1 and e2, or null if none exists.
  XmlNode? commonAncestor(final XmlNode e2) {
    var a = this;
    var b = e2;
    while (b.depth < a.depth) {
      a = a.parent!;
    }
    // https://github.com/dart-lang/linter/issues/2478
    // ignore: invariant_booleans
    while (a.depth < b.depth) {
      b = b.parent!;
    }
    while (a != b) {
      if (a.depth == 0) {
        return null;
      }
      a = a.parent!;
      b = b.parent!;
    }
    return a;
  }

  String shortString() {
    final self = this;
    return self is XmlElement
        ? '<${self.name}>'
        : self is XmlText
            ? '"${domText()}"'
            : nodeType.toString();
  }

  /// Normalize line endings for consistency with the Javascript DOM.
  String domText() => (value ?? innerText).replaceAll(RegExp(r'[\r\n\t]+'), ' ');

  /// Try to find the closest node.
  XmlNode? closest(final XmlNode? Function(XmlNode element) find) {
    final found = find(this);
    if (found != null) {
      return this;
    }

    if (hasParent) {
      return parent?.closest(find);
    }

    return null;
  }
}
