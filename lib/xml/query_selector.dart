import '../_index.dart';

const _spam = false;

// 1: name, 2: #id, 3: :nth-child(), 4: <, 5: ' ', otherwise: error
final _selectorRegex =
    RegExp(r'([a-zA-Z_][-0-9a-zA-Z_]*)|#([-0-9a-zA-Z_]+)|:nth-child\(([0-9]+)\)| *> *()| +()|.');

enum _CssPartType { initial, child, descendant }

class _CssPart {
  const _CssPart({required this.type, required this.name, required this.id, required this.index});

  final _CssPartType type;
  final String? name;
  final String? id;
  final int? index;

  bool matches(final int elementIndex, final XmlElement element) =>
      (name == null || name == element.name.local) &&
      (id == null || id == element.getAttribute('id')) &&
      (index == null || index == elementIndex);
}

List<_CssPart>? _parseSelector(final String selector) {
  final parts = <_CssPart>[];

  bool? needEmit;
  var type = _CssPartType.initial;
  String? name;
  String? id;
  int? index;
  void emit({required final _CssPartType nextType}) {
    parts.add(_CssPart(type: type, name: name, id: id, index: index));
    type = nextType;
    name = null;
    id = null;
    index = null;
  }

  for (final match in _selectorRegex.allMatches(selector.trim())) {
    final mName = match[1];
    final mId = match[2];
    final mNthChild = match[3];
    final mChild = match[4];
    final mDescendant = match[5];
    if (mName != null) {
      if (_spam) R2Log.d('name=$mName');
      if (name != null && name != mName) {
        R2Log.e('Double name in "$selector"');
        return null;
      }
      name = mName;
      needEmit = true;
    } else if (mId != null) {
      if (_spam) R2Log.d('id=$mId');
      if (id != null && id != mId) {
        R2Log.e('Double id in "$selector"');
        return null;
      }
      id = mId;
      needEmit = true;
    } else if (mNthChild != null) {
      final mIndex = int.parse(mNthChild, radix: 10) - 1;
      if (_spam) R2Log.d('index=$mIndex');
      if (index != null && index != mIndex) {
        R2Log.e('Double nth-child in "$selector"');
        return null;
      }
      index = mIndex;
      needEmit = true;
    } else if (mChild != null) {
      if (_spam) R2Log.d('Recurse ">"');
      if (needEmit != true) {
        R2Log.e('Double ">" in "$selector"');
        return null;
      }
      emit(nextType: _CssPartType.child);
      needEmit = false;
    } else if (mDescendant != null) {
      if (_spam) R2Log.d('Recurse " "');
      emit(nextType: _CssPartType.descendant);
      needEmit = false;
    } else {
      R2Log.d('TODO: Find a real css selector parser.');
      R2Log.e('Could not parse "$selector"');
      return null;
    }
  }
  switch (needEmit) {
    case null:
      R2Log.e('Empty selector "$selector"');
      return null;
    case false:
      R2Log.e('Missing final part in "$selector"');
      return null;
    case true:
      emit(nextType: _CssPartType.descendant);
      return parts;
  }
}

/// A CSS selector which can locate the element of this block.
class CssSelector {
  CssSelector(this.value) : _parts = _parseSelector(value);

  final String value;
  final List<_CssPart>? _parts;

  bool get valid => _parts != null;

  /// A Boundary pointing to `offset` relative to this block.
  Boundary boundary(final int offset) =>
      Boundary(cssSelector: value, textNodeIndex: 0, charOffset: offset);

  /// Returns a DomRange with the given offsets relative to this block.
  DomRange domRange({required final int start, final int? end}) =>
      DomRange(start: boundary(start), end: end == null ? null : boundary(end));

  /// Queries the first matching element in the document.
  XmlElement? query(final XmlDocument document) => queryAll(document).firstOrNull;

  /// Lazily queries matching elements in the document.
  ///
  /// Caveat/feature/bug:
  /// May return the same element multiple times if it matches in multiple ways, such as querying
  /// "a b c" in "<a><b><b><c/></b><b></a>" matching c twice (due to on matching either b).
  Iterable<XmlElement> queryAll(final XmlDocument document) {
    final parts = _parts;
    if (parts == null) {
      return const [];
    }

    Iterable<XmlElement> possibleMatches = const []; // Unused dummy initial value.
    for (final part in parts) {
      Iterable<XmlElement> expander(final int i, final XmlElement e) sync* {
        if (part.matches(i, e)) {
          yield e;
        }
        // Search all descendents recursively, unless specifying only direct children, with ">".
        if (part.type != _CssPartType.child) {
          yield* e.childElements.expandIndexed(expander);
        }
      }

      possibleMatches = part.type == _CssPartType.initial
          ? expander(0, document.rootElement)
          : possibleMatches
              .expand((final element) => element.childElements.expandIndexed(expander));
    }
    return possibleMatches;
  }

  @override
  String toString() => '"$value"';

  Map<String, dynamic> toJson() => {
        'value': value,
      };
}
