# Troubleshooting

## Android: `MainActivity cannot be cast to FragmentActivity`

The plugin requires `FlutterFragmentActivity`. Change `MainActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

## Android: `minSdkVersion` build failure

Set `minSdkVersion 24` in `android/app/build.gradle`.

## iOS: pod install fails

```bash
cd ios
pod deintegrate
pod update && pod install --repo-update
```

If that doesn't help, delete `Podfile.lock` and retry.

## iOS: `MissingPluginException` on stream subscription

Event channels register lazily inside the native view initialiser. Subscribe to streams inside `onReady` or after the reader widget has mounted, not in `initState` before the view exists.

## Web: reader not showing / JS errors

1. Verify you ran `dart run flutter_readium:copy_js_file <dest_dir>` after installing the package.
2. Check that both `flutter.js` and `readiumReader.js` script tags appear in `index.html`.
3. Check the file path of your `readiumReader.js` and see if it differs from the one in `index.html`.

## TTS not working on Android

TTS requires the Android TTS engine with the correct language data installed. If the device has no TTS engine, `ttsEnable` will throw. Check that Google Text-to-Speech (or another TTS engine) is installed and the required language pack is downloaded via device settings.

## Audio/TTS position drifts on restore

This is expected behavior on Android when the progression delta on restore is very small. The native side skips redundant scrolls when already within 1% of the target position. Use `cssSelector` or `domRange` in your saved locators for the most precise restoration.

## Publication fails to open

```dart
try {
  await reader.openPublication(url);
} on OpeningReadiumException catch (e) {
  print(e.type);    // notFound | formatNotSupported | forbidden | unknown
  print(e.message); // human-readable description
}
```

Common causes:
- File not found or URL typo (`notFound`)
- Unsupported format — only EPUB, WebPub, audiobook, and PDF are supported (`formatNotSupported`)
- DRM-protected content without a licence (`forbidden`)

## Getting debug logs

See the [Logging section of the Error Handling guide](guides/error-handling.md#logging) for the full setup — `setLogLevel`, the Dart-side fimber tree, and native log filtering on Android / iOS.

## Decorations render invisibly (fills must be `!important`)

When a custom theme/background is active (the reader effectively always sets one), Readium CSS injects:

```css
:root[style*="--USER__backgroundColor"] * { background-color: transparent !important }
```

This forces **every** element's background to transparent. Any decoration whose visible effect is its fill (e.g. `highlight`, `ruler`) must declare `background-color: … !important`, or it renders invisibly — this is why the upstream default highlight template uses `!important`.

How each platform satisfies this:

- **iOS / Android** — emit the `!important` directly in the decoration template HTML.
- **Web** — the upstream decorator sets only a *plain* inline `background-color`, so `injectDecorationOverrides` re-asserts it as inline `!important` (inline important beats stylesheet important) via a `MutationObserver`.

Decorations that don't rely on a fill are immune: `spotlight` works via box-shadow (iOS/Android) or body-dimming `color` CSS (Web), and `underline` swaps the fill for a `border-bottom`.

## Integration tests pass locally but fail in CI

A real failure can hide behind confusing output. Work through it in this order — it's how the `EPUBReaderView` asset crash (below) was found.

1. **Don't trust the CI summary — change the reporter.** In CI, `flutter test` auto-selects package:test's GitHub Actions reporter (`GITHUB_ACTIONS=true`), which can render a crash as a misleading tally (e.g. `🎉 2 tests passed` + exit 1 with no failure shown). Force a faithful reporter to see the truth:

   ```bash
   flutter test integration_test --reporter expanded -d <udid>
   ```

   `… did not complete [E]` cascading from one test onward (incl. `(tearDownAll)`) means the app/VM-service connection dropped — i.e. the app **crashed**. It is *not* a slow-timeout hang; those hit the per-test `_waitWithPump` 30s deadline and print a diagnostic message.

2. **Reproduce CI conditions locally.** Match the pinned runtime (`.flutter-version`, and `SIMULATOR_DEVICE` in `.github/workflows/integration-test-ios.yml`) and set `GITHUB_ACTIONS=true`. If it still passes locally, the differentiator is the *runner environment* (cold build, freshly-booted sim, un-generated build artifacts) — not the test logic.

3. **Get the native crash.** On failure the iOS job uploads an `ios-integration-*` artifact (crash `.ips` + `sim.logarchive`). Read the archive with `log`, not `flutter`:

   ```bash
   /usr/bin/log show sim.logarchive --style syslog --info --debug \
     --predicate 'process == "Runner" OR eventMessage CONTAINS[c] "crash" OR eventMessage CONTAINS[c] "WebContent"'
   ```

   The app process is `Runner`; its last lines before it stops logging are the crash (e.g. a Swift `Fatal error: Unexpectedly found nil …` with `file:line`).

## Web: image-tap resources fail to load from cross-origin servers without CORS headers

`getResourceUrl` / `imageProvider(href)` on Web resolve to the publication's served resource
URL and hand it to Flutter's image pipeline (`ui_web.createImageCodecFromUrl`, same mechanism
`Image.network`/`NetworkImage` use). On the CanvasKit renderer this **always** requires
`Access-Control-Allow-Origin` from the resource's server — CanvasKit needs pixel-level access
to build a GPU texture, so its `<img>`-element decode sets `crossOrigin = 'anonymous'`
unconditionally, and its `fetch()` fallback hits the same wall. If the server doesn't send a
CORS header, the browser blocks both, and you'll see console errors like:

```
Access to image at '<url>' from origin '<app origin>' has been blocked by CORS policy: No
'Access-Control-Allow-Origin' header is present on the requested resource.
Access to fetch at '<url>' from origin '<app origin>' has been blocked by CORS policy: ...
```

The image renders as a broken-image icon (`imageProvider`'s `errorBuilder` fires).

**This is a browser/CanvasKit constraint, not something the plugin can opt out of** — any
Flutter Web app using `Image.network`/`NetworkImage` against a CORS-less origin hits the same
error. There is no client-side workaround short of not decoding the image through Flutter's
canvas pipeline at all (e.g. a raw DOM `<img>` via a platform view, which is out of scope here).

- **Fix**: ensure the server hosting EPUB/publication resources sends
  `Access-Control-Allow-Origin` (an allow-list including your app's origin, or `*` for public
  resources).
- **Unaffected**: iOS/Android — `getResourceUrl` there returns a native-cached `file://` URL,
  never subject to browser CORS.
- Public demo servers (e.g. `publication-server.readium.org`) are a common source of this —
  don't mistake it for a regression if a locally-hosted or CORS-enabled resource works fine.

### Case study: the `EPUBReaderView` asset crash (2026-06)

iOS integration tests passed locally but deterministically failed in CI; only the two pre-reader tests passed and the rest `did not complete`. Cause: the WKWebView helper assets `assets/helpers/flutterReadiumTools.{js,css}` are **gitignored build artifacts** (compiled from `assets/_helper_scripts/src` by `npm run build:flutter`, run via `bin/install`). CI never built them, so the app bundle shipped without them and `EPUBReaderView.initUserScripts` force-unwrapped a nil `Bundle.main.path(...)` the instant the first reader view mounted. Fix: build the helpers in the workflow before the app build, and load assets without force-unwrapping so a missing artifact degrades + logs instead of trapping. Every native app-building job (iOS/Android, build + integration) runs the build via the shared `build-webview-helpers` composite action (`.github/actions/build-webview-helpers`). Web does **not** use these assets: its reader loads the `lib/helpers/readiumReader.js` navigator bundle (which `index.html` serves as `/readiumReader.js`), a separate gitignored artifact built by `npm run build:dev`. The web jobs build + copy it via the `build-web-reader-bundle` action (`.github/actions/build-web-reader-bundle`) — without it the reader's custom element never registers in the browser.
