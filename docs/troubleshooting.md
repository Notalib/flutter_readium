# Troubleshooting

## Android: `MainActivity cannot be cast to FragmentActivity`

The plugin requires `FlutterFragmentActivity`. Change `MainActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

## Android: `minSdkVersion` build failure

Set `minSdkVersion 24` in `android/app/build.gradle`.

## iOS: pod install fails

```bash
cd ios
pod deintegrate
pod update && pod install --repo-update
```

If that doesn't help, delete `Podfile.lock` and retry.

## iOS: EPUB content not loading (blank screen)

Readium uses a local web server on `127.0.0.1`. Add to `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

## iOS: `MissingPluginException` on stream subscription

Event channels register lazily inside the native view initialiser. Subscribe to streams inside `onReady` or after the reader widget has mounted, not in `initState` before the view exists.

## Web: reader not showing / JS errors

1. Verify you ran `dart run flutter_readium:copy_js_file web/` after installing the package.
2. Check that both `flutter.js` and `readiumReader.js` script tags appear in `index.html`.
3. If the JS file path differs from `web/readiumReader.js`, update the `src` attribute.

## TTS not working on Android

TTS requires the Android TTS engine with the correct language data installed. If the device has no TTS engine, `ttsEnable` will throw. Check that Google Text-to-Speech (or another TTS engine) is installed and the required language pack is downloaded via device settings.

## Audio/TTS position drifts on restore

This is expected behavior on Android when the progression delta on restore is very small. The native side skips redundant scrolls when already within 1% of the target position. Use `cssSelector` or `domRange` in your saved locators for the most precise restoration.

## Publication fails to open

```dart
try {
  await reader.openPublication(url);
} on OpeningReadiumException catch (e) {
  print(e.type);    // notFound | formatNotSupported | forbidden | unknown
  print(e.message); // human-readable description
}
```

Common causes:
- File not found or URL typo (`notFound`)
- Unsupported format — only EPUB, WebPub, and audiobook are supported (`formatNotSupported`)
- DRM-protected content without a licence (`forbidden`)

## Getting debug logs

```dart
await FlutterReadium().setLogLevel(LogLevel.debug);
```

On native platforms, also filter logcat (Android) or the Xcode console (iOS) for the tag `flutter_readium`.
