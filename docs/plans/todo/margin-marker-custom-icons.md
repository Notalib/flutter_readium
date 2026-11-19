# Custom Margin Marker Icons

**Type:** Feature
**Platforms affected:** iOS, Android, Web
**Estimated effort:** S
**Status:** Parked until a client asks for an icon the built-in set doesn't cover.

## Context

`DecorationStyle.marginMarker` ([margin-marker-decorations.md](../margin-marker-decorations.md), guide: [margin-markers.md](../../guides/margin-markers.md)) shows a text label or a built-in icon in the page margin. The icons are a closed enum, `MarginMarkerIcon { bookmark, note, star }`. Dart sends the icon's name, and each platform looks it up in its own name → SVG path map:

- iOS: `MarginMarkerConfig.iconPaths` in `reader/EPUBReaderView+Decorations.swift`.
- Android: `MarginMarkerStyle.ICON_PATHS` in `MarginMarkerStyle.kt`.
- Web: `MARGIN_MARKER_ICON_PATHS` in `web/src/decorations/DecorationController.ts`.

Each template wraps the path in the same element: `<svg viewBox="0 0 24 24" width="1.3em" height="1.3em" fill="currentColor" fill-rule="evenodd"><path d="…"/></svg>`. Today a new icon needs a plugin release.

## Proposal: app-supplied SVG path

Let apps pass their own single-path icon as SVG path data, not as markup:

```dart
const MarginMarker.svgPath('M12 2l2.9 6.9 …z', side: MarginSide.start)
```

- **Wire format:** `marker: { "svgPath": "<d>", "side": … }`, next to `label` and `icon`. Exactly one of the three is set; the named constructors make that impossible to get wrong in Dart.
- **Rendering:** the existing icon branch of each template, with the app's path in place of the built-in one. The icon therefore follows `tint` and dark themes, and taps, diffing (`extras` on web) and layout behave exactly like the built-in icons.
- **Validation, on every platform at parse time:** accept only SVG path syntax, that is `^[MmLlHhVvCcSsQqTtAaZz0-9eE.,+\-\s]+$`, with a length cap (say 4 KB). Reject anything else like a marker with no content: skip the decoration and log. Escape the value into the attribute anyway.
- **Constraints to document:** a 24×24 viewBox, a single colour (`currentColor`), and `fill-rule="evenodd"` for holes. Multi-colour icons are out of scope; see option C below.
- **Tests:** Dart round-trip; on each platform, a valid path renders and an invalid one (for example containing `"` or `<`) is skipped.

The regex is what makes this safe. Path data can't contain markup, so the app can't inject elements or scripts into the publication webview, even when the path comes from server data.

## Alternatives considered

| Option | Why not (yet) |
|---|---|
| **C. Image bytes**<br>(data URI in `<img>`) | Can't be tinted, so it clashes with dark themes.<br>The base64 is repeated in every marker's HTML.<br>Unverified whether ts-toolkit's sanitiser keeps `data:` image sources. |
| **D. App CSS**<br>(style string or map) | Readium CSS theme rules beat normal declarations, so apps would need `!important` everywhere.<br>Web renders in a shadow root.<br>If needed, prefer an allowlisted property map over a raw string. |
| **E. Dart-side template API**<br>(raw HTML) | Readium inserts template HTML as markup, so an attribute like `onerror` runs script in the publication webview, which has native bridges on Android.<br>Native renders the HTML as-is but web sanitises it, so results differ per platform.<br>It is the most flexible option and the biggest API to keep stable; revisit only for a need B can't meet. |

`B` (this proposal) covers "our own icon" without those costs.

## Done when

- `MarginMarker.svgPath` exists in Dart, with docs in `docs/api-reference/decorations.md` and a short section in the guide.
- iOS, Android and web validate, render and test it as above.
- A changelog fragment (`.added`) in both packages.
