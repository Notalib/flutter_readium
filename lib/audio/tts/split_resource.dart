import 'dart:math';

import '../../_index.dart';

/// Very approximate length of time that it takes to read one character with TTS.
const durationPerCharacter = Duration(microseconds: 1e6 ~/ 15);

/// A resource, probably a chapter.
class ResourceData {
  const ResourceData({
    required this.link,
    required this.length,
    required this.document,
    required this.blocks,
    required this.mediaItem,
  });

  /// Readium Link to the resource.
  final Link link;

  /// Length of the chapter.
  final int length;

  /// Parsed XHTML of the resource.
  final XmlDocument document;

  final List<TextBlock> blocks;

  /// A MediaItem which describes the chapter, including its estimated Duration.
  final MediaItem mediaItem;

  /// Estimated reading Duration of the resource.
  Duration get duration => durationPerCharacter * length;

  DomPosition? domPosition(final Boundary boundary) {
    final node = document.querySelector(boundary.cssSelector);
    if (node == null) {
      R2Log.d('Query failed: ${boundary.cssSelector}');
    }
    final offset = boundary.charOffset ?? 0;
    return node == null ? null : DomPosition(node: node, charOffset: offset);
  }

  @override
  String toString() =>
      'ResourceData(link: $link, length: $length, document: $document, blocks: $blocks, mediaItem: $mediaItem)';
}

/// A block of text, should be a paragraph.
class TextBlock {
  const TextBlock({
    required this.cssSelector,
    required this.beginPos,
    required this.element,
    this.text,
    this.alt,
  }) : assert(text != null || alt != null);

  /// The text in this block (paragraph).
  final String? text;

  /// The alt-text of this image (not a paragraph).
  final String? alt;

  /// A CSS selector which can locate the element of this block.
  final String cssSelector;

  /// Starting position of the block relative to the chapter.
  final int beginPos;

  /// The XmlElement this block corresponds to.
  final XmlElement element;

  /// Text or alt text.
  String get textOrAlt => text ?? alt ?? '';

  /// Length of text. Zero if this block is an image with alt-text.
  int get length => text?.length ?? 0;

  /// End position of the block relative to the chapter.
  int get endPos => beginPos + length;

  /// Returns lang attribute of this block element.
  String? get lang => element.lang;

  /// Returns closest lang attribute of this block element.
  String? get closestLang => element.closest((final el) => el.lang != null ? el : null)?.lang;

  /// Returns TTS speakable text and filters the physical page number based on
  /// `physicalPageIndexVisible` state settings.
  String get speakableText {
    final speakPhysicalPageIndex = FlutterReadium.state.ttsSpeakPhysicalPageIndex;

    if (element.isPageBreak) {
      return speakPhysicalPageIndex ? element.physicalPageIndexSemanticsLabel : '';
    }

    if (element.hasPageBreak) {
      return element.children
          .map(
            (final child) => child.isPageBreak
                ? (speakPhysicalPageIndex ? child.physicalPageIndexSemanticsLabel : '')
                : child.altOrText,
          )
          .join();
    }

    return textOrAlt;
  }

  @override
  String toString() =>
      'TextBlock(text: $text, alt: $alt, cssSelector: $cssSelector, beginPos: $beginPos, element: $element)';
}

/// Split an XHTML document into a sequence of section texts and corresponding CSS selectors.
///
/// Originally inspired by splitResourceAndAddToUtterances in r2-testapp-kotlin, but completely
/// rewritten so that it works with more than one book.
ResourceData? splitResource(
  final Link link,
  final XmlDocument document,
  final int index,
  final Publication publication,
) {
  final coverUri = FlutterReadium.state.pubCoverUri;

  const path = 'body';
  final element = document.rootElement.getElement(path);
  if (element == null) {
    R2Log.d('NO ELEMENTS FOUND');
    return null;
  }
  var pos = 0;
  Iterable<TextBlock> processElement(final XmlElement element, final String path) sync* {
    // If at least one of our direct children has a text node without just whitespace, yield us in a
    // single block/paragraph.
    final hasNonemptyTextNodes = element.children
        .any((final node) => node.isTextNode && node.domText().trimRight().isNotEmpty);
    if (hasNonemptyTextNodes) {
      final text = element.domText();

      // Remove 'em' tags from children
      for (final node in element.children) {
        // Check if the node is an 'em' element
        if (node is XmlElement && node.name.local.toLowerCase() == 'em') {
          // Get the parent of the 'em' element
          final parent = node.parent;
          // Create a new text node with the same text as the 'em' element
          final textNode = XmlText(node.innerText);
          // If the parent is not null, replace the 'em' element with the new text node in the parent's list of children
          if (parent != null) {
            parent.children[parent.children.indexOf(node)] = textNode;
          }
        }
      }

      // Merge adjacent XmlText nodes
      for (var i = 0; i < element.children.length - 1; i++) {
        // Get the current node and the next node
        final node = element.children[i];
        final nextNode = element.children[i + 1];
        // If both nodes are XmlText nodes, merge them
        if (node is XmlText && nextNode is XmlText) {
          // Create a new text node with the combined text of the two nodes
          final mergedNode = XmlText(node.value + nextNode.value);
          // Replace the first node with the new merged node in the element's list of children
          element.children[i] = mergedNode;
          // Remove the second node from the element's list of children
          element.children.removeAt(i + 1);
          // Decrement the index to check the new merged node in the next iteration
          i--;
        }
      }

      yield TextBlock(text: text, cssSelector: path, beginPos: pos, element: element);
      pos += text.length;
      return;
    }

    // Are we an image? If so, yield our alt-text.
    if (element.name.local.toLowerCase() == 'img') {
      final alt = element.getAttribute('alt');
      if (alt != null && alt.isNotEmpty) {
        yield TextBlock(alt: alt, cssSelector: path, beginPos: pos, element: element);
      }
    }

    // We don't directly contain text, so go recursive.
    var n = 1;
    for (final node in element.children) {
      if (node is XmlElement) {
        // Recurse now. We prefer referring to the element by its id, if it has one.
        final id = node.getAttribute('id');
        final ePath = id == null ? '$path > :nth-child($n)' : '#$id';
        yield* processElement(node, ePath);
        ++n;
      } else if (node.isTextNode) {
        // Text node just contains whitespace, but take its length into account.
        pos += node.domText().length;
      }
    }
  }

  var blocks = processElement(element, path).toList();

  // Return a dummy block if the chapter is empty, so that navigation to the chapter works.
  if (blocks.isEmpty) {
    blocks = [TextBlock(text: '', cssSelector: path, beginPos: 0, element: element)];
  }

  return ResourceData(
    link: link,
    length: pos,
    document: document,
    blocks: blocks,
    mediaItem: ttsMediaItem(
      publication: publication,
      index: index,
      link: link,
      length: pos,
      artUri: coverUri,
    ),
  );
}

MediaItem ttsMediaItem({
  required final Publication publication,
  required final int index,
  required final Link link,
  required final Uri? artUri,
  final int? length,
}) =>
    MediaItem(
      // The id must be unique, or memoised functions of MediaItems return the wrong result.
      id: 'TTS-${publication.identifier}-$index',
      title: link.title ?? '',
      // Switching album and artist value to display correct text order in Control Center.
      artist: publication.title,
      album: publication.author ?? publication.artist,
      genre: publication.subjects,
      duration: durationPerCharacter * max(length ?? link.properties?.xCharacters ?? 0, 1),
      displaySubtitle: publication.subtitle,
      displayDescription: publication.description,
      artUri: artUri,
    );
