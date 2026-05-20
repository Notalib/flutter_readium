---
name: flutter-marionette
description: 'Inspect a running Flutter app via the Marionette CLI. Use when debugging UI, capturing screenshots, reading logs, tapping elements, or verifying behavior of the example app. Triggers: screenshot, take screenshot, get logs, marionette, inspect app, flutter app, running app, debug app.'
---

# Flutter Marionette

Interact with a running Flutter app in debug mode using the `marionette` CLI.

## When to Use

- Capture a screenshot to verify UI state
- Read application logs to diagnose runtime behavior
- Tap, scroll, or enter text to exercise the app
- Verify example app behavior after a code change

## Setup

> First time? Follow the [full setup guide](./README.md) to instrument your app
> and install the MCP server. Both are pre-configured for VS Code and Claude Code.

The app must be running in debug mode. Find the VM service URI printed in the
console (e.g. `ws://127.0.0.1:XXXXX/ws`).

**Option A — Named instance (reuse across commands):**
```sh
marionette register my-app ws://127.0.0.1:XXXXX/ws
marionette -i my-app <command>
marionette unregister my-app   # cleanup when done
```

**Option B — Direct URI (one-off):**
```sh
marionette --uri ws://127.0.0.1:XXXXX/ws <command>
```

Check registered instances and connectivity:
```sh
marionette list
marionette doctor
```

## Taking Screenshots

```sh
marionette -i my-app take-screenshots --output ./screenshot.png
# or direct URI:
marionette --uri <ws-uri> take-screenshots --output ./screenshot.png
```

Multi-window apps produce numbered files: `screenshot.png`, `screenshot_1.png`, …

## Getting Logs

```sh
marionette -i my-app get-logs
```

## Interacting with the UI

```sh
# Discover what's on screen
marionette -i my-app get-interactive-elements

# Tap by key (most reliable), text, or coordinates
marionette -i my-app tap --key submit_button
marionette -i my-app tap --text "Open Book"
marionette -i my-app tap --x 100 --y 200

# Enter text
marionette -i my-app enter-text --key email_field --input "user@example.com"

# Scroll to element
marionette -i my-app scroll-to --text "Bottom Item"

# Back button
marionette -i my-app press-back-button
```

## Hot Reload

```sh
marionette -i my-app hot-reload
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Runtime error (connection failed, command failed) |
| 64 | Usage error (missing/invalid arguments) |

## Tips

- Prefer `--key` over `--text` for element matching — keys are stable, text can change.
- Run `get-interactive-elements` first to discover available targets.
- Use `--uri` for one-off commands; use `--instance` for repeated interactions.
- If a command fails with a connection error, run `marionette doctor` to check all instances.
