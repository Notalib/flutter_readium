import { Locator, LocatorText, TextElement, TextSegment } from "@readium/shared";

/** Context kept on each side of a spoken word, like the upstream content iterator. */
const CONTEXT_MAX_LENGTH = 50;

/**
 * Finds the segment containing `charIndex` of the utterance text. The utterance
 * speaks `TextElement.text`, which joins the segments with no separator, so a
 * segment starts where the previous one ends.
 */
function segmentAt(
  element: TextElement,
  charIndex: number
): { segment: TextSegment; start: number } | null {
  let start = 0;
  for (const segment of element.segments) {
    const end = start + segment.text.length;
    if (charIndex >= start && charIndex < end) return { segment, start };
    start = end;
  }
  return null;
}

/**
 * Locator of the segment containing `charIndex` of the utterance text, used
 * for sentence boundaries. Falls back to the element's locator when the
 * element has no segments or the index is outside its text.
 */
export function segmentLocatorForCharIndex(element: TextElement, charIndex: number): Locator {
  return segmentAt(element, charIndex)?.segment.locator ?? element.locator;
}

/**
 * Locator of the word spoken at `charIndex` of the utterance text, for a
 * `word` boundary event. `text.highlight` is the word and `text.before` /
 * `text.after` its surrounding text, so the decorator anchors the word itself
 * within the segment's element.
 *
 * Some engines report `charLength` 0; the word then runs to the next
 * whitespace. A word is cut at the end of its segment, because the segment's
 * CSS selector is the root the decorator searches in.
 */
export function wordLocatorForCharIndex(
  element: TextElement,
  charIndex: number,
  charLength: number
): Locator | null {
  const text = element.text ?? "";
  // Skip whitespace in case an engine reports the boundary before the word.
  while (charIndex < text.length && /\s/.test(text[charIndex])) charIndex++;

  const found = segmentAt(element, charIndex);
  if (!found) return null;
  const { segment, start } = found;
  const segmentEnd = start + segment.text.length;

  let end: number;
  if (charLength > 0) {
    end = Math.min(charIndex + charLength, segmentEnd);
  } else {
    end = charIndex;
    while (end < segmentEnd && !/\s/.test(text[end])) end++;
  }
  const highlight = text.slice(charIndex, end).trimEnd();
  if (!highlight) return null;

  // The segment locator's `before` already ends with the segment's leading
  // whitespace, so continue it from the first non-blank character.
  const segmentText = segment.text;
  const leading = segmentText.length - segmentText.trimStart().length;
  const before =
    (segment.locator.text?.before ?? "") + text.slice(start + leading, charIndex);
  const after = text.slice(charIndex + highlight.length);

  return new Locator({
    href: segment.locator.href,
    type: segment.locator.type,
    title: segment.locator.title,
    locations: segment.locator.locations,
    text: new LocatorText({
      before: before.slice(-CONTEXT_MAX_LENGTH),
      highlight,
      after: after.slice(0, CONTEXT_MAX_LENGTH),
    }),
  });
}
