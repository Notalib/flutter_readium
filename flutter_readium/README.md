# flutter_readium

Build EPUB, PDF, audiobook, comic, and WebPub readers in Flutter with one unified Dart API—powered
by Readium toolkits on iOS, Android, and Web.

[![pub package](https://img.shields.io/pub/v/flutter_readium.svg)](https://pub.dev/packages/flutter_readium)
[![Quality](https://github.com/notalib/flutter_readium/actions/workflows/quality.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/quality.yml)
[![Unit Tests](https://github.com/notalib/flutter_readium/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/test.yml)
[![CI](https://github.com/notalib/flutter_readium/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/ci.yml)

<p align="center">
  <img src="https://raw.githubusercontent.com/Notalib/flutter_readium/main/docs/assets/readme/flutter-readium-demo.gif" width="360" alt="flutter_readium example app changing EPUB reading preferences and demonstrating synchronized read-along highlighting.">
</p>

<p align="center"><em>Captured on iOS; synchronized narration uses the same Dart API on Android and Web.</em></p>

<p align="center">
  <a href="https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md"><strong>Get started</strong></a> ·
  <a href="https://github.com/Notalib/flutter_readium/tree/main/flutter_readium/example"><strong>Example app</strong></a> ·
  <a href="https://pub.dev/documentation/flutter_readium/latest/"><strong>API docs</strong></a>
</p>

| Reading | Listening | Rich formats |
| :---: | :---: | :---: |
| <img src="https://raw.githubusercontent.com/Notalib/flutter_readium/main/docs/assets/readme/capability-reading.png" width="240" alt="EPUB theme and typography controls in flutter_readium."> | <img src="https://raw.githubusercontent.com/Notalib/flutter_readium/main/docs/assets/readme/capability-listening.png" width="240" alt="Synchronized narration highlighting and playback controls in flutter_readium."> | <img src="https://raw.githubusercontent.com/Notalib/flutter_readium/main/docs/assets/readme/capability-rich-formats.png" width="240" alt="PDF and comic navigation in flutter_readium."> |
| EPUB themes, layout, and highlights | Synchronized narration on iOS, Android, and Web | PDF and comic/DiViNa navigation |

## Quick start

Add the package:

```bash
flutter pub add flutter_readium
```

Open a local file or URL, then mount the native reader:

```dart
final readium = FlutterReadium();
final publication = await readium.openPublication(publicationUrl);
final readerWidget = ReadiumReaderWidget(publication: publication);
```

See the [five-minute walkthrough](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md)
for lifecycle, navigation, preferences, and position restoration.

## Features

- EPUB 2 / EPUB 3 reading, with dynamic horizontal pagination and vertical scrolling modes
- PDF reading on iOS (PDFKit) and Android (PDFium), with layout, reading-progression, page-spacing, and fit preferences
- WebPub reading (including audiobook WebPub)
- Pre-recorded audio playback with track navigation and variable speed
- Synchronized Media Overlays in WebPubs (text-and-audio read-along)
- Platform-native text-to-speech with voice selection, speed, and pitch
- Reader preferences (typography, theme, scroll, columns, ...) via the Readium Preferences API
- App-supplied static reader fonts on iOS, Android, and Web
- Highlights and annotations via the Decorator API
- Position persistence and restoration via Locators
- Content search within open publications
- Real-time event streams for position, playback state, reader status, and errors
- Custom HTTP headers for publication and resource fetching

## How it works

flutter_readium is a federated plugin that delegates to the upstream Readium toolkit on each
platform:

- **swift-toolkit 3.11.0** on iOS
- **kotlin-toolkit 3.3.0** on Android
- **ts-toolkit** (`@readium/shared`, `@readium/navigator`) on Web

## Supported formats

| Format    | Visual       | TTS | Audio | Media Overlays         |
| --------- | :----------: | :-: | :---: | :--------------------: |
| EPUB 2    |      ✓       |  ✓  |   —   |           -            |
| EPUB 3    |      ✓       |  ✓  |   ✓   |           -            |
| WebPub    |      ✓       |  ✓  |   ✓   | ✓ (EPUB profile)       |
| Audiobook |      —       |  —  |   ✓   |           -            |
| PDF       |      ✓       |  —  |   —   |           -            |
| CBZ       |      ✓       |  —  |   —   |           -            |
| DiViNa    |      ✓       |  —  |  ✓¹   | ✓¹ (Guided Navigation) |

¹ DiViNa audio narration is driven by a Guided Navigation document and synchronizes at the page
level on all platforms (on Web, ts-toolkit has no DiViNa navigator, so images are rendered by a
plugin-side navigator). Panel-level zoom (the segments' `xywh` regions) is not yet implemented on
any platform.

LCP-protected publications are not currently supported. The underlying toolkits include an LCP adapter; it may be enabled in a future release.

## Platform support

| Feature                  | Android | iOS | Web        |
| ------------------------ | :-----: | :-: | :--------: |
| EPUB visual reading      |    ✓    |  ✓  |     ✓      |
| Comics (CBZ / DiViNa)    |    ✓    |  ✓  |     ✓      |
| PDF reading              |    ✓    |  ✓  |     —      |
| Audiobook playback       |    ✓    |  ✓  |     ✓      |
| Media Overlays           |    ✓    |  ✓  |     ✓      |
| Text-to-Speech           |    ✓    |  ✓  | Limited¹   |
| Highlights / decorations |    ✓    |  ✓  |     ✓      |
| Reader preferences       |    ✓    |  ✓  |     ✓      |
| PDF preferences          |    ✓    |  ✓  |     —      |
| Progress saving          |    ✓    |  ✓  |     ✓      |
| Content search           |    ✓    |  ✓  |     —      |
| Background audio         |    ✓    |  ✓  |     —      |

¹ Web TTS uses the browser's Web Speech API — voice availability and quality vary by browser.

> **macOS note:** Native macOS desktop (`flutter run -d macos`) is not supported — a no-op stub is registered so the Flutter macOS target still compiles, but every reader call returns `MethodNotImplemented`. The upstream `swift-toolkit` is iOS-only and has marked native macOS [`not_planned`](https://github.com/readium/swift-toolkit/issues/783). The iOS build runs fine on Apple Silicon Macs via "Designed for iPad".

## Minimum requirements

| Requirement | Version                |
| ----------- | ---------------------- |
| Flutter     | 3.44.8+                |
| Dart SDK    | 3.8.0+                 |
| Android     | `minSdkVersion` 24     |
| iOS         | 15.0+                  |

## Platform setup

Complete the per-platform setup below before running the reader. See the full
[installation guide](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/installation.md)
for details.

### Android

- Set `minSdkVersion` to 24 or higher in `android/app/build.gradle`.
- Change your `MainActivity` to extend `FlutterFragmentActivity` (not `FlutterActivity`) — otherwise the reader view will crash at runtime.
- If using TTS or background audio, add to `android/app/src/main/AndroidManifest.xml`:

  ```xml
  <uses-permission android:name="android.permission.WAKE_LOCK" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
  ```

### iOS

Add the Readium pods to your `ios/Podfile`. The versions must match the ones pinned in
`ios/flutter_readium.podspec`. The `example/ios/Podfile` is the source-of-truth for app
integration — copy these lines into your own `Podfile`:

```ruby
source 'https://github.com/readium/podspecs'
source 'https://cdn.cocoapods.org/'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  pod 'ReadiumShared', '~> 3.11.0'
  pod 'ReadiumInternal', '~> 3.11.0'
  pod 'ReadiumStreamer', '~> 3.11.0'
  pod 'ReadiumNavigator', '~> 3.11.0'
  pod 'ReadiumOPDS', '~> 3.11.0'
end
```

The `readium/podspecs` source is hosted at https://github.com/readium/podspecs. To use
a specific version, change the `~>` constraint accordingly (e.g. `~> 3.10.0`).

### Web

1. Copy the plugin's JavaScript bundle into your web app:

   ```bash
   dart run flutter_readium:copy_js_file <destination_directory>
   ```

   The destination should live inside your `web/` directory.

2. Reference the script from `web/index.html`:

   ```html
   <script src="flutter.js" defer></script>
   <script src="readiumReader.js" defer></script>
   ```

## Documentation

Full documentation is hosted in the [project repository](https://github.com/notalib/flutter_readium):

- **Getting Started** — [Installation](https://github.com/notalib/flutter_readium/blob/main/docs/getting-started/installation.md) · [Quick Start](https://github.com/notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md) · [Core Concepts](https://github.com/notalib/flutter_readium/blob/main/docs/getting-started/concepts.md)
- **Guides** — [EPUB Reading](https://github.com/notalib/flutter_readium/blob/main/docs/guides/epub-reading.md) · [Audiobook Playback](https://github.com/notalib/flutter_readium/blob/main/docs/guides/audiobook-playback.md) · [Text-to-Speech](https://github.com/notalib/flutter_readium/blob/main/docs/guides/text-to-speech.md) · [Preferences](https://github.com/notalib/flutter_readium/blob/main/docs/guides/preferences.md) · [Highlights & Annotations](https://github.com/notalib/flutter_readium/blob/main/docs/guides/highlights-annotations.md) · [Search](https://github.com/notalib/flutter_readium/blob/main/docs/guides/search.md) · [Custom HTTP Headers](https://github.com/notalib/flutter_readium/blob/main/docs/guides/http-headers.md) · [Saving Progress](https://github.com/notalib/flutter_readium/blob/main/docs/guides/saving-progress.md) · [Error Handling](https://github.com/notalib/flutter_readium/blob/main/docs/guides/error-handling.md)
- **API Reference** — [FlutterReadium class](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/flutter-readium.md) · [ReaderWidget](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/reader-widget.md) · [Locator](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/locator.md) · [Preferences](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/preferences.md) · [Decorations](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/decorations.md) · [Streams & Events](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/streams-events.md) · [Publication](https://github.com/notalib/flutter_readium/blob/main/docs/api-reference/publication.md)
- **Architecture** — [Overview](https://github.com/notalib/flutter_readium/blob/main/docs/architecture.md)
- **Troubleshooting** — [Troubleshooting](https://github.com/notalib/flutter_readium/blob/main/docs/troubleshooting.md)

The generated Dart API reference is also published on [pub.dev](https://pub.dev/documentation/flutter_readium/latest/).

## Example app

A complete example app is available in the repository at [flutter_readium/example/](https://github.com/notalib/flutter_readium/tree/main/flutter_readium/example), demonstrating EPUB and audiobook reading, TTS, preferences, and highlighting.

## License

BSD 3-Clause — see [LICENSE](https://github.com/notalib/flutter_readium/blob/main/LICENSE).
