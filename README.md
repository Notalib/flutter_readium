# flutter_readium

A Flutter plugin for reading EPUB, audiobook, and WebPub publications, wrapping the [Readium](https://readium.org) toolkits behind a unified Dart API.

flutter_readium is a federated Flutter plugin that delegates to the upstream Readium toolkits on each platform:

- **swift-toolkit 3.7.0** on iOS (and macOS, planned)
- **kotlin-toolkit 3.1.2** on Android
- **ts-toolkit** (`@readium/shared`, `@readium/navigator`) on Web

## Features
- EPUB 2 / EPUB 3 reading, with dynamic horizontal pagination and vertical scrolling modes
- PDF reading on iOS (PDFKit) and Android (PDFium), with scroll / reading-progression preferences
- WebPub reading (including audiobook WebPub)
- Pre-recorded audio playback with track navigation and variable speed
- Synchronized Media Overlays in WebPubs (text-and-audio read-along)
- Platform-native text-to-speech with voice selection, speed, and pitch
- Reader preferences (typography, theme, scroll, columns, ...) via the Readium Preferences API
- Highlights and annotations via the Decorator API
- Position persistence and restoration via Locators
- Content search within open publications
- Real-time event streams for position, playback state, reader status, and errors
- Custom HTTP headers for publication and resource fetching

## Supported formats

| Format    | Visual       | TTS | Audio | Media Overlays         |
| --------- | :----------: | :-: | :---: | :--------------------: |
| EPUB 2    |      ✓       |  ✓  |   —   |           -            |
| EPUB 3    |      ✓       |  ✓  |   ✓   |           -            |
| WebPub    |      ✓       |  ✓  |   ✓   | ✓ (EPUB profile)       |
| Audiobook |      —       |  —  |   ✓   |           -            |
| PDF       | ✓ (iOS, Android) | — |  —   |           -            |

CBZ, DIVINA, and LCP-protected publications are not currently supported. The underlying toolkits include an LCP adapter; it may be enabled in a future release.

## Platform support

| Feature                  | Android | iOS | macOS     | Web        |
| ------------------------ | :-----: | :-: | :-------: | :--------: |
| EPUB visual reading      |    ✓    |  ✓  |  Planned  |     ✓      |
| PDF reading              |    ✓    |  ✓  |     —     |     —      |
| Audiobook playback       |    ✓    |  ✓  |  Planned  |     ✓      |
| Media Overlays           |    ✓    |  ✓  |  Planned  |     —      |
| Text-to-Speech           |    ✓    |  ✓  |  Planned  | Limited¹   |
| Highlights / decorations |    ✓    |  ✓  |  Planned  |     ✓      |
| Reader preferences       |    ✓    |  ✓  |  Planned  |     ✓      |
| PDF preferences          |    ✓    |  ✓  |     —     |     —      |
| Progress saving          |    ✓    |  ✓  |  Planned  |     ✓      |
| Content search           |    ✓    |  ✓  |  Planned  |     —      |
| Background audio         |    ✓    |  ✓  |  Planned  |     —      |

¹ Web TTS uses the browser's Web Speech API — voice availability and quality vary by browser.

See the [macOS setup section](#macos) below for the current platform status.

## Minimum requirements

| Requirement | Version                |
| ----------- | ---------------------- |
| Flutter     | 3.32.0+                |
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

Then complete the per-platform setup below. See [docs/getting-started/installation.md](docs/getting-started/installation.md) for the full installation guide and [docs/getting-started/quick-start.md](docs/getting-started/quick-start.md) for a 5-minute walkthrough.

### Android

- Set `minSdkVersion` to 24 or higher in `android/app/build.gradle`.
- Change your `MainActivity` to extend `FlutterFragmentActivity` (not `FlutterActivity`) — otherwise the reader view will crash at runtime.
- If using TTS or background audio, add to `android/app/src/main/AndroidManifest.xml`:

  ```xml
  <uses-permission android:name="android.permission.WAKE_LOCK" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
  ```

#### Build-time configuration

The Android plugin exposes the following Gradle properties. Set them in your
app's `android/gradle.properties` to override the defaults at build time:

| Property                                      | Default | Description                                                                                                                                                                                           |
| --------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flutterReadium.mediaOverlayFetchConcurrency` | `8`     | Max number of media-overlay JSON files the Sync Audiobook navigator fetches in parallel. Higher values speed up opening publications with many overlays at the cost of more concurrent HTTP requests. |

Example `android/gradle.properties`:

```properties
flutterReadium.mediaOverlayFetchConcurrency=16
```

### iOS

Add the Readium pods to your `ios/Podfile`:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'PromiseKit', '~> 8.1'

  pod 'ReadiumShared', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumShared.podspec'
  pod 'ReadiumInternal', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumInternal.podspec'
  pod 'ReadiumStreamer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumStreamer.podspec'
  pod 'ReadiumNavigator', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumNavigator.podspec'
  pod 'ReadiumOPDS', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumOPDS.podspec'
  pod 'ReadiumAdapterGCDWebServer', podspec: 'https://raw.githubusercontent.com/readium/swift-toolkit/3.7.0/Support/CocoaPods/ReadiumAdapterGCDWebServer.podspec'
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

NOTE: This may be unnecessary once we upgrade to swift-toolkit v3.9.0

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

Full documentation is in [docs/](docs/):

- **Getting Started** — [Installation](docs/getting-started/installation.md) · [Quick Start](docs/getting-started/quick-start.md) · [Core Concepts](docs/getting-started/concepts.md)
- **Guides** — [EPUB Reading](docs/guides/epub-reading.md) · [Audiobook Playback](docs/guides/audiobook-playback.md) · [Text-to-Speech](docs/guides/text-to-speech.md) · [Preferences](docs/guides/preferences.md) · [Highlights & Annotations](docs/guides/highlights-annotations.md) · [Search](docs/guides/search.md) · [Custom HTTP Headers](docs/guides/http-headers.md) · [Saving Progress](docs/guides/saving-progress.md) · [Error Handling](docs/guides/error-handling.md)
- **API Reference** — [FlutterReadium class](docs/api-reference/flutter-readium.md) · [ReaderWidget](docs/api-reference/reader-widget.md) · [Locator](docs/api-reference/locator.md) · [Preferences](docs/api-reference/preferences.md) · [Decorations](docs/api-reference/decorations.md) · [Streams & Events](docs/api-reference/streams-events.md) · [Publication](docs/api-reference/publication.md)
- **Architecture** — [Overview](docs/architecture.md)
- **Troubleshooting** — [Troubleshooting](docs/troubleshooting.md)

## Example app

A complete example app is available in [flutter_readium/example/](flutter_readium/example/), demonstrating EPUB and audiobook reading, TTS, preferences, and highlighting:

```bash
cd flutter_readium/example && flutter run
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, build scripts, and contribution guidelines.

## License

BSD 3-Clause — see [LICENSE](LICENSE).
