# Platform Parity Plans

This directory contains decision-grade gap analysis and implementation plans for `flutter_readium`. Each plan describes either a feature from an upstream Readium toolkit that is not yet exposed through the Dart API (**Upstream feature**), or a place where iOS, Android, and Web behave differently within the plugin itself (**Cross-platform parity**).

Plans are split into **Open** (still actionable) and **Implemented** (kept for reference; the work has landed). Completed plan files carry an `> **✅ Implemented**` note at the top.

## Open plans

- **[web-search.md](web-search.md)** — `searchInPublication` throws `UnimplementedError` on web; iOS and Android fully implement it via their native `SearchService`. **This is the only remaining gap required for Web to reach feature parity with native.** *(Cross-platform parity / M)*

- **[cross-platform-search-options.md](cross-platform-search-options.md)** — `searchInPublication` accepts only a plain query string; both upstream toolkits expose `SearchOptions` (caseSensitive, wholeWord, diacriticSensitive, regularExpression, language) that are not forwarded. Affects iOS + Android (web is out of scope until web-search.md lands). *(Upstream feature / M)*

- **[epub-theme-preference.md](epub-theme-preference.md)** — `docs/api-reference/preferences.md` documents an `EpubThemeType` enum (`light`/`dark`/`sepia`) that does not exist in any platform. A doc/code mismatch to resolve by either implementing the feature or removing the reference — missing equally on all platforms, so not a web-vs-native gap. *(Upstream feature / S)*

## Implemented

These plans have been implemented on the `feat/web-feature-parity` branch and are retained for reference.

- **[web-decorations.md](web-decorations.md)** — `applyDecorations` now renders highlights/underlines and fires `onDecorationInteraction` on web. *(Cross-platform parity / M)*

- **[web-goto-locator-precision.md](web-goto-locator-precision.md)** — Web `goToLocator` now passes the full serialised `Locator` (cssSelector / progression / text) instead of href-only. *(Cross-platform parity / M)*

- **[locator-field-priority.md](locator-field-priority.md)** — swift-toolkit's reflowable navigator positions via `fragments.first` and ignores `cssSelector` (unlike kotlin/ts), so media-overlay books resumed at the chapter top on iOS. The plugin now promotes the DOM anchor into `fragments.first` for the swift visual navigator. *(Cross-platform parity / S)*

- **[web-error-event.md](web-error-event.md)** — `onErrorEvent` on web is now a real broadcast stream rather than throwing `UnimplementedError`. *(Cross-platform parity / S)*

- **[web-comic-support-plan.md](web-comic-support-plan.md)** — Nota comic-book media-overlay EPUBs now pan/zoom panels on web (helper bundle injected into the navigator iframe), with the spurious yellow highlight suppressed. *(Cross-platform parity / M)*

- **[pdf-preferences-gaps.md](pdf-preferences-gaps.md)** — `offsetFirstPage`, `spread`, and `visibleScrollbar` PDF preferences are now surfaced in the Dart model. *(Upstream feature / S)*

- **[decoration-active-flag.md](decoration-active-flag.md)** — The `isActive` flag (plus `spotlight`/`ruler` styles) was implemented, then **extracted to the stacked PR `feat/decoration-styles`** to keep this branch web-focused. Not present on `feat/web-feature-parity`; tracked on that PR. *(Upstream feature / S)*

---

## Considered and deferred

- **Web TTS audit** — The original audit produced a `web-tts.md` plan claiming web TTS was entirely unimplemented. That premise is incorrect: `WebTTSEngine` lives at [flutter_readium/web/src/TTS/ttsNavigator.ts](../../flutter_readium/web/src/TTS/ttsNavigator.ts) and the full `ttsEnable` / `play` / `pause` / `stop` / `next` / `previous` / voice-selection surface is wired through `ReadiumReader.ts`. A genuine TTS parity audit (word-level highlighting, decoration sync, missing-voice fallback) is still worthwhile but needs a fresh investigation against the current code.

- **Media overlay on web audit** — Same staleness: the original `media-overlay-missing-on-web.md` plan was written against an outdated snapshot. Media Overlay (`application/vnd.readium.narration+json`) and Guided Navigation (`application/guided-navigation+json`) both play through `audioEnable` on web today via [Audio/mediaOverlayNavigator.ts](../../flutter_readium/web/src/Audio/mediaOverlayNavigator.ts) and [Audio/guidedNavigation.ts](../../flutter_readium/web/src/Audio/guidedNavigation.ts). Any follow-up parity work in this area should start from a fresh audit.

- **Positions list API** — Both upstream toolkits compute a `positionsByReadingOrder` list internally but do not expose it as a public API on their navigators. The Dart `PositionsList` model exists, but surfacing it would require either polling the publication-level service or adding a dedicated method-channel call. Consumer demand is low compared to the maintenance cost; deferred.

- **LCP (Readium LCP)** — The README explicitly notes LCP is not currently supported. The upstream toolkits include an LCP adapter, and the model layer has a `Drm` class, but enabling LCP requires a license agreement with EDRLab and significant keystore / DRM lifecycle work beyond a parity fix. Intentionally out of scope.

- **CBZ / DIVINA / image formats** — The swift-toolkit includes a CBZ navigator module; the Dart plugin has no support and there is no current consumer demand. Not a parity issue; a new feature category. Deferred.

- **OPDS feed integration** — The Dart model layer includes rich OPDS types (`Feed`, `OPDSPublication`, etc.), but the plugin exposes no method to fetch or parse an OPDS feed URL. This is a convenience feature (consumers can fetch OPDS themselves and parse the JSON); deferred.

- **Content accessibility metadata** — The `Metadata` model includes an `Accessibility` type but `Publication.metadata.accessibility` is never used in the UI layer. Surfacing it as a structured property is low effort but also low consumer demand. Deferred.
