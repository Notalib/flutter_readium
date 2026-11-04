# Agent testing (marionette / web preview)

Operational guide for AI agents (and humans driving the same tooling) exercising the **example app** — the canonical end-to-end smoke test. All UI / behavior changes should be verified here before a task is declared done. If a change can't be exercised in the example app (native-only, behind a flag, platform edge case), say so explicitly rather than claiming verification.

## Integration-test timing and waits

Run the single `integration_test/plugin_integration_test.dart` entrypoint to avoid rebuilding the app for each group. Compare execution time separately from build time; one warm local run does not establish safe CI deadlines.

The harness prints `integration phase` timings for audio enable/play/state/pause and TTS publication opening, and `integration wait` timings for successful reader waits. These diagnostics remain visible with `READIUM_TEST_SKIP_LOGS=true`. Audio method phases have separate 60-second deadlines; the state-event budget starts after enable/play complete.

Prefer waiting for the exact resource, page, or selector under test to adding a quiet-period delay. Keep stabilization where late initial restoration or preference-driven relayout can overwrite the result. Keep the 120-second reader-mount budget: CI has seen fresh WebContent launches take 59–83 seconds after warm-up.

Use `expectConditionHolds` for negative assertions: it observes the full watchdog window on success but fails promptly on a recorded violation. Do not shorten these windows or speed up watchdog tests' playback; they verify real elapsed-time behavior. The newspaper cue-transition test seeks within the preceding cue, confirms its position, then crosses the boundary through normal playback.

## Launching the app (marionette)

Run `bin/install` after checkout or dependency changes, then `bin/doctor` before native testing.
Android and iOS example builds reject missing or empty generated reader helpers;
the native integration suite also checks the packaged Flutter assets before opening a publication.
If either check fails, run `bin/install` and rebuild the app. Web uses a separate navigator bundle.

Run `flutter run` with `run_in_background: true` — the command never terminates while the app is running, so a foreground call will always hit the timeout. Poll the background task output for the Dart VM Service URI, extract it, then register marionette:

```bash
# Poll for the VM service URI
for i in $(seq 1 30); do
  grep -m1 "Dart VM Service" <output_file> 2>/dev/null && break
  sleep 1
done
# Then: marionette register <name> <uri>/ws
```

## Interacting via marionette

- When adding interactive UI elements that should be exercisable via marionette, add a `ValueKey<String>` to the widget (especially `TextField`s inside `Autocomplete`). This makes `marionette tap --key` and `marionette enter-text --key` reliable.
- Prefer `tap --key` or `tap --text` over coordinate-based taps (`tap --x --y`). Coordinate taps are fragile — elements can overlap or shift between devices, leading to flaky tests that hit the wrong target.
- Bookshelf cards are keyed `book_card_<sanitizeForKey(title)>`, e.g. `book_card_The_Tale_of_Peter_Rabbit`. Tap by key directly; `get_interactive_elements` dumps full text styles (~8k tokens for the bookshelf).
- Simulator screenshots: pass `scale: 0.4` for state checks. Full size only to read small text.

## Choosing a control

The reader is a native view. Marionette sees only the Flutter widgets around it.

| Need | Tool |
|---|---|
| Flutter widgets (AppBar, pages, sheets) | marionette `tap --key` |
| Reader steps: select text, run a selection action, tap a decoration, go to text | `example.*` extensions below |
| App state: open publication, locator, highlights | `example.state` |
| What the reader renders | simulator `screenshot` (`scale: 0.3`) |
| A real tap on reader content | simulator `tap` in device points (screenshot px ÷ 3 on iPhone) |

Drive with the extensions, assert with `example.state`, and confirm visuals with one screenshot.

### `example.*` extensions

Debug builds only, in `example/lib/utils/agent_extensions.dart`. Call them with marionette `call_custom_extension` (omit the `ext.flutter.` prefix). Args are strings; text matches come from `searchInPublication`.

| Extension | Args | Result |
|---|---|---|
| `example.state` | — | `{publication, locator, highlights: [{id, text, tint, totalProgression}]}` |
| `example.selectionAction` | `actionId` (`highlight`\|`note`), `text`, `occurrence`? | `{actionId, locator, highlightId?}` |
| `example.decorationTap` | `id`, `group`? | `{opened}` |
| `example.goToText` | `text`, `occurrence`? | `{locator}` |

These call the app's own handlers, so they skip the plugin's native selection and decoration events. To test those events, use the steps below.

### Native gestures (iOS simulator)

- A simulator `tap` on a decoration fires `onDecorationInteraction`.
- Select a word: `touch_path` holding ~1.6 s (`[{x,y,dt_ms:0},{x,y,dt_ms:800},{x+1,y,dt_ms:800}]`). `tap` with `duration` does not select.
- Each tap on the selection toggles the edit menu.
- Injected taps on edit-menu items have not fired `onSelectionAction`. After one failed try, ask the user to tap the item.

Add an extension when a flow needs a native step the table above lacks.

## PDF / native views don't render in screenshots

Marionette captures the Flutter compositing layer, which cannot reach native platform views (PDFKit/PDFium). To visually verify native view content, use `xcrun simctl io booted screenshot /tmp/screen.png` (captures the full simulator framebuffer). For routine PDF navigation verification, check `marionette get-logs` for the `onPageChanged` locator position.

## Inspecting the web example

`bin/run_web_example [port]` (default 8080) builds the readium JS bundle and serves headlessly via `flutter run -d web-server` (no Chrome spawned). The `Claude_Preview` MCP launches it via the `flutter-web-example` config in `.claude/launch.json`:

- `preview_start` → then `preview_screenshot`, `preview_inspect` (computed CSS by selector — best for verifying colors/spacing), `preview_eval` (JS / DOM / readium bridge), `preview_console_logs`, `preview_network`.
- The `web-server` device compiles on first request (~45s); poll the page before screenshotting since the port opens before the compile finishes.

### Two planes

- The Flutter shell renders to `<canvas>`, so DOM inspect/eval only see `flt-glass-pane` — use **screenshots** for the shell.
- The **EPUB reader content** is real HTML/iframe injected by ts-toolkit (once a book is open), so `preview_inspect` / `preview_eval` hit exactly the layer for decoration-CSS / Highlight-API / locator-bridge debugging.
