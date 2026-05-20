# flutter_readium

[![pub package](https://img.shields.io/pub/v/flutter_readium.svg)](https://pub.dev/packages/flutter_readium)
[![Quality](https://github.com/notalib/flutter_readium/actions/workflows/quality.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/quality.yml)
[![Tests](https://github.com/notalib/flutter_readium/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/test.yml)
[![Build Android](https://github.com/notalib/flutter_readium/actions/workflows/build-android.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/build-android.yml)
[![Build iOS](https://github.com/notalib/flutter_readium/actions/workflows/build-ios.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/build-ios.yml)
[![Build Web](https://github.com/notalib/flutter_readium/actions/workflows/build-web.yml/badge.svg?branch=main)](https://github.com/notalib/flutter_readium/actions/workflows/build-web.yml)

A Flutter plugin for reading EPUB, audiobook, and WebPub publications, wrapping the [Readium](https://readium.org) toolkits behind a unified Dart API.

flutter_readium is a federated Flutter plugin that delegates to the upstream Readium toolkits on each platform:

- **swift-toolkit 3.9.0** on iOS (and macOS, planned)
- **kotlin-toolkit 3.1.2** on Android
- **ts-toolkit** (`@readium/shared`, `@readium/navigator`) on Web

## Features

- EPUB 2 / EPUB 3 reading, with dynamic horizontal pagination and vertical scrolling modes
- WebPub reading (including audiobook WebPub)
- Pre-recorded audio playback with track navigation and variable speed
- Synchronized Media Overlays (text-and-audio read-along)
- Platform-native text-to-speech with voice selection, speed, and pitch
- Reader preferences (typography, theme, scroll, columns, ...) via the Readium Preferences API
- Highlights and annotations via the Decorator API
- Position persistence and restoration via Locators
- Content search within open publications
- Real-time event streams for position, playback state, reader status, and errors
- Custom HTTP headers for publication and resource fetching

## Supported formats

| Format    | Visual | TTS | Audio | Media Overlays |
| --------- | :----: | :-: | :---: | :------------: |
| EPUB 2    |   ✓    |  ✓  |   —   |       ✓        |
| EPUB 3    |   ✓    |  ✓  |   ✓   |       ✓        |
| WebPub    |   ✓    |  ✓  |   ✓   |       ✓        |
| Audiobook |   —    |  —  |   ✓   |       ✓        |

PDF, CBZ, DIVINA, and LCP-protected publications are not currently supported. The underlying toolkits include LCP and PDF adapters; they may be enabled in a future release.

## Platform support

| Feature                  | Android | iOS | macOS     | Web        |
| ------------------------ | :-----: | :-: | :-------: | :--------: |
| EPUB visual reading      |    ✓    |  ✓  |  Planned  |     ✓      |
| Audiobook playback       |    ✓    |  ✓  |  Planned  |     ✓      |
| Media Overlays           |    ✓    |  ✓  |  Planned  |     —      |
| Text-to-Speech           |    ✓    |  ✓  |  Planned  | Limited¹   |
| Highlights / decorations |    ✓    |  ✓  |  Planned  |     ✓      |
| Reader preferences       |    ✓    |  ✓  |  Planned  |     ✓      |
| Progress saving          |    ✓    |  ✓  |  Planned  |     ✓      |
| Content search           |    ✓    |  ✓  |  Planned  |     —      |
| Background audio         |    ✓    |  ✓  |  Planned  |     —      |

¹ Web TTS uses the browser's Web Speech API — voice availability and quality vary by browser.

See the [macOS setup section](#macos) below for the current platform status.

## Minimum requirements

| Requirement | Version                |
| ----------- | ---------------------- |
| Flutter     | 3.3.0+                 |
| Dart SDK    | 3.8.0+                 |
| Android     | `minSdkVersion` 24     |
| iOS         | 15.0+                  |
| macOS       | 10.15+ (planned)       |

## Getting started

Add the dependency to your app's `pubspec.yaml`:

```yaml
dependencies:
  flutter_readium: ^x.y.z
```

Then complete the per-platform setup below. See the [installation guide](https://github.com/notalib/flutter_readium/blob/main/docs/getting-started/installation.md) and the [quick-start walkthrough](https://github.com/notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md) for details.

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

Add the Readium pods to your `ios/Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'PromiseKit', '~> 8.1'

  pod 'ReadiumShared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumShared.podspec'
  pod 'ReadiumInternal', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumInternal.podspec'
  pod 'ReadiumStreamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumStreamer.podspec'
  pod 'ReadiumNavigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumNavigator.podspec'
  pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumOPDS.podspec'
  pod 'ReadiumAdapterGCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.9.0/Support/CocoaPods/ReadiumAdapterGCDWebServer.podspec'
  pod 'ReadiumZIPFoundation', podspec: 'https://raw.githubusercontent.com/readium/podspecs/refs/heads/main/ReadiumZIPFoundation/3.0.1/ReadiumZIPFoundation.podspec'

  # ...
end
```

To allow the local content server to serve publication resources, add to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true />
</dict>
```

### macOS

macOS is planned but not yet implemented. The plugin registers on macOS but reader functionality is unavailable.

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
