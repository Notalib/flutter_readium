# ADR 0001: Media-overlay ToC ownership and navigation

- **Status:** Accepted
- **Date:** 2026-10-13; amended 2026-10-16
- **Scope:** Sync Narration on iOS, Android, and web
- **Implementation and evidence:** [Native plan](../plans/native-media-overlay-toc-context.md), [web plan](../plans/web-media-overlay-toc-context.md), [regression record](../plans/media-overlay-adr-regressions.md)

## Context

A Table of Contents (ToC) entry can target a section that has no audio of its own, while its children are narrated. [PR #259](https://github.com/Notalib/flutter_readium/pull/259) and [PR #273](https://github.com/Notalib/flutter_readium/pull/273) exposed a shared ownership problem: parent inheritance can overwrite a narrated subsection, and unrestricted inheritance can carry a chapter into another resource.

Some valid publications list only paragraph cues in Sync Narration and target their enclosing XHTML sections in the ToC. Those sections cannot be found in the narration tree. A heading can also be present in XHTML without containing any narrated cue. Current-section reporting and navigation must handle these shapes consistently across all three platforms.

Ownership describes which section a playing cue belongs to. A navigation destination describes where a request should start playback. They are separate decisions: a cue-less heading may seek forward without owning the following cue.

## Decision

### Ownership from narration

Resolve ownership while recursively traversing the narration. Each list keeps a current reference inherited from its caller.

1. Restrict ownership to the node's text resource. On a resource change, use that resource's file-only ToC entry if present; otherwise clear the reference.
2. A matching container supplies its reference to its children, even without audio.
3. A directly matching playable cue becomes the reference for following same-resource siblings. A narrated subsection therefore continues over its ancestor.
4. A non-matching cue uses the current reference. Without a reference it remains unowned.
5. Recurse with the effective reference, preserving cue order and timing. Changes inside a nested list do not mutate its caller's reference.

Generic wrappers inherit the caller's reference; a heading activated inside a wrapper continues only within that list. A matching nested container does not reset the caller's active heading after the container ends. Do not activate an audio-less flat narration heading as a continuation target.

### Ownership from document order

When narration supplies no owner, resolve ToC starts within the cue's XHTML resource. An anchored entry starts at its exact content id or its first content descendant. When a container and a deeper entry share that start, the deeper entry wins. Unresolved entries do not create a start.

Report the last resolved start at or before the current content. Content before every anchored start uses the resource's file-only entry if present; otherwise it remains unowned. Never assign it to a following section. Preserve an owner already supplied by narration.

An element without narrated descendants does not acquire ownership merely because navigation can seek forward from it. Asynchronous enrichment must not change the destination of an identical navigation request.

### Navigation

Resolve requests in this order:

1. Explicit audio time, preserving its offset.
2. Exact cue identity.
3. Assigned ToC reference, selecting its first owned cue.
4. A known XHTML element: select the first cue at or after the element in document order, including descendants and later siblings. If no cue follows in that resource, return no audio match.
5. Existing resource/progression fallback, only where permitted.

Always match resource plus fragment together. Repeated anchor names in different resources must not match each other. Inspect each cue's resource even when a narration list begins in another file.

A precise structural destination works in the currently playing resource. An unknown or unreadable anchor cannot rewind same-resource playback through resource fallback ([#139](https://github.com/Notalib/flutter_readium/issues/139)). A rejected seek preserves both playback and the cached resume locator. For a different resource, retain existing fallback behavior for unknown anchors. Fragmentless requests retain their existing resource/progression behavior.

The locator API does not distinguish a ToC selection from a tap that produces the same anchor. The same navigation contract applies to both.

### Case contract

| Case | Result |
| --- | --- |
| Audio-less parent with narrated children | Children inherit the parent; selecting the parent seeks to its first owned cue |
| Narrated subsection followed by same-list paragraphs | Heading and paragraphs use the subsection |
| Heading inside a generic wrapper | Continues inside the wrapper; does not escape the list |
| Matching nested container followed by an outside cue | Container owns its children; the caller's reference applies afterward |
| Cue moves to another resource | Use that resource's file-only entry, otherwise clear inherited ownership |
| Prelude before the first anchored entry | File-only owner if present, otherwise unowned |
| Section and deeper heading share their first cue | Deeper heading owns the cue |
| Exact cue also appears as an assigned ToC reference | Exact cue wins |
| Uncued section present in XHTML | Seek to the first cue at or after its element |
| Heading exists but contains no narrated cue | Seek forward to the first cue at or after the heading; do not fabricate an owner |
| Known element after the last cue | No audio match; preserve playback |
| Unknown same-resource anchor | No audio match; preserve playback and resume position |
| Unknown cross-resource anchor | Retain existing resource fallback |
| Same fragment in different resources | Match the full resource and fragment |
| Empty or invalid narration | No fabricated cue or owner |
| Node has audio and children | Emit its cue first, then its children |
| Explicit time or fragmentless locator | Preserve time priority or existing resource/progression behavior |

## Consequences and limits

Enrichment adds titles and document-order owners without replacing narration-derived ownership. XHTML lookup can be lazy and publication-scoped. If parsing fails, only known ids are usable; unknown ids retain the fallback policy above. Strict native XML parsing and browser HTML recovery are implementation limitations, not a promise of identical malformed-document repair. Native regression tests explicitly cover an undeclared `&nbsp;` stopping the index and the equivalent numeric `&#160;` allowing later targets to resolve. Publications should use well-formed XHTML with predefined or numeric entities; we do not enable external DTD loading to repair them.

Guided Navigation retains its existing behavior. This decision adds no public API or bridge fields. URL canonicalization changes, DOM-derived narration scope, cross-resource inheritance of anchored parents, and iOS playback of multiple audio files inside one overlay remain outside its scope.

Keep equivalent ownership and seek regression cases on all three platforms. Unit tests establish the case contract; shared integration tests must assert emitted cue, owner, seek offset, same-file no-rewind/resume, and navigation across resource boundaries. Record actual build, simulator, browser, and device results in the linked plans.

## Alternatives

Keeping parent-first precedence fixes inheritance but resets narrated subsections. A global last-match window leaks ownership across nested lists and resources. Assigning preludes to a following section changes navigation after enrichment. Loading every XHTML file during parser initialization adds another ownership source and unnecessary work; lookup-time document inspection handles the cases that narration alone cannot resolve.
