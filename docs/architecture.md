# Architecture Overview

## Package structure

This is a federated Flutter plugin split into two pub packages:

```
flutter_readium/                  — app-facing package
flutter_readium_platform_interface/ — shared models & platform contract
```

```
Flutter App
    │
    ▼
FlutterReadium (singleton, flutter_readium)
    │
    ▼
FlutterReadiumPlatform (abstract interface)
    │
    ├── MethodChannelFlutterReadium  (default implementation)
    │       │
    │       ├── iOS        — Swift / swift-toolkit (pinned in `flutter_readium/ios/flutter_readium.podspec`)
    │       ├── Android    — Kotlin / kotlin-toolkit (pinned in `flutter_readium/android/build.gradle`)
    │       └── Web        — TypeScript / @readium/navigator
    │
    └── ReadiumReaderWidget  (platform view)
```

## Communication

All Dart↔native communication uses Flutter method channels and event channels defined in `MethodChannelFlutterReadium`:

- **Method channel** (`flutter_readium`) — request/response calls (open, navigate, preferences, …)
- **Event channels** — one-way streams from native to Dart:
  - `flutter_readium/reader_status`
  - `flutter_readium/text_locator`
  - `flutter_readium/timebased_state`
  - `flutter_readium/error_event`

Opening a publication: Dart sends the URL over the method channel → native parses via Readium → returns a JSON Publication manifest → Dart deserialises into a `Publication` object.

Position updates travel the reverse direction via the text locator event channel.

## Models

All models in `flutter_readium_platform_interface` define hand-written `toJson` / `fromJson` methods (via the `JSONable` mixin) for cross-platform serialisation, persistence, and debugging. The package does not use `json_serializable` or `freezed` code generation.

## Singleton pattern

`FlutterReadium` is a singleton — there is one reader active at a time. The global publication lifecycle (open/close) is managed centrally. Do not introduce per-instance state without reviewing the existing lifecycle.

## Web implementation

The web plugin is a TypeScript/webpack bundle (`flutter_readium/web/_scripts/`) compiled to `flutter_readium/lib/helpers/readiumReader.js`. It is loaded inside a webview and communicates with Dart via `postMessage` / JS interop.

After any TypeScript change run `bin/update_web_example` to rebuild and deploy to the example app.

## Native toolkits

| Platform | Toolkit | Version |
|----------|---------|---------|
| iOS | swift-toolkit | 3.9.0 |
| Android | kotlin-toolkit | 3.2.0 |
| Web | `@readium/*` npm packages | see `flutter_readium/package.json` |

macOS is not supported — the plugin registers on macOS as a stub but all calls return `MethodNotImplemented`. swift-toolkit is iOS-only.

When upgrading any toolkit version, verify that all three platforms move together where API surface overlaps.
From repo root, run `bin/readium_versions` to print the current pinned values from the source-of-truth files.
