---
name: "source-command-flutter-marionette"
description: "Inspect a running Flutter app — take screenshots, read logs, tap elements, hot-reload. Requires the app to be running in debug mode with a VM service URI."
---

# source-command-flutter-marionette

Use this skill when the user asks to run the migrated source command `flutter-marionette`.

## Command Template

Interact with a running Flutter app using the `marionette` CLI.

> First time? See the setup guide in `.github/skills/flutter-marionette/README.md`
> to instrument your app and install the MCP servers.

## Setup

The app must be running in debug mode. The VM service URI is printed in the
console when you run `flutter run` (e.g. `ws://127.0.0.1:XXXXX/ws`).

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

## Common tasks

### Take a screenshot

```sh
marionette -i my-app take-screenshots --output ./screenshot.png
```

Multi-window apps produce numbered files: `screenshot.png`, `screenshot_1.png`, …

### Get logs

```sh
marionette -i my-app get-logs
```

### Discover UI elements

```sh
marionette -i my-app get-interactive-elements
```

### Tap / interact

```sh
marionette -i my-app tap --key submit_button      # by ValueKey (most reliable)
marionette -i my-app tap --text "Open Book"        # by visible text
marionette -i my-app tap --x 100 --y 200           # by coordinates
marionette -i my-app enter-text --key field --input "value"
marionette -i my-app scroll-to --text "Item"
marionette -i my-app press-back-button
```

### Hot reload

```sh
marionette -i my-app hot-reload
```

## Error recovery

If a command fails with a connection error, run `marionette doctor` to check
all instances, then `marionette unregister <name>` to clean up stale entries.
Re-run `flutter run` if needed and register the new URI.
