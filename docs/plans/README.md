# Plans

This directory holds implementation plans, parity audits, and retained reference plans for
`flutter_readium`.

## Structure

- `docs/plans/` — implemented or historical plans kept for reference. Completed files usually carry
	an `> **✅ Implemented**` note near the top.
- `docs/plans/todo/` — still-actionable plans.
- `docs/plans/upstream/` — plans whose real fix belongs in an upstream Readium toolkit rather than
	in this plugin.

## Open plans (`todo/`)

- **[todo/web-search.md](todo/web-search.md)** — `searchInPublication` still throws
	`UnimplementedError` on web. *(Cross-platform parity / M)*
- **[todo/cross-platform-search-options.md](todo/cross-platform-search-options.md)** — expose
	native `SearchOptions` through the plugin API. *(Upstream feature / M)*
- **[todo/epub-theme-presets.md](todo/epub-theme-presets.md)** — add a plugin-owned EPUB
	presets convenience layer (`light` / `dark` / `sepia`) as a QoL feature, rather than as upstream
	parity. *(Plugin QoL / S-M)*
- **[todo/divina-panel-zoom-plan.md](todo/divina-panel-zoom-plan.md)** — native DiViNa panel
	zoom/pan approach exploration. *(Cross-platform parity / M-L)*
- **[todo/native-comic-panel-pan-handoff.md](todo/native-comic-panel-pan-handoff.md)** — follow-up
	native comic cue framing work after the shared narration sync API landed. *(Cross-platform parity / M-L)*
- **[todo/native-reader-interaction-navigation-plan.md](todo/native-reader-interaction-navigation-plan.md)** —
	disentangle manual reader interaction from page-navigation/manual-mode signaling. *(Cross-platform parity / M)*

## Upstream plans (`upstream/`)

- **[upstream/upstream-audio-error-surfacing-plan.md](upstream/upstream-audio-error-surfacing-plan.md)** —
	contribute proper `AudioNavigator` failure surfacing to `readium/swift-toolkit`. *(Upstream contribution / M)*

## Implemented reference plans

- **[web-decorations.md](web-decorations.md)** — web decoration rendering and interaction.
- **[web-goto-locator-precision.md](web-goto-locator-precision.md)** — full-locator web navigation.
- **[web-error-event.md](web-error-event.md)** — web error event stream.
- **[web-comic-support-plan.md](web-comic-support-plan.md)** — comic helper injection and web panel sync.
- **[locator-field-priority.md](locator-field-priority.md)** — iOS locator-field compensation for reflowables.
- **[pdf-preferences-gaps.md](pdf-preferences-gaps.md)** — iOS PDF preference surface expansion.
- **[decoration-active-flag.md](decoration-active-flag.md)** — active decoration flag and styling follow-up.
- **[comic-manual-zoom-plan.md](comic-manual-zoom-plan.md)** — native comic manual zoom/pan behavior.
- **[ios-audio-error-recovery-plan.md](ios-audio-error-recovery-plan.md)** — audio streaming failure recovery plan that has since landed locally.
- **[cross-platform-audio-stall-watchdog.md](cross-platform-audio-stall-watchdog.md)** — synchronized progress-based audiobook stall detection and regressions for iOS, Android, and web.
- **[native-divina-sync-plan.md](native-divina-sync-plan.md)** — implemented shared narration-sync/manual-mode slice; remaining comic framing work was split out.

---

## Considered and deferred

- **Web TTS audit** — The original audit produced a `web-tts.md` plan claiming web TTS was entirely unimplemented. That premise is incorrect: `WebTTSEngine` lives at [flutter_readium/web/src/TTS/ttsNavigator.ts](../../flutter_readium/web/src/TTS/ttsNavigator.ts) and the full `ttsEnable` / `play` / `pause` / `stop` / `next` / `previous` / voice-selection surface is wired through `ReadiumReader.ts`. A genuine TTS parity audit (word-level highlighting, decoration sync, missing-voice fallback) is still worthwhile but needs a fresh investigation against the current code.

- **Media overlay on web audit** — Same staleness: the original `media-overlay-missing-on-web.md` plan was written against an outdated snapshot. Media Overlay (`application/vnd.readium.narration+json`) and Guided Navigation (`application/guided-navigation+json`) both play through `audioEnable` on web today via [Audio/mediaOverlayNavigator.ts](../../flutter_readium/web/src/Audio/mediaOverlayNavigator.ts) and [Audio/guidedNavigation.ts](../../flutter_readium/web/src/Audio/guidedNavigation.ts). Any follow-up parity work in this area should start from a fresh audit.

- **Positions list API** — Both upstream toolkits compute a `positionsByReadingOrder` list internally but do not expose it as a public API on their navigators. The Dart `PositionsList` model exists, but surfacing it would require either polling the publication-level service or adding a dedicated method-channel call. Consumer demand is low compared to the maintenance cost; deferred.

- **LCP (Readium LCP)** — The README explicitly notes LCP is not currently supported. The upstream toolkits include an LCP adapter, and the model layer has a `Drm` class, but enabling LCP requires a license agreement with EDRLab and significant keystore / DRM lifecycle work beyond a parity fix. Intentionally out of scope.

- **CBZ / DIVINA / image formats** — The swift-toolkit includes a CBZ navigator module; the Dart plugin has no support and there is no current consumer demand. Not a parity issue; a new feature category. Deferred.

- **OPDS feed integration** — The Dart model layer includes rich OPDS types (`Feed`, `OPDSPublication`, etc.), but the plugin exposes no method to fetch or parse an OPDS feed URL. This is a convenience feature (consumers can fetch OPDS themselves and parse the JSON); deferred.

- **Content accessibility metadata** — The `Metadata` model includes an `Accessibility` type but `Publication.metadata.accessibility` is never used in the UI layer. Surfacing it as a structured property is low effort but also low consumer demand. Deferred.
