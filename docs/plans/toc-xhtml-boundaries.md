# XHTML boundaries for narration ToC ownership

## Problem

Playback can enter an article while the reported ToC entry remains a preceding nested subsection. This happens when a narrated heading activates continuation ownership, but the next article targets an XHTML section absent from the narration containers. Preserving every non-null narration owner carries the preceding heading across that section boundary. The stale owner also makes next-ToC navigation seek to the same article again.

The consumer reproduction exposes both Sync Narration and Guided Navigation. Guided Navigation takes precedence, and its flat cue conversion has the same last-heading continuation problem. The correction therefore runs for both selected sources.

## Correction

Use the existing XHTML element index to reconcile owners before playback and owner-based seek lookup consume the cues. A later ToC target can replace an existing owner only when its element encloses the cue and starts after the owner's element. Only targets absent from exact cue identities, original narration owners, and matched narration containers are candidates. Parsing retains matched container identities independently of cue ownership: child headings can replace every descendant owner and otherwise hide the container after flattening. This preserves directly narrated headings, same-section continuation, and caller ownership after represented nested narration containers.

Inspect only cue-bearing resources with existing owners and unresolved anchored ToC targets. Reuse session indexing where available. Missing owner/cue ids or unreadable XHTML preserve the narration result. Guided Navigation keeps its source priority, time matching, and seek policy; web does not expose its Sync Narration uncued-anchor resolver to guided callers. No public API, bridge field, or dependency version changes.

The contract and limitations are recorded in [ADR 0001](../adr/0001-media-overlay-toc-ownership.md).

## Regression coverage

- Flat narration contains a subsection heading and paragraphs spanning later XHTML sections absent from narration. The heading retains its own cue and same-section paragraphs; later sections receive their own descendants and first-owned-cue navigation destination.
- Represented nested narration containers restore the caller's owner, including when XHTML nesting differs.
- A matched container has no audio and its child heading replaces all descendant owners. For narration `h, side(sub, p2), p3`, owners remain `h, sub, sub, h` after correction even when XHTML places `p3` inside `side`. A separate genuinely absent section still receives its corrected owner. These regressions failed before retaining container identities.
- A synthetic publication offers both narration interfaces with different cue identities. Guided Navigation remains selected, and initialization corrects its owner before navigation. This test failed against the earlier Sync Narration-only guard.
- Existing suites cover resource identity, repeated fragments, first-cue ties, preludes, cue-less headings, malformed XHTML, explicit-time priority, and unknown same-resource no-rewind behavior.

## Verification

| Check | Result |
| --- | --- |
| iOS example device build, `flutter build ios --no-codesign` | Passed, including after diagnostic cleanup |
| App-hosted XCTest | 89 passed; existing `WithTimeoutTests` excluded after the full attempt stalled in its cancellation-ignoring test |
| Final focused Swift ownership and guided-priority tests | 25 passed after retaining matched container identities |
| Android Kotlin compilation and unit tests | Passed; 119 tests passed, 1 existing skip |
| Kotlin formatting | Passed |
| Web tests | 403 passed across 25 suites |
| Web typecheck and example bundle generation | Passed |
| Independent focused web parser/ownership review tests | 90 passed for the container-identity amendment |
| Changelog validation and `git diff --check` | Passed |
| Dart format/analyze | Not required; no Dart or shared API changes |
| Consumer beta on iPhone 18 Pro, iOS 27 simulator | Original reproduction, brief playback, and next/previous navigation passed before the container-identity amendment; live playback not rerun for that amendment |
| Android/browser live playback | Not run |

## Live reproduction and reviews

The rebuilt consumer beta selected the expected article at the original reading position. Navigation advanced from the nested subsection to the article, then to the following article, and returned correctly. Brief playback advanced while retaining the expected owner. These automated checks used the app's existing Redux actions through the Dart VM and inspected native locator/app-state summaries. The user independently confirmed by manual inspection that the display looked correct and the ToC updated when expected.

Temporary count-only diagnostics proved that Guided Navigation was selected and the boundary correction executed. They were removed from the final source, which then passed the iOS build and focused tests again. Committed regressions use invented publication data; raw consumer logs and publication content are excluded.

Independent correctness review and ponytail review found no blocking issues. A synthetic web stress probe took about 3 ms for 300 cues/30 sections, 53 ms for 1000/100, and 1282 ms for 3000/300 in one XHTML resource. Caching element positions and candidate anchors is a nonblocking optimization for larger publications; no slowdown was established in the original reproduction.
