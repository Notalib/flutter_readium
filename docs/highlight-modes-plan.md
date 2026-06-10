# Highlight Modes — Implementation Plan

Target: four TTS/MediaOverlay decoration styles on iOS, Android, and Web.

## Modes

| Style | Description |
|---|---|
| `highlight` | Opaque filled rectangle placed **behind** text (`experimentalPositioning: true`, alpha 1.0). Default. |
| `underline` | Colored border-bottom under the active text line. No box behind text. |
| `spotlight` | Tinted box behind text **and** all surrounding body text is dimmed, drawing the eye to the active range. |
| `ruler` | Full-viewport-width stripe across the active text line — wide enough to reach page margins, a reading-ruler aid. |

---

## Phase A — Enum + Dart surface + cleanup

### A1. Extend `DecorationStyle` enum
File: `flutter_readium_platform_interface/lib/src/reader/reader_decoration.dart`

Add `spotlight` and `ruler` to the enum. Update `fromString()`:

```dart
enum DecorationStyle {
  highlight,
  underline,
  spotlight,
  ruler;

  static DecorationStyle fromString(String? styleStr) {
    switch (styleStr) {
      case 'underline': return DecorationStyle.underline;
      case 'spotlight': return DecorationStyle.spotlight;
      case 'ruler':     return DecorationStyle.ruler;
      case 'highlight':
      default:          return DecorationStyle.highlight;
    }
  }
}
```

### A2. Remove `setSpotlightGroup` entirely
`setSpotlightGroup(String?)` was an interim API that drives spotlight from the Dart side as an explicit call.  
The new design drives it from decoration presence: when any decoration with `style = spotlight` is live, the
group automatically dims surrounding text. No separate toggle is needed.

Remove from:
- `flutter_readium_platform_interface/lib/flutter_readium_platform_interface.dart`
- `flutter_readium/lib/flutter_readium.dart`
- `flutter_readium/lib/src/flutter_readium_web.dart`
- `flutter_readium/lib/src/js_publication_channel.dart` (extension type + wrapper)
- `flutter_readium/test/flutter_readium_test.dart` (mock stub)

### A3. Update CHANGELOG
Under `## Unreleased` / `### Added`, replace the `setSpotlightGroup` entry with a description of the four-mode enum.

---

## Phase B — Spotlight template

### B-Web
- Route `spotlight`-style decorations to a `<group>__spotlight` upstream subgroup (similar to `__underline`).
- When the first decoration lands in any `__spotlight` group, inject or update an iframe `<style>` that dims
  the document body and restores color for that group's `::highlight()` pseudo-element.
- When the spotlight group is cleared (zero decorations), remove the dim.
- Remove `setSpotlightGroupOnIframes` / `setSpotlightGroup` TS methods from `helpers.ts` and `ReadiumReader.ts`.
- Add a `__spotlight` suffix constant in `helpers.ts`.

Key CSS (injected per iframe):
```css
/* dim everything */
body.__fr-spotlight, body.__fr-spotlight * {
  color: rgba(0,0,0,0.22) !important;
}
/* restore for the active group */
body.__fr-spotlight ::highlight(<internalId>) {
  color: initial !important;
}
```

Limitation: only effective in the CSS Custom Highlight API path (Chrome ≥ 105). DOM-fallback browsers see no
spotlight effect — the `.readium-highlight` box sits behind the dimmed text layer.

### B-iOS
File: `flutter_readium/ios/Classes/Reader/ReaderViewController.swift` (or wherever decoration templates are configured).

Add a custom `HTMLDecorationTemplate` for `spotlight`-style decorations:

```swift
HTMLDecorationTemplate(
    layout: .bounds,
    width: .wrap,
    element: { decoration in
        let tint = decoration.style.tint.cssValue
        // The box sits behind the text (experimentalPositioning: true) and uses a
        // box-shadow to bleed out to the edges of the viewport, dimming everything else.
        return """
        <div style="
          background-color: transparent;
          box-shadow: 0 0 0 9999px rgba(0,0,0,0.55);
          z-index: 10;
          position: relative;
        "></div>
        """
    },
    stylesheet: nil
)
```

Register this template for the custom style ID `"spotlight"`. Both Swift (`Decoration.Style.Id`) and Kotlin
(`Decoration.Style`) support custom IDs without upstream PRs — see upstream `CustomDecorationStyles` demo.

Known limitation (paginated columns): the `box-shadow` approach clips at column boundaries in multi-column
EPUB layouts. Full-page dim would require a sibling element above the column stack, which requires DOM mutation.
Document the limitation; do not work around it.

### B-Android
File: `flutter_readium/android/.../ReadiumFlutterPlugin.kt` (wherever `HtmlDecorationTemplate` is configured).

Equivalent Kotlin using `HtmlDecorationTemplate`:

```kotlin
HtmlDecorationTemplate(
    layout = HtmlDecorationTemplate.Layout.BOUNDS,
    width = HtmlDecorationTemplate.Width.WRAP,
    element = { decoration ->
        val tint = decoration.style.tint
        """<div style="
          background-color: transparent;
          box-shadow: 0 0 0 9999px rgba(0,0,0,0.55);
          z-index: 10;
          position: relative;
        "></div>"""
    }
)
```

Register under style ID `"spotlight"`.

---

## Phase C — Ruler template

The ruler renders a full-viewport-width stripe at the height of each decorated text line, coloured by the tint.
This is a reading-ruler accessibility aid: it marks the active spoken line without obscuring any text.

No new upstream features are needed — `Layout.Boxes + Width.Viewport` is already in the toolkit.

### C-Web
In `ReadiumReader.ts → applyDecorations`, route `ruler`-style decorations to a `<group>__ruler` upstream subgroup.
Send each decoration with:
```ts
style: {
  tint: raw.style.tint,
  layout: Layout.Boxes,   // one element per text bounding box
  width: Width.Viewport,  // stretch to viewport width
}
```

No special CSS injection is needed: the upstream decorator already renders a filled rect behind the text.

Add `RULER_GROUP_SUFFIX = "__ruler"` constant to `helpers.ts`.

### C-iOS
Register a custom `HTMLDecorationTemplate` for style ID `"ruler"`:

```swift
HTMLDecorationTemplate(
    layout: .boxes,
    width: .viewport,
    element: { decoration in
        let tint = decoration.style.tint.cssValue
        return "<div style=\"background-color: \(tint);\"></div>"
    }
)
```

### C-Android
```kotlin
HtmlDecorationTemplate(
    layout = HtmlDecorationTemplate.Layout.BOXES,
    width = HtmlDecorationTemplate.Width.VIEWPORT,
    element = { decoration ->
        val tint = decoration.style.tint
        """<div style="background-color: ${tint.cssValue};"></div>"""
    }
)
```

---

## Phase D — Web TTS wiring (separate branch)

When the web TTS engine arrives, wire it to `applyDecorations` as follows:

1. On each TTS utterance-start event, call:
   ```dart
   flutterReadium.applyDecorations(
     "tts_utterance",
     [ReaderDecoration(id: locator.href, locator: locator, style: utteranceStyle)],
   );
   ```
2. On each range event (word-level), call:
   ```dart
   flutterReadium.applyDecorations(
     "tts_range",
     [ReaderDecoration(id: locator.href, locator: locator, style: rangeStyle)],
   );
   ```
3. On TTS stop/pause, call `applyDecorations("tts_utterance", [])` and `applyDecorations("tts_range", [])` to clear.
4. The stored `_utteranceStyle` / `_rangeStyle` from `setDecorationStyle` in `ReadiumReader.ts` can be consumed here.

No new Dart API is required — the existing `applyDecorations` + `setDecorationStyle` surface is sufficient.
