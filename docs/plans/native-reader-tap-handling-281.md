# Native EPUB tap handling (#281)

Implemented on 2026-10-25; retained as the decision and validation record for [#281](https://github.com/Notalib/flutter_readium/issues/281).

## Problem and decision

Flutter classified pointer releases using a fixed 70 logical-pixel edge while the native Readium adapters used proportional zones. On a 411dp reader, a tap 100dp from the edge both turned the page and opened controls. Changing one threshold would retain two classifiers and their platform differences.

Use the stock native EPUB adapters as the tap authority on Android and iOS. Report a controls action to Dart: ordinary center taps toggle; edge-navigation taps hide, including failed edge attempts. In scroll mode the stock adapter does not turn pages, so ordinary taps anywhere toggle controls. Content-consumed interactions retain their native handling.

Prioritize pagination (approximately 95% of usage). Preserve the public widget API, native zones and reading progression, keyboard input, wake-lock behavior, Flutter Semantics labels/order/geometry and explicit commands. Native publication content keeps its existing accessibility exposure. PDF, DiViNa and web retain their Dart tap path.

## Narration and drag policy

Following is intended to stop when the user manually navigates away from narration. A center tap or a failed edge tap on the narrated page should not stop following. Controls hiding is independent: a deliberate drag beyond the existing pan slop hides active controls even if a turn fails or snaps back; small jitter does not.

For this PR, native tap/key and explicit page commands enter manual mode after the navigator accepts a turn. iOS uses its awaited result and holds narration cues while user navigation is pending. Failed navigation replays the latest held cue through the normal guarded sync path. Counts isolate overlapping operations; superseded readers cannot change the replacement's narration.

Android kotlin-toolkit 3.4.0 reflowable page-turn Booleans indicate acceptance, not completion ([source](https://github.com/readium/kotlin-toolkit/blob/3.4.0/readium/navigator/src/main/java/org/readium/r2/navigator/epub/EpubNavigatorFragment.kt#L882-L914)). Existing page callbacks identify known absolute publication boundaries, allowing those turns to be rejected before they are mistaken for movement. Physical indices are normalized using native reading progression for RTL. Cached state is invalidated on explicit locator navigation, accepted turns, preferences and detach. Unknown state and other failed accepted turns remain a toolkit limitation; this is not a general outcome API.

The user explicitly chose a tap fix now and a swipe-lifecycle follow-up. Paginated swipes retain the existing Flutter manual-mode heuristic, including failed or snapped-back swipes. A successful fast swipe can finish after its native drag-end callback; a failed swipe supplies no reliable settled callback in the pinned APIs. Do not substitute timing guesses or defer one narration cue as a completion signal.

Scroll mode uses a small heuristic: one finger moving predominantly along the reading axis beyond `computePanSlop` enters manual mode once. Taps, jitter, cross-axis movement and a sequence that becomes multi-touch preserve following. A deliberate boundary drag can stop following without displacement; that limitation is accepted. No new offset bridge, setting or cue-visibility system is introduced.

## Integration

- Android retains `DirectionalNavigationAdapter` behind a delegating `OverflowableNavigator`, recording whether an edge turn was attempted independently of its return value.
- iOS retains its adapter and binds it through a private forwarding `VisualNavigator`. Task-local input attribution separates pointer feedback from keys across awaited callbacks. A failed edge turn stays consumed rather than becoming a center tap.
- Per-reader channel feedback enables native tap ownership only for EPUB. Dart's internal pointer tracker handles deliberate drags and the retained legacy paths; the Flutter Semantics command path stays separate.

## Independent validation

Runtime checks used the normal example `PlayerPage` and its production controls with an isolated temporary driver and self-generated synthetic EPUBs. Android API 36 emulator and iOS 27 iPhone simulator were authorized. No live publications or patron data were used.

| Check | Evidence |
|---|---|
| Android original #281 repro | 50dp and 100dp right-edge taps and center taps, each with controls hidden/visible: edges only hide/turn, center only toggles. No transient controls opening on edge taps. |
| Android narration | Successful edge navigation disables following once; center taps preserve it. The original backward-at-first-page failure was reproduced before the boundary guard and passed after it. |
| Android RTL | Native reading progression is RTL; first-resource physical page 17/18 is the logical beginning. A right-edge backward tap preserves following; a left-edge forward tap moves to physical page 16 and disables following once. At the last resource, a forward tap on physical page 0 hides controls without moving (narration was not active). |
| Android scroll | Center/edge taps toggle controls and preserve following; a deliberate reading-axis drag hides controls and disables following once. |
| iOS physical taps | User-operated simulator check with observed logs: center opens controls, proportional-zone and near-edge taps hide controls and advance one page per tap. The user confirmed an extra tap accounts for the extra logged page. |
| Semantics | Normal iOS player previous/next/toggle actions dispatch correctly, preserving explicit-command controls behavior. TTS previous at the first page preserves following; successful next disables it. Android OS tree retains three reader buttons and hides native content. |
| Automated gates | `bin/format`, `bin/analyze`, `bin/changelog check`, all 49 plugin Dart tests, Kotlin compilation/formatting and iOS no-sign build passed. Six Kotlin boundary tests passed. The targeted Dart tracker/channel file contains 17 tests. |
| Review regressions | Independently reproduced multi-touch and overlapping iOS observer failures were corrected. An external pointer repro and a source-matched Swift proxy test against protocol stubs passed; the latter is not native iOS E2E or a committed test. |
| Native iOS regressions | Five RunnerTests passed for image priority at both edges and the center, ignored page images, ordinary tap routing, and stopping narration before or after a failed-turn replay is queued. They use the real Readium observers/adapter and the reader's stop handling. The unsigned iOS build also passed after these corrections. |

Image activation precedes page navigation so edge images keep their content action. Images intentionally excluded from image actions, such as comic page images, fall through to navigation and controls. Narration stop clears held cues and cancels queued replay tasks; cancellation is checked again after JavaScript awaits before navigation. These corrections preserve the tap and narration policy above.

## Remaining coverage and follow-up

Full TalkBack/VoiceOver focus and activation have not been verified. Semantics inspection and direct actions do not establish screen-reader parity. Wider viewports, fixed-layout EPUB, link/selection/image/decoration interaction matrices, PDF, DiViNa and web were not independently exercised end to end for this change. The complete iOS tap matrix and active-narration last-page boundary behavior remain unverified.

Follow up with supported toolkit user-navigation completion/failure callbacks, including swipes and Android accepted-but-unmoved turns, before promising exact following outcomes for every gesture. That work may require a kotlin-toolkit change and a dependent plugin update; it should use event callbacks rather than polling. No upstream PR or toolkit upgrade is included here.
