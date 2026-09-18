# flutter_readium — Web (TypeScript)

TS implementation bundled to JS and loaded in a webview. Wraps the npm ts-toolkit packages `@readium/{shared,navigator,navigator-html-injectables}` (versions in `../package.json`). Repo-wide instructions: `../../CLAUDE.md`.

- **Before declaring any web TS changes done:** run `bin/typecheck`, then `bin/update_web_example`. Never hand-edit built JS — bundles are generated and gitignored.
- **Locator serialization**: call `locator.serialize()` before `JSON.stringify` — a plain stringify silently drops `otherLocations` Map entries. Wider rules: `docs/architecture.md#bridge-serialization`.
- Web example for manual checks: `bin/run_web_example [port]`. The Flutter shell is a `<canvas>` (use screenshots), but EPUB content is real HTML in an iframe, so DOM inspection and JS eval work there.
- **TTS needs a real browser.** The in-app preview browser accepts `speechSynthesis.speak()` but never dispatches `onstart` — `speaking` just stays `true` forever, which looks exactly like the stall the watchdog hunts for. Drive TTS checks through Claude in Chrome (or a browser you open yourself) instead; there, utterances start in 1-500 ms and `window.speechSynthesis` exposes the real voice list, network voices included.

## Toolchain

Rollup 4 (`../rollup.config.mjs`, driven by `bin/build_js`), TypeScript 6.
