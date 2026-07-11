# Locator Field Priority — reflowable positioning asymmetry

> **✅ Implemented.** The plugin now compensates on iOS (see *Compensation* below). Retained as a reference for the underlying toolkit asymmetry — read this before touching media-overlay locator construction or the swift visual-navigator entry points.

**Type:** Cross-platform parity
**Platforms affected:** iOS (primary), with kotlin/ts behaviour documented for contrast

## The asymmetry

When navigating to a `Locator` inside a **reflowable** resource, each upstream toolkit
resolves the location from a *different priority order* of `Locator` fields. Crucially, the
swift-toolkit does **not** use `locations.cssSelector` at all:

| Toolkit | Source | Priority order | Honors `cssSelector`? |
|---|---|---|---|
| **kotlin** 3.2.0 | `scrollToLocator` (`navigator/.../_scripts/src/utils.js`) | `text.highlight` → **`cssSelector`** → `fragments` → `progression` (never referenced) | ✅ |
| **swift** 3.9.0 | `EPUBReflowableSpreadView.go(to:)` | `text.highlight` → **`fragments.first`** (used as a DOM tag id via `scroll(toTagID:)`) → `progression` | ❌ |
| **web** (ts-toolkit) | `EpubNavigator.goTo(locator)` | resolves `cssSelector` / `text.highlight` (see [web-goto-locator-precision.md](web-goto-locator-precision.md)) | ✅ (verify when touching) |

### Consequence

A `Locator` whose DOM anchor lives **only** in `locations.cssSelector` positions correctly
on Android/web but lands at the **top of the resource** on iOS, because swift takes
`fragments.first`, treats it as a DOM element id, and finds nothing.

This bit media-overlay (sync-narration) **resume**. The persisted MO "combined" locator
(built by `FlutterMediaOverlayItem.toCombinedLocator`) has this shape:

```
href:      41654-0003-generic.xhtml         // text resource — correct chapter
locations:
  cssSelector:      "#pegs00022"            // the real DOM anchor — swift ignores this
  fragments:        ["t=105.600155338"]     // audio time fragment — swift uses this as a tag id ❌
  position:         3
  progression:      0.469…                  // audio progression (not text)
  totalProgression: 0.360…
```

On iOS `go(to:)` called `scroll(toTagID: "t=105.600155338")`, found no such element, and
showed the chapter start. Once playback began it snapped to the right place, because that
path (`syncToLocator`) goes to a *clean* text locator from `asTextLocator` whose
`fragments.first` is the bare DOM id.

## Compensation (the rule)

**For the swift visual navigator, the DOM anchor must be in `fragments.first`.** The plugin
enforces this two ways:

1. **Consumer-side promotion** — `Locator.promotingTextAnchorForVisualNav()`
   ([utils/ReadiumExtensions.swift](../../flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/ReadiumExtensions.swift))
   promotes a simple `#id` css anchor to `fragments.first`. Applied at the two iOS entry
   points that hand a (possibly MO/audio-shaped) locator to the navigator:
   `EPUBNavigatorViewController` `initialLocation`
   ([EPUBReaderView.swift](../../flutter_readium/ios/flutter_readium/Sources/flutter_readium/EPUBReaderView.swift) init)
   and `goToLocator`. This fixes **already-persisted** locators and any cssSelector-only
   locator from a TOC entry / bookmark. Complex selectors and anchorless locators are left
   untouched (falls back to swift's `progression`).

2. **Producer-side hardening** — `toCombinedLocator`
   ([model/FlutterMediaOverlay.swift](../../flutter_readium/ios/flutter_readium/Sources/flutter_readium/model/FlutterMediaOverlay.swift))
   keeps the text DOM-id fragment ahead of the audio `t=…` fragment, so newly-persisted MO
   locators are self-sufficient for swift without relying on promotion. `Locator.timeOffset`
   still finds the `t=` fragment by prefix regardless of order, so audio mapping is unaffected.

`toClientFriendlyLocator` is deliberately **not** involved: it normalizes the pure-audio
locator inside `mapToTimebasedState`, but for MO books `submitTimebasedPlayerStateToListener`
overrides `currentLocator` with the combined locator, bypassing it.

## Gotcha for future work

Don't "simplify" the promotion/hardening away on the assumption that `cssSelector` is honored
everywhere — it is not honored by swift-toolkit 3.9.0. If a future swift-toolkit upgrade
starts resolving `cssSelector` in `EPUBReflowableSpreadView.go(to:)`, this compensation
becomes redundant and can be removed; verify against that version's `go(to:)` first.
