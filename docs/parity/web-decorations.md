# Web Decorations

> **✅ Implemented** on `feat/web-feature-parity`. `applyDecorations` renders highlights/underlines on web and `onDecorationInteraction` fires on tap. Retained for reference.

**Type:** Cross-platform parity
**Platforms affected:** Web
**Estimated effort:** M

## Context

`applyDecorations` is the primary way consumers persist user highlights and annotations across a session. On iOS and Android, calling `applyDecorations(id, decorations)` renders coloured highlight / underline overlays on the text and fires `onDecorationInteraction` when the user taps one. On Web, the method is a no-op — decorations are silently dropped. A consumer writing a cross-platform app cannot restore saved highlights on the web reader without this, which is a user-visible regression whenever the web target is used.

The ts-toolkit EpubNavigator internally uses a `decorate` message via its frame-comms protocol (visible in `flutter_readium/web/src/helpers.ts` at `highlightSelection()`) — so the underlying machinery exists in the npm package; it just isn't wired to the Dart `applyDecorations` call.

## Current state

- **iOS / Android**: Fully implemented. Decorations are serialised as JSON strings per the project convention and applied via the Readium navigator's `apply(decorations:in:)` / `applyDecorations()` APIs.
- **Web** (`flutter_readium/lib/src/flutter_readium_web.dart` line 243): `applyDecorations` logs a debug message and returns without doing anything. `reader_widget_web.dart` line 107 has the same silent no-op.
- The `JsPublicationChannel` / `js_publication_channel.dart` has no JS interop bindings for decorations or decoration interactions; `ReadiumReader` in `ReadiumReader.ts` has no `applyDecorations` method.
- The `onDecorationInteractionCallback` JS setter already exists in `js_publication_channel.dart` (line 37) and `readium_webview.dart` (line 88), meaning the callback plumbing to Dart is prepared — but nothing on the JS side triggers it.

## Proposed approach

1. **JS side** (`flutter_readium/web/src/ReadiumReader.ts`): Add a public `applyDecorations(groupId: string, decorationsJson: string): void` method that deserialises the array and calls the navigator's frame-comms `decorate` message (following the pattern already used in `helpers.ts`'s `highlightSelection()`). Add a matching method to the `ReadiumReader` JS interop extension type in `js_publication_channel.dart`.
2. **Decoration interactions**: Wire the navigator's `decorationActivated` (or equivalent listener) to call back into Dart via `onDecorationInteractionCallback`. The `onDecorationInteractionCallback` setter and `onDecorationInteractionHandler` are already plumbed in `readium_webview.dart`.
3. **Dart web plugin** (`flutter_readium_web.dart`): Replace the no-op with a real call to the new `JsPublicationChannel.applyDecorations(id, encodedList)`.
4. **Widget** (`reader_widget_web.dart`): Replace the no-op similarly.

Follow the JSON-string convention: each `ReaderDecoration` is `json.encode(d.toJson())`, consistent with how iOS/Android pass decorations over the channel (see `reader_channel.dart` line 83–87).

After any TS change, run `bin/update_web_example` to rebuild and deploy.

## Scope boundaries

- First iteration: highlight and underline styles only — these are the only two styles the ts-toolkit natively defines and the only two the Dart model (`DecorationStyle`) currently supports.
- Decoration persistence across resource reload (re-applying decorations when the navigator moves to a new chapter) is a follow-up; native iOS/Android handles this automatically at the Readium level, but on web it may require the Dart side to re-submit on navigation events.
- Custom decoration styles (beyond highlight/underline) are out of scope.

## Risks / open questions

1. **Frame-comms API stability**: The `_cframes[0]?.msg.send("decorate", …)` pattern used in `helpers.ts` is an internal ts-toolkit detail, not a formally documented public API. It may change between minor versions of `@readium/navigator`. Consider filing for a stable public `applyDecorations` surface in the upstream ts-toolkit issue tracker.
2. **Multi-resource reload**: The ts-toolkit navigator may clear decorations when it loads a new resource (chapter). If so, the Dart side needs to re-apply after each `positionChanged` event for a different `href`.
3. **`isActive` flag**: The upstream ts-toolkit `Decoration.Style` supports an `isActive` boolean that changes the visual appearance. This is not yet in the Dart `ReaderDecorationStyle` model (also a gap in [decoration-active-flag.md](decoration-active-flag.md)).

## Verification

1. Run `bin/update_web_example` after TS changes.
2. Run `bin/analyze` and `bin/format` from the repo root.
3. Launch the example app on web (`flutter run -d chrome` from `flutter_readium/example/`) and:
   - Open an EPUB.
   - Call `applyDecorations('test', [ReaderDecoration(...)])` from the app.
   - Confirm highlights render on the correct text.
   - Tap a rendered highlight and confirm `onDecorationInteraction` fires with the correct `decorationId`.
   - Navigate to a new chapter and confirm decorations survive (or document the limitation if they do not).
4. Run `bin/analyze` and `bin/format` once more.
