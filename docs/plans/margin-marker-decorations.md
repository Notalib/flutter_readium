# Margin Marker Decorations

**Type:** Feature
**Platforms affected:** iOS, Android, Web
**Estimated effort:** M

## Context

Two client needs come down to the same thing, a small marker in the page margin, lined up with a text location:

- **Page numbers.** Print-equivalent EPUBs carry a `pageList` nav (see the [DAISY KB page on page lists](http://kb.daisy.org/publishing/docs/navigation/pagelist.html)). Readers want the printed page numbers shown in the margin so they can cite or follow along with a paper copy.
- **Bookmarked highlights.** A client mock-up shows a highlighted passage with a bookmark icon in the margin next to its first line.

Both upstream toolkits do page numbers in their test apps with a custom decoration style backed by an `HTMLDecorationTemplate` (`layout: bounds`, `width: page`, and a small element floated into the page margin):

- swift-toolkit: `TestApp/Sources/Reader/Common/VisualReaderViewController.swift`, section "Page list decorations".
- kotlin-toolkit: `test-app/src/main/java/org/readium/r2/testapp/reader/EpubReaderFragment.kt` (`DecorationStylePageNumber`, `pageNumberTemplate()`).
- kotlin-toolkit `demos/navigator/.../decorations/CustomDecorationStyles.kt` shows `data-activable="1"`, which limits a template's tap area to the marked child element.

As of swift-toolkit 3.11.1 / 4.0.0-alpha.3 and kotlin-toolkit 3.4.0 this is still the recommended approach; neither toolkit has a first-class margin-marker feature. ts-toolkit's Decorator also accepts `HTMLDecorationTemplate` styles (`type: "template"`). Its sanitiser allows SVG "for icon-style decorations (e.g. sidemarks)". The versions already pinned in `flutter_readium/package.json` (`@readium/navigator` 2.13.2, injectables 2.9.1) include all of this.

## Why a built-in style, not docs-only recipes

Client apps cannot add decoration templates themselves. Templates are registered in native code when the navigator is created, and the Dart API has no hook for them and no way to run JavaScript in the webview. A recipe would have to tell clients to patch the plugin's Swift, Kotlin and TypeScript.

The plugin therefore ships **one generic margin-marker style** that shows either a text label or a built-in icon. The docs then give **recipes** that use it: page numbers and bookmarked highlights. If clients later need markers this style can't express, a Dart-side template API can be added on top of the same native code.

## Current state

- **Dart** (`flutter_readium_platform_interface/lib/src/reader/reader_decoration.dart`): `DecorationStyle` is `highlight | underline | spotlight`, and the hand-written `DecorationStyle.fromString` falls back to `highlight` for unknown values. `ReaderDecorationStyle` has `style`, optional `tint` and `isActive`. On the wire, `style` is sent as `style.name`.
- **iOS**: the template map is built in `reader/EPUBReaderView.swift` (around line 171, `decorationTemplates[Decoration.Style.Id("spotlight")] = …`). `spotlightDecorationTemplate()` and `escapeHtmlAttr` are in `reader/EPUBReaderView+Decorations.swift`; the spotlight template force-casts its config (`as!`). In `utils/ReadiumExtensions.swift`, `Decoration.Style.init(withStyle:tintColor:isActive:)` turns any style string into a `Style.Id`, but always with a `HighlightConfig`, which has nowhere to put marker data.
- **Android**: `decorationTemplates` is set in `fragments/EpubReaderFragment.kt` (around line 832, `templates[SpotlightStyle::class] = …`). `SpotlightStyle.kt` is the model for a custom `@Parcelize` style. `decorationStyleFromMap` in `ReadiumExtensions.kt` takes a `Map` and is shared by two paths: `applyDecorations` (`ReadiumReaderWidget.kt:535`) goes through `decorationFromJson`, which holds an `org.json.JSONObject` and copies only `style`/`tint`/`isActive` into a new map; the TTS `setDecorationStyle` path passes method-channel Maps directly. `decorationFromJson` also calls `styleJson.getString("tint")`, which **throws when `tint` is absent**, even though `tint` has been optional in the Dart model since the spotlight change.
- **Web** (`web/src/decorations/DecorationController.ts`): `applyDecorations` maps each raw style to a built-in `Highlight`/`Underline` style, and routes spotlight into a subgroup.
- **Example app**: `pageList.page.dart` lists `pageListOrGenerated` for navigation. User highlights are created through the `highlight` selection action and rendered as a decoration group. The `example.*` debug extensions (`docs/agent-testing.md`) can create and inspect them.

## API

```dart
enum DecorationStyle { highlight, underline, spotlight, marginMarker; … }

enum MarginMarkerIcon { bookmark }
enum MarginSide { start, end }

class MarginMarker implements JSONable {
  const MarginMarker.label(String this.label, {this.side = MarginSide.start}) : icon = null;
  const MarginMarker.icon(MarginMarkerIcon this.icon, {this.side = MarginSide.start}) : label = null;
  final String? label;
  final MarginMarkerIcon? icon;
  final MarginSide side;
  // toJson: {'label'?: …, 'icon'?: icon.name, 'side': side.name}
}

class ReaderDecorationStyle {
  const ReaderDecorationStyle({required this.style, this.tint, this.isActive = false, this.marker});
  /// Required when [style] is [DecorationStyle.marginMarker]; ignored otherwise.
  final MarginMarker? marker;
  // toJson adds: if (marker != null) 'marker': marker!.toJson()
}
```

Design decisions:

1. **Wire value `"marginMarker"`.** Dart sends `style.name`, so every platform matches on `"marginMarker"`.
2. **Marker data is one nested `marker` object**, not separate `label`/`icon`/`side` fields on `ReaderDecorationStyle`. The other styles keep a clean shape, and the two named constructors make "label xor icon" impossible to get wrong. This is non-breaking: the field is optional, like `tint` and `isActive`. As a plugin-owned flat structure it travels as a map, per `docs/architecture.md#bridge-serialization`.
3. **Icons are a closed enum** rendered as built-in inline SVG (`fill="currentColor"`). Dart never supplies markup. Web sanitises template HTML, but native doesn't, so accepting app markup would open an injection path. Add icons to the enum when a client needs one.
4. **`tint` colours the marker** (text, border and icon fill through `color`). Without a tint, `color` is omitted and the marker uses the text colour. `isActive` is ignored.
5. **`side` is logical.** `start` is the left margin in LTR and the right margin in RTL; `end` is the opposite. Declare `float: left|right` first and `float: inline-start|inline-end` second, so webviews without logical float values keep the physical one. The recipes put page numbers at `end` and bookmarks at `start`, as in the mock-up, so both fit on one line in single-column layouts. In two-column layouts the `end` margin of the left page and the `start` margin of the right page are the same gap, so markers there can overlap; document this rather than compensating for it.
6. **No special tap handling.** The marker span carries `data-activable="1"`, which limits the template's tap area to the span in the margin on all three platforms (swift and kotlin `decorator.js`, and ts-toolkit's `Decorator.handleActivation`). Without it the tap area would be the page-width row over the line's text, and kotlin-toolkit hit-tests every group and takes the first match, so the marker could steal taps meant for the highlight. With it, text taps reach the highlight. A tap on the marker itself reports a normal `onDecorationInteraction` for the marker's group; apps ignore groups they don't handle. Markers live in the app's own groups (`page-list`, `highlight-markers`), never in a plugin subgroup.
7. **Styles are inline in the template element**, not in `FlutterReadiumTools.scss`. ts-toolkit renders decorations inside a shadow root, where document stylesheets don't apply, and on native, Readium CSS theme rules (`:root[style*="--USER__backgroundColor"] *` with `background-color: transparent !important`, and `color: inherit !important` under a text colour) beat any class rule. Inline `!important` declarations win on all three platforms (see `docs/troubleshooting.md#decorations-render-invisibly-fills-must-be-important`).
8. **Template element** (identical markup on all platforms):
   ```html
   <div><span data-activable="1" style="{inline styles}">{escaped label | built-in SVG}</span></div>
   ```
   Inline styles on the span, each with `!important`: the two `float` declarations from decision 5, a small margin and padding, `font-size: 0.75em`, `line-height: 1.4`, `border: 1px solid currentColor`, `border-radius: 3px`, `background-color: var(--USER__backgroundColor, var(--RS__backgroundColor))`, `opacity: 0.85`, and `color: {tint}` when a tint is set. `--RS__backgroundColor` alone is always white, so it is only the fallback. The SVG carries `width="1em" height="1em"`. Use `layout: bounds` and `width: page`, so the row's top lines up with the first line of the range and spans the page, and the span floats into the margin.
9. **A `marginMarker` without a `marker` is skipped and logged on every platform**, never rendered empty and never a crash. Dart also asserts in debug in `applyDecorations`, but release builds and `setDecorationStyle` (TTS) reach native unchecked.
10. **The page-number mapping lives in the example app only**, as in the upstream test apps (`pageList` → `locatorFromLink` → `ReaderDecoration`). Use `pageList`, not `pageListOrGenerated`: the generated entries are PDF links, and PDF navigators don't support decorations. If it proves useful for a client, promote it to a `Publication` extension later.

## Implementation steps

### 1. Dart

`reader_decoration.dart`: add `marginMarker` (including a case in `DecorationStyle.fromString`, which otherwise maps it back to `highlight`), `MarginMarker`, `MarginMarkerIcon` and `MarginSide`, and add `marker` to `ReaderDecorationStyle` (constructor, `toJson`, `fromJson`, `copyWith` with the shared `unset` sentinel). In `applyDecorations`, assert in debug that `marginMarker` decorations have a `marker`. Export the new types. Add a `toJson`/`fromJson` round-trip test for a marker decoration.

### 2. iOS

- `EPUBReaderView+Decorations.swift`:
  - Add `Decoration.Style.Id.marginMarker = "marginMarker"`.
  - Add `struct MarginMarkerConfig: Hashable, Sendable { label: String?; icon: String?; side: String; tint: UIColor? }`.
  - Add `static func marginMarkerDecorationTemplate()`, which builds the element from the config, escapes the label with `escapeHtmlAttr`, and maps the icon name to the built-in SVG. Read the config with `as?` and return an empty element on a mismatch; never copy the spotlight template's `as!`.
- `ReadiumExtensions.swift`: in `Decoration.Style.init(fromMap:)`, when `styleStr == "marginMarker"`, read `map["marker"]` and build `Decoration.Style(id: .marginMarker, config: MarginMarkerConfig(…))`. If `marker` is missing or has neither label nor icon, log and return `nil` so the decoration is skipped.
- `EPUBReaderView.swift`: register the template next to spotlight.

### 3. Android

- New `MarginMarkerStyle.kt`, modelled on `SpotlightStyle.kt`: `@Parcelize data class MarginMarkerStyle(val label: String?, val icon: String?, val side: String, @ColorInt override val tint: Int) : Decoration.Style, Decoration.Style.Tinted`. `@Parcelize` is required because `Decoration.Style` is `Parcelable`.
- `ReadiumExtensions.kt`:
  - `decorationFromJson`: read `tint` with `optString`/`isNull` (this fixes the existing crash), and add `"marker"` to the map it builds, converted from `JSONObject` to `Map` (`m.keys().asSequence().associateWith { m.get(it) }`; Android's org.json has no `toMap()`). `decorationStyleFromMap` then sees the same Map shape on both the `applyDecorations` and the TTS path.
  - `decorationStyleFromMap`: add a `"marginMarker"` branch. If `marker` is missing or has neither label nor icon, log and return `null` so the decoration is skipped.
- `EpubReaderFragment.kt`: add `marginMarkerDecorationTemplate()` and register it with `templates[MarginMarkerStyle::class] = …`. Move `escAttr()` out of the spotlight template so both templates can use it.
- Run the Android gates in `flutter_readium/android/AGENTS.md`.

### 4. Web

- `DecorationController.ts`: type the raw style with optional `tint` and `marker`. For `marginMarker` decorations, push `{ type: DecorationStyleType.Template, layout: DecorationLayout.Bounds, width: DecorationWidth.Page, element: () => html }` in the decoration's own group, using the same markup and SVG as native. Skip and log a `marginMarker` without a `marker`.
- Put the marker payload and tint in the decoration's `extras`. ts-toolkit's `stylesEqual` ignores a Template's `element`, so without this a changed label, icon, side or tint under the same decoration id is never re-rendered; `decorationsEqual` does compare `extras`.
- Check against the pinned `@readium/navigator` 2.13.2 typings that `element` is a function at the navigator level (it is a string in injectables) and that `extras` is available.
- Add cases to `web/src/__tests__/DecorationController.test.ts`, including a re-apply with a changed tint. Run the web gates in `flutter_readium/web/AGENTS.md`, including `bin/update_web_example`.

### 5. Example app (the two recipes)

- **Page numbers:** in the reader page, add a "Page numbers in margin" toggle with `ValueKey('page_numbers_toggle')`, shown only when `pub.pageList.isNotEmpty`. When on, apply group `page-list` with `MarginMarker.label(link.title!, side: MarginSide.end)` per entry, skipping entries with a null title or locator. When off, apply an empty list.
- **Bookmarked highlights:** wherever the example applies its highlights group, also apply a `highlight-markers` group with one `MarginMarker.icon(MarginMarkerIcon.bookmark)` per highlight, on the same locator, tinted the highlight's colour (or a fixed green, as in the mock-up). Taps on the text keep going to the highlight decoration itself.

### 6. Docs and changelog

- New guide `docs/guides/margin-markers.md`, with both recipes as copy-paste snippets and notes on `side`, `tint`, margin width, two-column overlap, and the fact that markers are meant to be paired with a text decoration for taps. Link it from `docs/api-reference/decorations.md` and `docs/guides/highlights-annotations.md`.
- `docs/api-reference/decorations.md`: add `marginMarker` and `MarginMarker`. The tables there are otherwise stale (`spotlight`, `isActive` and optional `tint` are missing); that is a separate docs fix, not part of this change.
- Changelog fragments per `CONTRIBUTING.md#changelog`: `+margin-marker-decorations.added.md`, and `+android-decoration-without-tint.fixed.md` for the crash. Validate with `bin/changelog check`. The example-app changes get no fragment.
- When done, move this plan to `docs/plans/` with an `> **✅ Implemented**` note and update `docs/plans/README.md`.

### 7. Validation

- `bin/format` and `bin/analyze`, plus the iOS, Android and web gates from their `AGENTS.md` files. `bin/check_channel_parity` should be unaffected, because no channel method is added.
- Smoke test on the iOS simulator, an Android device and web (`docs/agent-testing.md`):
  - Turn on page numbers and take screenshots in paginated and scroll mode, with a dark custom theme (marker background and tint must survive it), and in an RTL publication if one is available.
  - Create a highlight with `example.selectionAction` and confirm the bookmark icon appears next to its first line. Tap the highlighted text on the simulator or device and confirm `onDecorationInteraction` reports the highlight, not the marker.
- Fixtures come from `bin/fetch_test_resources`. Check whether a fixture EPUB has a `pageList`. If none does, add one to `Notalib/readium-test-resources` and to the `trim` list in `bin/build_test_fixtures`.

## Risks / open questions

- **Empty page-break anchors.** Page-list targets are often empty elements (`<span epub:type="pagebreak" id="p12"/>`). The upstream test apps use the same anchors, but check that the marker's vertical position matches on all three platforms.
- **Unescaped page-break selectors.** `locatorFromLink` (`publication.dart`) builds `cssSelector: '#<fragment>'` without CSS escaping. An id that starts with a digit (`12`) makes `querySelector` throw before the fragment fallback runs, and that page number silently disappears. Fix `locatorFromLink` in its own PR if a real publication hits this.
- **Margin width.** Markers sit in the page margin. Icons need a little more room than page numbers, and with small `pageMargins` they may overlap the text. Document this rather than compensating for it.
- **Fixed-layout two-page spreads (iOS).** Decorations are duplicated on both pages until swift-toolkit 4.0 (readium/swift-toolkit#632). This is cosmetic, and margin markers are rare in fixed layout.
- **Volume.** A long book has hundreds of page-list entries in one `applyDecorations` call. The natives render only loaded resources, but check that opening a chapter doesn't get noticeably slower.
- **Overlap with [highlight-modes.md](highlight-modes.md).** Its open `ruler` style also adds a `DecorationStyle` value and a native template next to spotlight. Whichever lands second rebases onto the other; the two don't conflict in design.

## Out of scope

- A Dart-side API for app-defined templates (the possible follow-up described above).
- Suppressing marker taps. Markers are additive; an app that doesn't want marker events ignores their group.
- Vertical writing modes.
- PDF (PDF navigators don't support decorations, and PDFs show their own page numbers).
