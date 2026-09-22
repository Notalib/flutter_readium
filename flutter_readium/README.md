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

Pass a publication URL (for example, a file or HTTPS URL) to this reader screen:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.publicationUrl});

  final String publicationUrl;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _readium = FlutterReadium();
  Publication? _publication;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final publication = await _readium.openPublication(widget.publicationUrl);
      if (!mounted) {
        await _readium.closePublication();
        return;
      }
      setState(() => _publication = publication);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    if (_publication != null) unawaited(_readium.closePublication());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_publication == null) return const Center(child: CircularProgressIndicator());
    return ReadiumReaderWidget(publication: _publication!);
  }
}
```

See the [five-minute walkthrough](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md)
for navigation, preferences, and position restoration. Complete the platform setup below before running.

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
- Enable core library desugaring in your app's Gradle build file. The Readium Android artifacts require it:

  ```kotlin
  android {
      compileOptions {
          isCoreLibraryDesugaringEnabled = true
      }
  }

  dependencies {
      coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
  }
  ```

  For Groovy Gradle files, see the [installation guide](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/installation.md).
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

Keep these pod versions aligned with the plugin's pin; do not override them independently.

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

For more detail, see the [installation guide](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/installation.md),
[reader walkthrough](https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md),
[feature guides](https://github.com/Notalib/flutter_readium/tree/main/docs/guides), and
[API reference](https://pub.dev/documentation/flutter_readium/latest/). For implementation details and toolkit
versions, see the [project README](https://github.com/Notalib/flutter_readium#how-it-works).

## Example app

A complete example app is available in the repository at [flutter_readium/example/](https://github.com/notalib/flutter_readium/tree/main/flutter_readium/example), demonstrating EPUB and audiobook reading, TTS, preferences, and highlighting.

## License

BSD 3-Clause — see [LICENSE](https://github.com/notalib/flutter_readium/blob/main/LICENSE).
