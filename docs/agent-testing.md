# Agent testing (marionette / web preview)

Operational guide for AI agents (and humans driving the same tooling) exercising the **example app** — the canonical end-to-end smoke test. All UI / behavior changes should be verified here before a task is declared done. If a change can't be exercised in the example app (native-only, behind a flag, platform edge case), say so explicitly rather than claiming verification.

## Launching the app (marionette)

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

## PDF / native views don't render in screenshots

Marionette captures the Flutter compositing layer, which cannot reach native platform views (PDFKit/PDFium). To visually verify native view content, use `xcrun simctl io booted screenshot /tmp/screen.png` (captures the full simulator framebuffer). For routine PDF navigation verification, check `marionette get-logs` for the `onPageChanged` locator position.

## Inspecting the web example

`bin/run_web_example [port]` (default 8080) builds the readium JS bundle and serves headlessly via `flutter run -d web-server` (no Chrome spawned). The `Claude_Preview` MCP launches it via the `flutter-web-example` config in `.claude/launch.json`:

- `preview_start` → then `preview_screenshot`, `preview_inspect` (computed CSS by selector — best for verifying colors/spacing), `preview_eval` (JS / DOM / readium bridge), `preview_console_logs`, `preview_network`.
- The `web-server` device compiles on first request (~45s); poll the page before screenshotting since the port opens before the compile finishes.

### Two planes

- The Flutter shell renders to `<canvas>`, so DOM inspect/eval only see `flt-glass-pane` — use **screenshots** for the shell.
- The **EPUB reader content** is real HTML/iframe injected by ts-toolkit (once a book is open), so `preview_inspect` / `preview_eval` hit exactly the layer for decoration-CSS / Highlight-API / locator-bridge debugging.
