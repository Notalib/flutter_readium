# Decoration Active Flag

> **✅ Implemented, then extracted.** The `isActive` flag (with the `spotlight`/`ruler` styles) was implemented, then removed from `feat/web-feature-parity` (commit `a01ab8db`) and moved to the stacked PR `feat/decoration-styles`. Not present on this branch; tracked on that PR. Retained for reference.

**Type:** Upstream feature
**Platforms affected:** iOS, Android
**Estimated effort:** S

## Context

Both the swift-toolkit and kotlin-toolkit `Decoration.Style` types support an `isActive: Bool` flag alongside the `tint` colour. When `isActive` is `true`, the navigator renders the decoration in a visually distinct "active" state — for example, a brighter or outlined highlight — to indicate the currently focused annotation (e.g. a search result being navigated to, or a highlight the user has just tapped). Without this flag, all decorations look identical regardless of which one is "current", making it impossible for a consumer to implement standard annotation-browser UX (navigate through results and highlight the active one differently).

The flag exists in both upstream toolkits with identical semantics:
- **swift-toolkit**: `Decoration.Style.highlight(tint: UIColor?, isActive: Bool)` and `Decoration.Style.underline(tint: UIColor?, isActive: Bool)` — confirmed from `DecorableNavigator.swift`.
- **kotlin-toolkit**: `Decoration.Style.Highlight(tint: Int, isActive: Boolean)` and `Decoration.Style.Underline(tint: Int, isActive: Boolean)` — confirmed from `DecorableNavigator.kt`.

## Current state

- **Dart model** (`flutter_readium_platform_interface/lib/src/reader/reader_decoration.dart`): `ReaderDecorationStyle` has only `style: DecorationStyle` and `tint: Color`. No `isActive` field.
- **iOS** (`EPUBReaderView.swift` line 293): `Decoration(id:locator:style:.highlight())` is called with no `isActive` argument (defaults to `false`). The serialisation path in `ReadiumExtensions.swift` (or wherever `Decoration.Style(fromMap:)` is implemented) also has no `isActive` support.
- **Android** (`FlutterDecorationPreferences.kt`, `ReadiumExtensions.kt`): Same — no `isActive` mapping.
- **Web**: Decorations are not yet implemented (see [web-decorations.md](web-decorations.md)).

## Proposed approach

1. **Dart model** (`reader_decoration.dart`): Add `isActive: bool` (defaulting to `false`) to `ReaderDecorationStyle`. Update `toJson()` to include `'isActive': isActive` and `fromJson()` to read it. This is a non-breaking change since the new field has a default value.
2. **iOS** (`ReadiumExtensions.swift` or wherever `Decoration.Style(fromMap:)` is defined): Read `isActive` from the JSON map and pass it to the upstream `Decoration.Style` constructor.
3. **Android** (`ReadiumExtensions.kt` or `FlutterDecorationPreferences.kt`): Same — read `isActive` from the decoration JSON map and forward to the upstream `Decoration.Style.Highlight` / `Decoration.Style.Underline` constructor.
4. No platform-interface or method-channel changes beyond the model update — the decoration JSON already flows as a string through `applyDecorations`.

Key files that change:
- `flutter_readium_platform_interface/lib/src/reader/reader_decoration.dart`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/utils/ReadiumExtensions.swift` (or wherever `Decoration.Style(fromMap:)` is defined)
- `flutter_readium/android/src/main/kotlin/dk/nota/flutter_readium/ReadiumExtensions.kt` (or equivalent)

## Scope boundaries

- This plan does not introduce new decoration styles beyond `highlight` and `underline` — it only adds the `isActive` attribute to the existing ones.
- Custom decoration styles (sidebar markers, line backgrounds, etc.) are out of scope.
- Web is out of scope until [web-decorations.md](web-decorations.md) is implemented, at which point `isActive` should be included in that implementation.

## Risks / open questions

1. **Visual rendering of `isActive`**: On iOS, the "active" visual effect is defined by the upstream `HTMLDecorationTemplate`. Confirm whether the `experimentalPositioning: true` template used in `EPUBReaderView.swift` line 86 respects `isActive`. If not, the flag may be silently ignored by the renderer even after correct serialisation.
2. **Locating the iOS serialisation code**: The `Decoration.Style(fromMap:)` deserialiser was referenced in `FlutterReadiumPlugin.swift` line 255 but the implementation file was not audited. Locate it during implementation to avoid creating a duplicate path.

## Verification

1. Run `bin/analyze` and `bin/format` from the repo root.
2. In the example app on iOS and Android, apply two decorations with the same group — one with `isActive: false`, one with `isActive: true`.
3. Confirm via visual inspection (marionette screenshot on iOS simulator, or `xcrun simctl io booted screenshot`) that the `isActive: true` decoration renders differently (typically brighter or outlined) from the inactive one.
4. Toggle `isActive` by re-applying the decoration list with the flags swapped and confirm the active rendering moves to the other decoration.
