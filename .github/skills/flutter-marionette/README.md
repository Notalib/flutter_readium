# Flutter MCP Servers — Developer Setup

Two MCP servers complement each other for Flutter development in this project:

| Server | Purpose |
|--------|---------|
| **Dart & Flutter MCP** (`dart mcp-server`) | Code analysis, pub.dev search, dependency management, formatting, tests |
| **Marionette MCP** (`marionette mcp`) | Runtime interaction: screenshots, logs, tap, scroll, enter text |

Both are pre-configured for VS Code (Copilot) and Claude Code — see below.

---

## 1. Dart & Flutter MCP server

### VS Code / Copilot
Enable in your workspace settings (`.vscode/settings.json` — already set in this repo):
```json
"dart.mcpServer": true
```
The Dart VS Code extension registers the server automatically. No further setup needed.

### Claude Code
Run once to register for this project:
```sh
claude mcp add --transport stdio dart -- dart mcp-server
```

---

## 2. Marionette MCP server

Marionette lets the AI agent interact with a **running** Flutter app in debug mode.

### 2a. Install `marionette_mcp` (dev dependency)

`marionette_mcp` is already added as a dev dependency of the example app
(`flutter_readium/example/pubspec.yaml`). The MCP configs run it via
`dart run marionette_mcp` from that directory — no global install needed.

If you're adding Marionette to a different app, run:

```sh
flutter pub add dev:marionette_mcp
```

### 2b. Instrument your Flutter app

Add the Flutter-side package to the app you want to control:

```sh
flutter pub add marionette_flutter
```

Then initialize the binding in `main.dart` (**debug mode only**):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

> ⚠️ `MarionetteBinding` must be the **only** binding initialized.  
> If your tests call `main()` and `kDebugMode` is `true`, guard with:
> ```dart
> import 'dart:io' show Platform;
> final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
> if (kDebugMode && !isFlutterTest) {
>   MarionetteBinding.ensureInitialized();
> } else {
>   WidgetsFlutterBinding.ensureInitialized();
> }
> ```

### 2c. MCP configuration

The Marionette MCP server (`marionette mcp`) is pre-configured in this repo:

- **VS Code / Copilot** — `.vscode/mcp.json`
- **Claude Code** — `.mcp.json` (project root)

No manual configuration needed if you installed the global `marionette` CLI above.

### 2d. Run the example app and connect

```sh
cd flutter_readium/example && flutter run
# Note the VM service URI in the console, e.g.:
# ws://127.0.0.1:54321/ws
```

The MCP server will discover registered instances automatically. You can also
register one manually:

```sh
marionette register example ws://127.0.0.1:54321/ws
marionette doctor   # verify connectivity
```

---

## Optional: Log collection

To expose app logs via `get_logs`, add a log collector. Using the `logging` package:

```sh
flutter pub add marionette_logging
```

```dart
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(logCollector: LoggingLogCollector()),
);
```

See the [marionette_mcp pub.dev page](https://pub.dev/packages/marionette_mcp#installation-2)
for `logger` and custom `PrintLogCollector` options.
