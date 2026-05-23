# Installation

## Requirements

| Requirement | Version |
|-------------|---------|
| Flutter SDK | ≥ 3.32.0 |
| Dart SDK | ≥ 3.8.0 |
| Android minSdk | 24 |
| iOS | 15.0+ |
| Xcode | 14+ |
| CocoaPods | 1.15+ |

## 1. Add the dependency

```yaml
dependencies:
  flutter_readium: ^0.0.1
```

```bash
flutter pub get
```

## 2. Android setup

### Minimum SDK

In `android/app/build.gradle`:

```gradle
android {
  defaultConfig {
    minSdkVersion 24
  }
}
```

### Fragment activity

The plugin uses platform views that require Fragment support. Change your `MainActivity` to extend `FlutterFragmentActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

Without this you will see: `MainActivity cannot be cast to androidx.fragment.app.FragmentActivity`.

### Optional permissions

For TTS and audiobook background playback, add to `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

## 3. iOS setup

### Podfile

Add the Readium pods to your `ios/Podfile` inside the `target 'Runner'` block.

To avoid version-drift, copy the exact Readium pod lines from:

- `flutter_readium/example/ios/Podfile` (app integration source-of-truth)
- and keep them aligned with `flutter_readium/ios/flutter_readium.podspec` (plugin pin)

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  pod 'PromiseKit', '~> 8.1'
  # Readium pod lines: copy from flutter_readium/example/ios/Podfile
end
```

Then run `pod install` (or `pod install --repo-update` on the first run).

### App Transport Security

Current swift-toolkit-based readers use a custom URL-scheme handler (no localhost web server), so `NSAppTransportSecurity` exceptions are not required for the plugin itself.

### Background audio (optional)

Add to `Info.plist` to keep audio playing when the app is backgrounded:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## 4. macOS

**Native macOS desktop is not supported.** Running `flutter run -d macos` will compile, but every reader call returns `MethodNotImplemented` — the upstream swift-toolkit is iOS-only and upstream has marked native macOS [`not_planned`](https://github.com/readium/swift-toolkit/issues/783). No setup is required or useful for the desktop target.

**To reach Mac users, ship the iOS build via "Designed for iPad."** Apple Silicon Macs (M1 and later) execute iOS .ipa binaries natively, and swift-toolkit is maintained with that mode in mind. Upload your iOS app to App Store Connect and keep the **Mac App Store → "Make this app available on Mac"** option enabled — Mac users can then install and run your reader app from the Mac App Store with no additional work.

This path supports Apple Silicon only (Intel Macs are excluded by Apple, not by this plugin).

## 5. Web setup

### Copy the JS bundle

Run once from your app root after installing the package:

```bash
dart run flutter_readium:copy_js_file <dest_dir>
```

This copies `readiumReader.js` into your chosen `dest_dir`. We recommend using the `web/` directory.

### Add script tags to index.html

```html
<head>
  <!-- Flutter init -->
  <script src="flutter.js" defer></script>
  <!-- Readium reader -->
  <script src="readiumReader.js" defer></script>
</head>
```

## Verification

```dart
import 'package:flutter_readium/flutter_readium.dart';

try {
  final pub = await FlutterReadium().openPublication('https://example.org/book.webpub');
  print('Opened: ${pub.metadata.title}');
} on ReadiumException catch (e) {
  print('Failed to open: $e');
}
```
