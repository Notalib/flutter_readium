# Web Error Event Stream

> **✅ Implemented** on `feat/web-feature-parity` (commit `7de08e9e`). `onErrorEvent` on web is a real broadcast stream rather than throwing `UnimplementedError`. Retained for reference.

**Type:** Cross-platform parity
**Platforms affected:** Web
**Estimated effort:** S

## Context

`onErrorEvent` is the plugin's channel for surfacing non-fatal errors from the reader (resource load failures, navigator errors, etc.) to Dart consumers. On iOS, error events are emitted via the `errorStreamHandler` EventChannel and consumers can react — for example by showing a snackbar or retrying a resource. On Android the same channel exists (though it notes it does not currently emit automatically). On web, `onErrorEvent` throws `UnimplementedError`, meaning any consumer that subscribes to this stream will crash at runtime when running on web.

The web plugin already has a `StreamController<ReadiumError>` for timebased state and a reader status controller — the pattern for adding an error stream is already established and straightforward.

## State at planning time

- **iOS**: `errorStreamHandler` sends events via `FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(...)` in multiple places: `timebasedNavigator(_:encounteredError:)`, `navigator(_:didFailToLoadResourceAt:withError:)`, etc.
- **Android**: `ReadiumErrorEventChannel` is registered; the `onErrorEvent` method channel name is `dk.nota.flutter_readium/error`. Note: the API reference doc (`docs/api-reference/streams-events.md`) warns that Android does not currently emit errors automatically.
- **Web** (`flutter_readium_web.dart` lines 324–327): `get onErrorEvent` throws `UnimplementedError`.
- The `FlutterReadiumWebPlugin` already has `StreamController`s for locator and status; the pattern for adding an error stream is identical.

## Landed approach

1. **Dart web plugin** (`flutter_readium_web.dart`):
   - Add `static final StreamController<ReadiumError> _errorEventController = StreamController<ReadiumError>.broadcast();`.
   - Add `static void addErrorEvent(ReadiumError error) { _errorEventController.add(error); }`.
   - Override `get onErrorEvent` to return `_errorEventController.stream`.
2. **JS callbacks** (`readium_webview.dart`): Add a `@JSExport() void onErrorHandler(String jsonString)` method and wire it to a new `onErrorCallback` JS setter in `js_publication_channel.dart`. Register it in `registerJSExports()`.
3. **JS side** (`ReadiumReader.ts`): In `openPublication`'s catch block (and any other error site), call `(window as any).onErrorCallback?.(JSON.stringify({ message, code }))` so JS-side errors propagate to Dart.

The `ReadiumError` model in `flutter_readium_platform_interface/lib/src/exceptions/readium_exceptions.dart` already has a `fromJson` constructor that covers the `message` / `code` fields sent by iOS/Android.

## Scope boundaries

- First iteration: wire the stream so it is subscribable without crashing, and forward errors from the JS `openPublication` failure path.
- Detailed error categorisation (DRM, network, format errors) is a follow-up shared across all platforms.
- The existing Android caveat ("does not emit automatically") is a separate issue and not part of this plan.

## Risks / open questions

1. **JS error shape**: Confirm `ReadiumError.fromJson` can round-trip the minimal `{ message, code }` payload that JS will send. The iOS payload also includes `data`; the web version may omit it initially.
2. **Multiple error sites**: The ts-toolkit's frame managers and navigator internals surface errors via thrown exceptions rather than callbacks. Catching all of them comprehensively may require wrapping more try/catch blocks in `ReadiumReader.ts`.

## Verification

1. Run `bin/analyze` and `bin/format` from the repo root.
2. On web, subscribe to `FlutterReadium().onErrorEvent` before opening a publication; confirm no `UnimplementedError` is thrown.
3. Open a publication with a deliberately broken resource URL; confirm an error event is emitted and received in the Dart subscription.
4. Confirm the stream does not close after emitting one error (it should be a broadcast stream).
