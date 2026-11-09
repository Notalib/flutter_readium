# flutter_readium — Web (TypeScript)

TS implementation bundled to JS and loaded in a webview. Wraps the npm ts-toolkit packages `@readium/{shared,navigator,navigator-html-injectables}` (versions in `../package.json`). Repo-wide instructions: `../../AGENTS.md`.

- **Before declaring any web TS changes done:** run `bin/typecheck` (type-check plus ESLint), then `bin/update_web_example`. Never hand-edit built JS — bundles are generated and gitignored.
- **No shadowing globals:** ESLint's `no-shadow` with `builtinGlobals` rejects locals named like browser globals (`document`, `origin`, `status`, …). Terser can mangle such a local and the global to the same name in the production bundle. Rename the local; don't disable the rule.
- **Gate scope:** for TypeScript-only changes, the web checks are sufficient. Run the repo-wide Dart format/analyze gates only when Dart or shared API files also changed.
- **Locator serialization**: call `locator.serialize()` before `JSON.stringify` — a plain stringify silently drops `otherLocations` Map entries. Wider rules: `docs/architecture.md#bridge-serialization`.
- **Web plugin Dart tests** (`flutter_readium_web_test.dart`, `js_publication_channel_test.dart`) are `@TestOn('browser')` and use a fake `ReadiumReader` on `globalThis` (`test/support/fake_readium_reader.dart`). Run them with `fvm flutter test --platform chrome <file>`; plain `flutter test` skips them. The Web CI job runs them.
- Web example for manual checks: `bin/run_web_example [port]`. The Flutter shell is a `<canvas>` (use screenshots), but EPUB content is real HTML in an iframe, so DOM inspection and JS eval work there.
- **TTS needs a real browser.** The in-app preview browser accepts `speechSynthesis.speak()` but never dispatches `onstart` — `speaking` just stays `true` forever, which looks exactly like the stall the watchdog hunts for. Drive TTS checks through Claude in Chrome (or a browser you open yourself) instead; there, utterances start in 1-500 ms and `window.speechSynthesis` exposes the real voice list, network voices included.

## Toolchain

Rollup 4 (`../rollup.config.mjs`, driven by `bin/build_js`), TypeScript 6.
