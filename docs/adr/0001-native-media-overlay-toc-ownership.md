# ADR 0001: Sync Narration ToC ownership and navigation

- **Status:** Accepted; native implementation validated on simulators. Web implementation validated by focused ChromeDriver integration with autoplay enabled.
- **Date:** 2026-10-13
- **Scope:** Sync Narration on iOS, Android and web.
- **Tasks:** [Native checklist](../plans/native-media-overlay-toc-context.md), [web checklist](../plans/web-media-overlay-toc-context.md)

## Context and evidence

A Table of Contents (ToC) target can be an audio-less section containing narrated
children. [PR #259](https://github.com/Notalib/flutter_readium/pull/259) added inheritance
and structural seeking on Android. [PR #273](https://github.com/Notalib/flutter_readium/pull/273)
adds inheritance on iOS, but not structural seeking. Its reviewed head is `ae6b702`;
this implementation starts from main `c3b2225`.

The fixture inspection covered 38 Sync Narration documents and 330 cues in seven WebPubs:
`TestResources` at `05abfbeb`, and current `readium-test-resources` at `fd0c3d6d`.

- The current `38533_overlay_preview-toc-section-child` fixture targets an XHTML section
  without audio. Its narrated heading and paragraphs must inherit that section.
- Ordinary previews target narrated headings followed by paragraphs inside a wrapper.
  Continuing the heading's ToC reference is existing behavior worth preserving.
- No sampled JSON combines a matching container with a different matching descendant
  heading. The parent-reset regression is reproducible with that synthetic combination:
  #273 and Android give the heading its subsection, then the next paragraph its ancestor.
- Five `TestResources/WebPub/ValidWithAudio` documents contain the next file's first page
  cue under the previous file's container. Both files have their own fragmentless ToC entry.
  Unrestricted inheritance assigns that boundary cue to the previous chapter.
- All sampled JSON has one wrapper level followed by cues. It does not establish semantics
  for deeper subsection boundaries, headings without audio, or parents owning no cues.

The cross-file sequence also exists in the source SMIL. Narration grouping therefore
cannot be assumed to mean strict DOM containment. These are fixture observations, not
claims that upstream Readium specifies the ownership policy below.

## Decision

Resolve Sync Narration ownership in the parser, while resource identities and recursive
lists are still available. Enrichment adds titles to those assignments without applying
another global ownership window. Guided Navigation keeps its existing enrichment path.

### Current-section ownership

Each recursive narration list keeps a current ToC reference, initially inherited from its
caller. For a node in that list:

1. Restrict inherited/current ownership to the node's text resource. On a resource change,
   use that resource's fragmentless ToC entry if present; otherwise clear the reference.
2. A matching container supplies its own ToC reference to its children, even without audio.
3. A directly matching playable cue becomes the current ToC reference for following
   same-resource siblings only when it has no narration children. This preserves
   narrated-heading continuation over an ancestor.
4. A non-matching cue uses the current reference. No known reference means no assigned owner.
5. Recurse with the node's effective reference and preserve cue order, timing and position.
   State changes inside a nested list do not mutate its caller's current reference.

A nested container's own match must not replace the caller's active heading. Generic
wrappers inherit their caller's reference; headings inside continue within that wrapper's
list. A heading activated inside a wrapper does not escape its list. This is a conservative
implementation boundary, not an inferred XHTML section boundary. Deeper authoring shapes
need explicit examples and tests before extending the contract.

Do not activate an audio-less flat heading as a new continuation target. That would add
behavior absent from the current flat-cue enrichment and is outside the observed cases.

### Anchored navigation

Use existing explicit-time lookup first, then exact text-resource/anchor lookup, then
lookup by an assigned ToC reference. The latter selects the first cue owned by the target.
Use the complete resource-plus-fragment identity; repeated anchor names in other files
must not match. Candidate lookup must inspect each cue's resource rather than rejecting
an overlay solely because its first cue references a different resource.

A recognized structural anchor is a precise destination and works even when resource
fallback is disabled. This intentionally gives iOS Android's existing behavior: selecting
or tapping a known section anchor can seek to its first cue in the currently playing file.
An unknown same-file anchor still cannot rewind playback through resource fallback
(issue #139). The current locator API cannot distinguish a ToC click from a tap on the
same known section anchor; this decision applies to both. Integration tests must
check known section requests and unknown-anchor no-rewind behavior.

An unmatched audio seek must also leave the cached resume locator unchanged. The Android
integration test exposed an existing caller bug: it cached a rejected anchor even though
no audio seek occurred, so `play(null)` later tried that anchor and did not resume. Preserve
the old cached locator when Sync Narration has no mapping. Android's existing public
navigation acknowledgment remains unchanged; measure playback position, not that boolean.

Fragmentless links retain their existing resource/progression navigation. Explicit audio
time, image lookup and locator serialization keep their existing priorities and formats.

On web, the shared mapper opts into this policy only for Sync Narration. Active `goTo`
and `play` requests use the installed audio publication, which may differ from newly
loaded publication flags. Guided Navigation retains its parser, global enrichment and
legacy mapper defaults, including priority when both narration formats are present.
Web keeps its existing href normalization and progression calculation. An unmapped
explicit Sync play or reused-enable request leaves the active playback state and
position untouched; retry after terminal failure retains its existing resume fallback.

### Case contract

| Case | Owner / navigation result |
| --- | --- |
| Audio-less parent with narrated children | Children inherit parent; anchored parent seeks to first owned cue |
| Narrated subsection heading followed by same-list paragraphs | Heading and paragraphs use subsection, not the ancestor |
| Generic wrapper around those paragraphs | Inherit the starting reference; continue heading inside its list |
| Heading inside wrapper, cue after wrapper | Restore caller's current reference; no heading leakage from nested list |
| Matching nested container, cue after it | Container match applies inside; caller's reference applies afterward |
| Cue moves to another resource with a file-only ToC entry | Assign that resource's ToC entry, not the previous resource's chapter |
| Cue moves to another resource without such an entry | Clear inherited ownership until a direct match supplies it |
| Exact cue anchor also appears as an assigned ToC reference | Exact cue match wins |
| Known structural anchor with resource fallback disabled | Seek to its first owned cue |
| Unknown anchor with resource fallback disabled | Return no match; leave playback untouched |
| Same anchor name in different files | Match resource and anchor together |
| No matching ToC / empty or invalid narration | No fabricated owner or cue; existing parser validation remains |
| Node has its own audio and children | Emit own cue first, then children; preserve original traversal order |
| Fragmentless or time-bearing locator | Preserve existing resource/progression and explicit-time behavior |

## Alternatives and deferred work

- Keeping #273's precedence preserves parent inheritance but introduces the subsection-reset
  edge case and the observed cross-file misassignment.
- Always preferring a global last match leaks references across recursive/resource boundaries.
- DOM inspection adds content loading and another ownership source; it is unnecessary for
  the cases in this change.
- A separate target-to-first-descendant index is deferred. It is needed if a parent has only
  cues owned by nested subsections, but the sampled fixtures do not demonstrate that case.
  This implementation does not claim such a parent has a precise seek destination.
- Audio-less flat headings, cross-file inheritance of an anchored parent, URL-normalization
  changes and Guided Navigation structural inheritance remain out of scope.

No shared Dart API, preference, bridge field or native overlay storage/index is added.
The implementation does not expand iOS's synthetic audio reading order to all audio files
within an overlay; ownership/lookup tests on cross-file cues do not prove that existing
multi-audio playback limitation is resolved.

## Validation and follow-up

Keep equivalent Swift/Kotlin cases for ownership and lookup. Use the current #259 fixture
for native integration tests that assert both `tocHref` and seek destination while audio
is already in the same file. Include an unknown-anchor no-rewind check. Preserve the
[locator-field compensation](../plans/locator-field-priority.md).

Record actual test/build/device results in the task checklist. Mark implementation
complete only after those checks; report unavailable device evidence explicitly.
